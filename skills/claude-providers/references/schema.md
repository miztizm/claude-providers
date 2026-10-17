# The on-disk contract

Everything below was recovered by inspecting the shipped app bundle and the loader schema delivered
by the host at the time of writing — not from public documentation. Treat it as the contract the
scripts target, and re-check it after a Claude Desktop major update.

## 1. Claude Desktop — third-party inference

The app keeps first-party and third-party state in **separate directories**, which is why switching
providers never touches the subscription session:

```
%APPDATA%\Claude\                    normal claude.ai login (never written by these scripts)
%LOCALAPPDATA%\Claude-3p\             third-party ("3p") user data
├─ claude_desktop_config.json         { "deploymentMode": "3p" }
└─ configLibrary\
   ├─ _meta.json                      { "appliedId": "<uuid>", "entries": [{ "id": "<uuid>", "name": "OpenRouter" }] }
   └─ <uuid>.json                     the inference document
```

`deploymentMode` accepts `"3p"` or `"1p"`; anything unset means the app shows its normal login.
Entry ids are UUIDs (`^[a-f0-9-]{36}$`).

### The document

The app's field vocabulary is `inference*`. Two shapes carry the same values — the nested form its
own editor writes, and the flat form used by the managed/policy reader. The scripts emit **both** so
either reader resolves the same gateway; unknown keys are warned about, not fatal.

```json
{
  "inference": {
    "provider": "gateway",
    "baseUrl": "https://openrouter.ai/api",
    "authScheme": "bearer",
    "credential": { "kind": "static", "apiKey": "sk-or-v1-…" }
  },
  "inferenceProvider": "gateway",
  "inferenceGatewayBaseUrl": "https://openrouter.ai/api",
  "inferenceGatewayApiKey": "sk-or-v1-…",
  "inferenceGatewayAuthScheme": "bearer",
  "inferenceCredentialKind": "static"
}
```

Other providers the same schema accepts (not used by these scripts): `vertex`, `bedrock`, `foundry`,
plus credential kinds `interactive` (vendor sign-in), `external-idp` (OIDC), `helper-script` (a
command that prints the secret), `vendor-profile`, `workforce`.

Why `helper-script` is not the default here: it is the cleaner option (no key copy on disk), but it
is only worth its complexity once someone needs key rotation without restarting the app. The static
kind matches what the user's existing CLI launchers already do (`~/.claude/*.key` plus a plaintext
copy in `~/.claude/settings.json`).

### Why a separate directory matters for `off`

`off` removes our config-library entries and their documents, drops `deploymentMode` to `1p`, and
leaves `%APPDATA%\Claude` completely alone. Nothing in the claude.ai session, history or login is
touched by any mode of these scripts.

## 2. Claude Code — `~/.claude/settings.json`

The desktop app's Code tab runs the same Claude Code engine, which reads the `env` block at session
start:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://openrouter.ai/api",
    "ANTHROPIC_AUTH_TOKEN": "sk-or-v1-…",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "xiaomi/mimo-v2.6-flash",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek/deepseek-v4.1-flash"
  },
  "modelPicker": { "replaceBuiltInOptions": true, "options": [ … ] }
}
```

The file is **strict JSON** (no comments) and **must not start with a BOM** — Claude Code rejects a
BOM. That is why the scripts write UTF-8 without BOM everywhere, and why `code-desktop.ps1` delegates
to the user's `or-toggle.ps1`, which already owns the marker-based surgery on that file.

## 3. DeepSeek Harness — `llm-pi-ai`

DSH's provider layer is the loader entry `llm-pi-ai`
(`@deepseek-ai/dsh-llm-pi-ai`), configured by a `providers` map:

```yaml
providers:
  openrouter:
    displayName: "OpenRouter"
    api: openai-completions      # openai-completions | openai-responses | anthropic-messages
    baseURL: https://openrouter.ai/api/v1
    apiKeyEnv: OPENROUTER_API_KEY
    models:
      - id: xiaomi/mimo-v2.6-flash
```

- `apiKeyEnv` is the *name* of an environment variable the DSH **host process** reads at startup —
  not a value. Set it in the environment and restart DSH, or the provider lists models and every
  call fails auth.
- Optional per-model keys: `name`, `contextWindow`, `maxTokens`, `input` (`text`/`image`),
  `reasoningEfforts`, `compat.*`, `transport`, `timeoutMs`, `streamIdleTimeoutMs`, `retryPolicy`.
- The block is written into `~/.dsh/profiles/<profile>/cordis.patch.yml`, between comment markers:

```yaml
# >>> dsh-provider:openrouter (managed by claude-providers) >>>
…
# <<< dsh-provider:openrouter <<<
```

A profile with no patches holds a bare `[]`; appending after it would create two YAML roots, so the
script replaces that placeholder and keeps the comment header. Removal restores the file
byte-for-byte (or back to `[]`), which the test suite asserts.
