// Account balances from an Actual Budget sync server (via @actual-app/api,
// installed in ~/.local/share/quickshell/actual: `npm install @actual-app/api`).
// Reads its config as JSON on stdin (keeps passwords out of `ps`):
//   {url, password, budget (name or sync id), encryptionPassword?, dataDir}
// Prints {budget, budgets, accounts: [{name, balance, offbudget}]} or {error}.
// Balances are as of the server's last bank sync (no bank sync is triggered).
import { createRequire } from "node:module";
import { mkdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";

const base = (process.env.XDG_DATA_HOME || homedir() + "/.local/share") + "/quickshell/actual/";
const out = process.stdout.write.bind(process.stdout);
// the API logs to stdout: keep stdout for our JSON only
console.log = console.info = console.warn = (...a) => process.stderr.write(a.join(" ") + "\n");

async function main() {
    const cfg = JSON.parse(readFileSync(0, "utf8"));
    let api;
    try {
        api = createRequire(base)("@actual-app/api");
    } catch {
        throw new Error(`@actual-app/api missing: cd ${base} && npm install @actual-app/api`);
    }
    if (!cfg.url || !cfg.password) throw new Error("actual.url / actual.password not set (private.json)");
    mkdirSync(cfg.dataDir, { recursive: true });
    await api.init({ dataDir: cfg.dataDir, serverURL: cfg.url, password: cfg.password });
    try {
        const budgets = await api.getBudgets();
        const want = (cfg.budget || "").toLowerCase();
        const b = budgets.find(b => [b.name, b.groupId, b.cloudFileId, b.id].some(v => v && v.toLowerCase() === want))
               ?? (budgets.length === 1 || !want ? budgets.find(b => b.groupId) : null);
        if (!b) throw new Error(`budget "${cfg.budget}" not found (have: ${budgets.map(b => b.name).join(", ")})`);
        await api.downloadBudget(b.groupId, cfg.encryptionPassword ? { password: cfg.encryptionPassword } : undefined);
        const accounts = [];
        for (const a of await api.getAccounts()) {
            if (a.closed) continue;
            accounts.push({ name: a.name, balance: (await api.getAccountBalance(a.id)) / 100, offbudget: !!a.offbudget });
        }
        out(JSON.stringify({ budget: b.name, budgets: budgets.map(b => b.name), accounts }));
    } finally {
        await api.shutdown();
    }
}

main().catch(e => { out(JSON.stringify({ error: String(e?.message ?? e) })); process.exitCode = 1; });
