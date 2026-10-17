# claude-providers

Point the **Claude Desktop app**, **Claude Code** and **DeepSeek Harness** at OpenRouter, Hugging
Face or the Xiaomi MiMo endpoint — and get back to the normal claude.ai login with one command.

Ships as an **Agent Skill** (and a Claude Code / NAVIG plugin), so any agent that can read
`skills/<name>/SKILL.md` gets the procedure, the scripts and the verification with it.

## Why this exists

The usual way to move Claude Code to another provider is environment variables
(`ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`) — fine for the CLI and the editor extensions, but it
cannot redirect the **desktop app's** own chat, because that app is already running and cannot be
handed env vars after the fact. The desktop app instead persists an "inference gateway" document in
a separate directory (`%LOCALAPPDATA%\Claude-3p`). These scripts write exactly that state, and revert
it, without ever touching your subscription login (`%APPDATA%\Claude`).

## Commands

| Script | Surface |
| --- | --- |
| `desktop-3p.ps1 openrouter\|hf\|mimo\|off\|status` | Claude Desktop app — chat, Cowork and the Code tab (app-wide gateway) |
| `code-desktop.ps1 on\|hf\|mimo\|off\|status` | Claude Code CLI + the desktop Code tab (via `~/.claude/settings.json`) |
| `dsh-provider.ps1 openrouter\|hf\|off\|status` | DeepSeek Harness — registers a provider in `llm-pi-ai` |

All of them: `-DryRun` previews and masks the key, `-Relaunch` quits + restarts the app so it
re-reads state, `status` is read-only. Keys come from `~/.claude/openrouter.key`, `hf.key`,
`mimo.key`.

```powershell
pwsh -NoProfile -File skills/claude-providers/scripts/desktop-3p.ps1 status
pwsh -NoProfile -File skills/claude-providers/scripts/desktop-3p.ps1 openrouter -DryRun
pwsh -NoProfile -File skills/claude-providers/scripts/desktop-3p.ps1 openrouter -Relaunch
pwsh -NoProfile -File skills/claude-providers/scripts/desktop-3p.ps1 off -Relaunch
```

## Install

```powershell
npx skills add miztizm/claude-providers                                   # Agent Skills convention
git clone https://github.com/miztizm/claude-providers "$HOME\.claude\skills\claude-providers"
pwsh -NoProfile -File .\install.ps1 -Target claude,codex,cursor,dsh,navig
```

Claude Code plugin marketplace:

```
/plugin marketplace add miztizm/claude-providers
/plugin install claude-providers
```

NAVIG:

```powershell
navig skill install skill:miztizm/claude-providers
navig store install https://github.com/miztizm/claude-providers
```

Details per installer: [`skills/claude-providers/references/install.md`](skills/claude-providers/references/install.md).

## Verify

```powershell
pwsh -NoProfile -File skills/claude-providers/scripts/test-scripts.ps1   # 10/10, temp dir only
navig skill lint skills\claude-providers
```

What the suite proves — and the one thing it cannot (the app accepting the document), with the
recovery path — is in
[`references/verification.md`](skills/claude-providers/references/verification.md).

## Safety notes

- **The provider choice is app-wide, not per-session.** Per session you change the *model* only.
- **Quit before writing.** A running app rewrites this state on exit; `-Relaunch` is the safe path.
- **The desktop credential is stored inline** in the 3p document (`static` kind): a second plaintext
  copy of the key under `%LOCALAPPDATA%\Claude-3p\configLibrary\`. `off` removes it.
- **Nothing here is a proxy.** No request rewriting, no telemetry, no network calls of its own.
- Windows only: the config paths are Windows-specific.
- DSH reads keys from an environment variable (`apiKeyEnv`) — set it and restart DSH, or the
  provider lists models and every call fails auth.

## Layout

```
.claude-plugin/{plugin.json,marketplace.json}   Claude Code + NAVIG plugin manifests
skills/claude-providers/                        SKILL.md, evals.json, scripts/, references/
install.ps1                                     junction/copy into Claude, Codex, Cursor, DSH, NAVIG
```

The field-level contract the scripts target (and why it is where it is) is documented in
[`references/schema.md`](skills/claude-providers/references/schema.md).

MIT.
