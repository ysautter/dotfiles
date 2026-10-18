#!/usr/bin/env bash
# Waybar module: Claude subscription usage (5h session + 7d weekly).
# Uses the same endpoint as Claude Code's /usage command.

CREDS="${CLAUDE_CREDS:-$HOME/.claude/.credentials.json}"
ICON="✻"

out() { jq -cn --arg t "$1" --arg tt "$2" --arg c "$3" --argjson p "${4:-0}" \
    '{text:$t, tooltip:$tt, class:$c, percentage:$p}'; exit 0; }

STATE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-usage"
TOKEN_URL="https://platform.claude.com/v1/oauth/token"
CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"   # Claude Code's OAuth client
COOLDOWN=900                                        # s to wait after a failed refresh
mkdir -p "$STATE"

EXPIRED_MSG="Claude login token expired and auto-refresh failed.
Start Claude Code (claude) once to log in again."

now_ms() { date +%s%3N; }
expires_at() { jq -r '.claudeAiOauth.expiresAt // 0' "$CREDS"; }

# Renew the access token with the refresh token, like Claude Code does.
# Only called once the token is already expired (or rejected), so a running
# Claude Code, which renews before expiry, normally gets there first.
refresh_token() {
    exec 9>"$STATE/refresh.lock"
    flock -w 20 9 || return 1
    # Someone else (Claude Code or another run) may have renewed meanwhile.
    (( $(expires_at) > $(now_ms) + 60000 )) && [[ $1 != force ]] && return 0
    # Back off after a failure; the endpoint rate-limits aggressively.
    local fail="$STATE/refresh-failed"
    [[ -f $fail ]] && (( $(date +%s) - $(stat -c %Y "$fail") < COOLDOWN )) && return 1

    local rt resp tmp
    rt=$(jq -r '.claudeAiOauth.refreshToken // empty' "$CREDS")
    [[ -z $rt ]] && return 1
    resp=$(curl -s -m 15 -w '\n%{http_code}' "$TOKEN_URL" -H 'Content-Type: application/json' \
        -H 'User-Agent: claude-code/2.0.0' \
        -d "$(jq -cn --arg rt "$rt" --arg cid "$CLIENT_ID" \
            '{grant_type:"refresh_token", refresh_token:$rt, client_id:$cid}')")
    local code=${resp##*$'\n'}; resp=${resp%$'\n'*}
    if [[ $code != 200 || -z $(jq -r '.access_token // empty' <<<"$resp" 2>/dev/null) ]]; then
        # Error replies contain no tokens, so they are safe to log.
        echo "$(date -Is) HTTP $code $(head -c 300 <<<"$resp")" >>"$STATE/refresh-error.log"
        touch "$fail"; return 1
    fi

    # Write back atomically, keeping all other fields; refresh tokens rotate.
    cp -p "$CREDS" "$STATE/credentials.json.bak"
    tmp=$(mktemp "$CREDS.XXXXXX") || return 1
    chmod 600 "$tmp"
    jq --argjson r "$resp" --argjson now "$(now_ms)" '
        .claudeAiOauth.accessToken = $r.access_token
        | .claudeAiOauth.refreshToken = ($r.refresh_token // .claudeAiOauth.refreshToken)
        | .claudeAiOauth.expiresAt = ($now + ($r.expires_in // 3600) * 1000)
    ' "$CREDS" >"$tmp" && mv "$tmp" "$CREDS" || { rm -f "$tmp"; return 1; }
    rm -f "$fail"
}

[[ -n $(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS" 2>/dev/null) ]] \
    || out "$ICON n/a" "No Claude credentials in $CREDS" "error"

if (( $(expires_at) < $(now_ms) + 60000 )); then
    refresh_token || out "$ICON expired" "$EXPIRED_MSG" "error"
fi

fetch_usage() {
    local token
    token=$(jq -r '.claudeAiOauth.accessToken' "$CREDS")
    RESP=$(curl -s -m 10 -w '\n%{http_code}' https://api.anthropic.com/api/oauth/usage \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-code/2.0.0") || out "$ICON ?" "Claude usage: network error" "error"
    CODE=${RESP##*$'\n'}
    RESP=${RESP%$'\n'*}
}

fetch_usage
if [[ $CODE == 401 ]]; then   # token rejected although not expired: renew once
    refresh_token force && fetch_usage
    [[ $CODE == 401 ]] && out "$ICON expired" "$EXPIRED_MSG" "error"
fi
[[ $CODE != 200 ]] && out "$ICON ?" "Claude usage: HTTP $CODE" "error"

s_pct=$(jq -r '.five_hour.utilization // 0 | floor' <<<"$RESP")
s_reset=$(jq -r '.five_hour.resets_at // empty' <<<"$RESP")
w_pct=$(jq -r '.seven_day.utilization // 0 | floor' <<<"$RESP")
w_reset=$(jq -r '.seven_day.resets_at // empty' <<<"$RESP")

fmt() { [[ -n $1 ]] && date -d "$1" "$2" || echo "-"; }

tooltip="Session (5h): ${s_pct}% — resets $(fmt "$s_reset" '+%H:%M')
Weekly (7d):  ${w_pct}% — resets $(fmt "$w_reset" '+%a %d.%m %H:%M')"

if (( w_pct >= 100 )); then
    out "$ICON 100% ↻ $(fmt "$w_reset" '+%a %H:%M')" "$tooltip" "critical" 100
elif (( s_pct >= 100 )); then
    out "$ICON 100% ↻ $(fmt "$s_reset" '+%H:%M')" "$tooltip" "critical" 100
fi

class="normal"
(( s_pct >= 80 )) && class="warning"
out "$ICON ${s_pct}% ↻ $(fmt "$s_reset" '+%H:%M')" "$tooltip" "$class" "$s_pct"
