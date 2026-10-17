# Installing this skill, per installer

The repository is laid out to be consumed by every common skill/plugin installer **without changes**:

```
claude-providers/
├─ .claude-plugin/plugin.json       Claude Code / NAVIG plugin manifest
├─ .claude-plugin/marketplace.json  marketplace root (one-plugin catalog)
├─ skills/claude-providers/         the skill: SKILL.md + evals.json + scripts/ + references/
├─ install.ps1                      local installer (junction or copy)
└─ README.md
```

`skills/<name>/SKILL.md` is the position all of them look for, so nothing is duplicated per installer.

## Claude Code (CLI, desktop Code tab, VS Code extension)

```powershell
# as a plugin (updates stay linked to the repo)
/plugin marketplace add miztizm/claude-providers
# then
/plugin install claude-providers

# or as a plain user skill
git clone https://github.com/miztizm/claude-providers "$HOME\.claude\skills\claude-providers"
```

## skills.sh / `npx skills` (the Agent Skills convention)

```powershell
npx skills add miztizm/claude-providers
```

Installs into the agent's skills directory of your choice from the same `skills/claude-providers/`.

## NAVIG

```powershell
navig skill install skill:miztizm/claude-providers   # normalizes into ~/.navig/store/skills/<id>/
navig skill install .\claude-providers\skills\claude-providers   # from a local clone
navig store install https://github.com/miztizm/claude-providers  # as a plugin (health-gated)
navig plugin inspect .\claude-providers --json                   # health before installing
```

A valid plugin folder dropped into `~/.navig/plugins/` **is installed** — every loader scans that
root live. Skills are always free in NAVIG; nothing here is tier-gated (`"navig": { "tier": "free" }`).

## DeepSeek Harness

```powershell
pwsh -NoProfile -File .\install.ps1 -Target dsh
```

Copies the skill into `~/.dsh/skills/claude-providers`. Discovery of that directory is not verified
on every DSH build — if the skill does not appear in the harness catalog, register it through the
harness's own skill settings instead.

## Codex / Cursor / other agents

```powershell
pwsh -NoProfile -File .\install.ps1 -Target codex,cursor,claude,navig,dsh
```

| Target | Destination |
| --- | --- |
| `claude` | `~/.claude/skills/claude-providers` |
| `codex` | `~/.codex/skills/claude-providers` |
| `cursor` | `~/.cursor/skills/claude-providers` (best-effort; Cursor's skill support varies by version) |
| `dsh` | `~/.dsh/skills/claude-providers` |
| `navig` | `~/.navig/plugins/claude-providers` (plugin root, so `skills/` is picked up) |

Default is a **junction** (link, not copy) so `git pull` in the clone updates every agent at once;
pass `-Copy` where junctions are not wanted.

## Manual, no installer

Copy `skills/claude-providers/` into whatever directory your agent scans for skills. Nothing in the
skill imports the host it runs on, so there is no wiring step.
