---
name: claude-providers
description: >
  Point the Claude Desktop app, Claude Code and DeepSeek Harness at OpenRouter, Hugging Face or
  the Xiaomi MiMo endpoint, and revert to the normal claude.ai login. Use when the user says
  "use openrouter in claude desktop", "put my claude app on openrouter", "switch claude code to
  hugging face", "get my claude desktop back on my subscription", "change the provider of the
  claude app", "where is my claude desktop provider config". Edits app configuration and may quit
  and relaunch Claude Desktop, so preview with -DryRun before applying, and always offer the
  revert command. Windows only (the config paths are Windows-specific).
safety: elevated
platforms: [windows]
tools: [bash_exec]
category: system
tags: [claude, openrouter, huggingface, provider, gateway, windows]
activation_keywords: [provider, openrouter, huggingface, gateway]
activation_keywords_ru: [провайдер, опенроутер, переключи]
user_invocable: true
---

# claude-providers

<!--
  Root entry point.
  NAVIG's `navig skill install skill:owner/repo` copies THIS directory as the skill, so the
  procedure below addresses files relative to the repository root. The canonical skill (and what
  Claude Code / skills.sh / the plugin loader read) is skills/claude-providers/SKILL.md, which is
  the same document with paths relative to the skill folder. skills/claude-providers/scripts/test-scripts.ps1
  asserts that every path either copy references actually exists.
-->

Three surfaces, three providers, one command shape. Everything is PowerShell, lives in
`skills/claude-providers/scripts/`, and every action has a preview mode and a revert.

| Surface | What actually changes | Command |
| --- | --- | --- |
| Claude Desktop **app** (chat, Cowork, Code tab) | third-party inference document in `%LOCALAPPDATA%\Claude-3p` + `deploymentMode: "3p"` | `desktop-3p.ps1` |
| **Claude Code** (CLI + desktop Code tab) | `env` block in `~/.claude/settings.json` (via the user's `or-toggle.ps1`) | `code-desktop.ps1` |
| **DeepSeek Harness** | `llm-pi-ai` loader entry in `~/.dsh/profiles/<profile>/cordis.patch.yml` | `dsh-provider.ps1` |

Providers: `openrouter` (`https://openrouter.ai/api`), `hf` (`https://router.huggingface.co`),
`mimo` (`https://api.xiaomimimo.com/anthropic`). Keys are read from `~/.claude/openrouter.key`,
`hf.key`, `mimo.key` — never typed into the conversation, never echoed (previews mask them).

## Hard rules

<!--
  Root entry point.
  NAVIG's `navig skill install skill:owner/repo` copies THIS directory as the skill, so the
  procedure below addresses files relative to the repository root. The canonical skill (and what
  Claude Code / skills.sh / the plugin loader read) is skills/claude-providers/SKILL.md, which is
  the same document with paths relative to the skill folder. scripts/test-scripts.ps1 asserts that
  every path either copy references actually exists.
-->

1. **Preview first.** `-DryRun` prints the exact files and JSON, writes nothing, masks the key.
2. **Quit before writing.** The running desktop app rewrites this state on exit, so a write made
   behind its back is lost — `-Relaunch` quits, writes, restarts. `-Force` exists and is exactly
   that risk.
3. **Never delete the subscription login.** The desktop app's third-party state lives in a
   *separate* directory (`%LOCALAPPDATA%\Claude-3p`); `%APPDATA%\Claude` is untouched, so `off`
   always returns the user to the claude.ai login.
4. **Say what is app-wide.** The desktop provider choice is app-wide, not per-session: a user who
   expects per-chat providers will be surprised. Per session you change the *model* only.
5. **DSH is not a gateway.** It cannot be pointed at Claude Desktop, and Claude Desktop cannot be
   pointed at it. `dsh-provider.ps1` adds providers *inside* DSH.
6. **No secrets in output.** Do not print a key, do not paste one into a file that gets committed.

## Procedure

<!--
  Root entry point.
  NAVIG's `navig skill install skill:owner/repo` copies THIS directory as the skill, so the
  procedure below addresses files relative to the repository root. The canonical skill (and what
  Claude Code / skills.sh / the plugin loader read) is skills/claude-providers/SKILL.md, which is
  the same document with paths relative to the skill folder. scripts/test-scripts.ps1 asserts that
  every path either copy references actually exists.
-->

```powershell
# 1. what is configured right now (read-only)

<!--
  Root entry point.
  NAVIG's `navig skill install skill:owner/repo` copies THIS directory as the skill, so the
  procedure below addresses files relative to the repository root. The canonical skill (and what
  Claude Code / skills.sh / the plugin loader read) is skills/claude-providers/SKILL.md, which is
  the same document with paths relative to the skill folder. scripts/test-scripts.ps1 asserts that
  every path either copy references actually exists.
-->
pwsh -NoProfile -File skills/claude-providers/scripts/desktop-3p.ps1 status
pwsh -NoProfile -File skills/claude-providers/scripts/code-desktop.ps1 status
pwsh -NoProfile -File skills/claude-providers/scripts/dsh-provider.ps1 status

# 2. preview, always

<!--
  Root entry point.
  NAVIG's `navig skill install skill:owner/repo` copies THIS directory as the skill, so the
  procedure below addresses files relative to the repository root. The canonical skill (and what
  Claude Code / skills.sh / the plugin loader read) is skills/claude-providers/SKILL.md, which is
  the same document with paths relative to the skill folder. scripts/test-scripts.ps1 asserts that
  every path either copy references actually exists.
-->
pwsh -NoProfile -File skills/claude-providers/scripts/desktop-3p.ps1 openrouter -DryRun

# 3. apply (quits + restarts the app so it re-reads the state)

<!--
  Root entry point.
  NAVIG's `navig skill install skill:owner/repo` copies THIS directory as the skill, so the
  procedure below addresses files relative to the repository root. The canonical skill (and what
  Claude Code / skills.sh / the plugin loader read) is skills/claude-providers/SKILL.md, which is
  the same document with paths relative to the skill folder. scripts/test-scripts.ps1 asserts that
  every path either copy references actually exists.
-->
pwsh -NoProfile -File skills/claude-providers/scripts/desktop-3p.ps1 openrouter -Relaunch

# 4. verify by re-reading, never by trusting the write

<!--
  Root entry point.
  NAVIG's `navig skill install skill:owner/repo` copies THIS directory as the skill, so the
  procedure below addresses files relative to the repository root. The canonical skill (and what
  Claude Code / skills.sh / the plugin loader read) is skills/claude-providers/SKILL.md, which is
  the same document with paths relative to the skill folder. scripts/test-scripts.ps1 asserts that
  every path either copy references actually exists.
-->
pwsh -NoProfile -File skills/claude-providers/scripts/desktop-3p.ps1 status

# 5. revert

<!--
  Root entry point.
  NAVIG's `navig skill install skill:owner/repo` copies THIS directory as the skill, so the
  procedure below addresses files relative to the repository root. The canonical skill (and what
  Claude Code / skills.sh / the plugin loader read) is skills/claude-providers/SKILL.md, which is
  the same document with paths relative to the skill folder. scripts/test-scripts.ps1 asserts that
  every path either copy references actually exists.
-->
pwsh -NoProfile -File skills/claude-providers/scripts/desktop-3p.ps1 off -Relaunch
```

At the next start screen the app offers **Continue with Gateway** (older builds: "Local
configuration"); the model picker then lists that gateway's models.

## Provider mapping

<!--
  Root entry point.
  NAVIG's `navig skill install skill:owner/repo` copies THIS directory as the skill, so the
  procedure below addresses files relative to the repository root. The canonical skill (and what
  Claude Code / skills.sh / the plugin loader read) is skills/claude-providers/SKILL.md, which is
  the same document with paths relative to the skill folder. scripts/test-scripts.ps1 asserts that
  every path either copy references actually exists.
-->

- **OpenRouter** — app base URL `https://openrouter.ai/api` (Anthropic skin, bearer auth). Best when
  you want one bill across many model families; only Anthropic first-party models are guaranteed.
- **Hugging Face router** — `https://router.huggingface.co`; the token needs the *Make calls to
  Inference Providers* permission. Model ids are repo ids (`Org/Model`), and `:cheapest` / `:fastest`
  suffixes control routing.
- **Xiaomi MiMo (official)** — `https://api.xiaomimimo.com/anthropic`, Anthropic-compatible, no
  OpenRouter markup.

## When something looks wrong

<!--
  Root entry point.
  NAVIG's `navig skill install skill:owner/repo` copies THIS directory as the skill, so the
  procedure below addresses files relative to the repository root. The canonical skill (and what
  Claude Code / skills.sh / the plugin loader read) is skills/claude-providers/SKILL.md, which is
  the same document with paths relative to the skill folder. scripts/test-scripts.ps1 asserts that
  every path either copy references actually exists.
-->

| Symptom | First move |
| --- | --- |
| App shows a config error after a switch | `desktop-3p.ps1 off -Relaunch`, then fall back to the UI path (Help → Troubleshooting → Enable Developer Mode → Developer → Configure Third-Party Inference) |
| Change did not stick | The app was open: re-run with `-Relaunch` |
| Gateway works but the picker is empty | The gateway's `/v1/models` (or OpenRouter credits) — check the key has credit, not the script |
| Code tab ignores the switch | Code sessions read `~/.claude/settings.json` at start: restart the app, or `code-desktop.ps1 <mode> -Relaunch` |
| DSH provider lists models, calls fail auth | `apiKeyEnv` variable is unset in the DSH host: `dsh-provider.ps1 <provider> -SetEnvVar`, then restart DSH |

## References

<!--
  Root entry point.
  NAVIG's `navig skill install skill:owner/repo` copies THIS directory as the skill, so the
  procedure below addresses files relative to the repository root. The canonical skill (and what
  Claude Code / skills.sh / the plugin loader read) is skills/claude-providers/SKILL.md, which is
  the same document with paths relative to the skill folder. scripts/test-scripts.ps1 asserts that
  every path either copy references actually exists.
-->

- `references/schema.md` — the exact on-disk contract (3p document vs flat keys, `_meta.json`,
  `deploymentMode`, the `llm-pi-ai` YAML block), so you can read or debug a config by hand.
- `references/verification.md` — what the test suite proves, and the one thing it cannot (the app
  accepting the document), with the recovery path.
- `references/install.md` — installing this skill into Claude Code, NAVIG, DSH, Codex, Cursor, or
  plain `~/.claude/skills`.

## Self-check

<!--
  Root entry point.
  NAVIG's `navig skill install skill:owner/repo` copies THIS directory as the skill, so the
  procedure below addresses files relative to the repository root. The canonical skill (and what
  Claude Code / skills.sh / the plugin loader read) is skills/claude-providers/SKILL.md, which is
  the same document with paths relative to the skill folder. scripts/test-scripts.ps1 asserts that
  every path either copy references actually exists.
-->

```powershell
pwsh -NoProfile -File skills/claude-providers/scripts/test-scripts.ps1    # 10 checks, writes only inside a temp dir
```
