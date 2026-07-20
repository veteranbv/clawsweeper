import { readFileSync, writeFileSync } from "node:fs";

const [configPath] = process.argv.slice(2);
if (!configPath) throw new Error("target repository config path is required");

const config = JSON.parse(readFileSync(configPath, "utf8"));
if (!config.generic_fallbacks.some((entry) => entry.owner === "veteranbv")) {
  config.generic_fallbacks.push({
    owner: "veteranbv",
    deny_repositories: [],
    allow_repo_name_pattern: "^[A-Za-z0-9_.-]+$",
    prompt_note:
      "Synthetic proof fixture for the pinned ClawSweeper handler. Keep all review actions open.",
    apply_close_rules: { issue: [], pull_request: [] },
    package_manager: "pnpm",
    validation_commands: [],
    changed_gate: null,
  });
}
writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
