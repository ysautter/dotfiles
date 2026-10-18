#!/usr/bin/env bash
# Waybar module: Claude subscription usage (5h session + 7d weekly).
# Uses the same endpoint as Claude Code's /usage command.

CREDS="$HOME/.claude/.credentials.json"
ICON="✻"

out() { jq -cn --arg t "$1" --arg tt "$2" --arg c "$3" --argjson p "${4:-0}" \
    '{text:$t, tooltip:$tt, class:$c, percentage:$p}'; exit 0; }

TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS" 2>/dev/null)
[[ -z $TOKEN ]] && out "$ICON n/a" "No Claude credentials in $CREDS" "error"

EXPIRED_MSG="Claude login token expired.
Start Claude Code (claude) once to refresh it."

EXPIRES=$(jq -r '.claudeAiOauth.expiresAt // 0' "$CREDS")
(( EXPIRES > 0 && EXPIRES < $(date +%s%3N) )) && out "$ICON expired" "$EXPIRED_MSG" "error"

RESP=$(curl -s -m 10 -w '\n%{http_code}' https://api.anthropic.com/api/oauth/usage \
    -H "Authorization: Bearer $TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-code/2.0.0") || out "$ICON ?" "Claude usage: network error" "error"
CODE=${RESP##*$'\n'}
RESP=${RESP%$'\n'*}
[[ $CODE == 401 ]] && out "$ICON expired" "$EXPIRED_MSG" "error"
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
