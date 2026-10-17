# What is verified, and the one thing that is not

`scripts/test-scripts.ps1` is the gate. It writes **only** inside a temp directory, launches no app,
and quits nothing. 10 checks, all passing on Windows 11 / PowerShell 7 / Claude Desktop 2.26454.2.

| # | Check | What it proves |
| --- | --- | --- |
| 1 | syntax | every `.ps1`/`.psm1` parses with zero PowerShell parse errors |
| 2 | module exports | `ClaudeProviders.psm1` exports everything the scripts call |
| 3 | dry-run | `desktop-3p.ps1 -DryRun` prints the 3p document, `_meta.json` and `claude_desktop_config.json`, and writes nothing |
| 4 | apply (sandbox) | files exist, are valid JSON, **no BOM**, `appliedId` is a UUID, one entry, `deploymentMode: "3p"`, `inference.provider: "gateway"` |
| 5 | idempotency | a second apply does not duplicate the config-library entry |
| 6 | revert | `off` removes the managed entry + document and leaves the app out of 3p mode |
| 7 | dsh reversibility | block inserts once; removal restores the file byte-for-byte; text above the block unchanged |
| 7b | empty profile | a `[]` patch file becomes a single YAML root, comments preserved; revert restores `[]` |
| 8 | real state | `%LOCALAPPDATA%\Claude-3p`, `~/.claude/settings.json` and every `~/.dsh/profiles/*/cordis.patch.yml` hash identical before/after |
| 9 | wrapper | `code-desktop.ps1 -DryRun` touches nothing |

## The gap: the app accepting the document

Check 4 proves the document is well-formed and shaped like the schema recovered from the bundle. It
cannot prove that the **shipped app** accepts *this* document — that requires launching Claude
Desktop with the state applied, which is a real config change and therefore a decision the user
makes, not the test suite.

Failure mode if a future build renames a field is loud and recoverable, not silent:

1. the app reports a third-party configuration error (the bundle logs `custom3p_config_error_class`
   and surfaces it in the start screen), and
2. `desktop-3p.ps1 off -Relaunch` restores the normal claude.ai login — the first-party directory
   was never touched — and
3. the UI path still works: **Help → Troubleshooting → Enable Developer Mode → Developer →
   Configure Third-Party Inference**, with the same base URL / bearer / static key values the script
   prints in `-DryRun`.

## How to close the gap yourself

```powershell
pwsh -NoProfile -File scripts/desktop-3p.ps1 openrouter -DryRun   # read the JSON
pwsh -NoProfile -File scripts/desktop-3p.ps1 openrouter -Relaunch # apply for real
pwsh -NoProfile -File scripts/desktop-3p.ps1 status               # confirm what the app now has
```

If the start screen does not offer **Continue with Gateway**, that build does not read the document
these scripts write — use the UI path, and open an issue with the app version.

## Deliberate non-goals

- No proxying, no request rewriting, no token accounting: the app talks straight to the provider.
- No key management beyond reading `~/.claude/*.key`; nothing invents, rotates or uploads a key.
- No navig imports, no daemon, no network calls of its own.
- No per-session provider switching — the desktop app has no such concept; only the model is
  per-session.
