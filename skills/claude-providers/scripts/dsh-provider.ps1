<#
.SYNOPSIS
    Register OpenRouter / Hugging Face as model providers inside DeepSeek Harness (DSH).

.DESCRIPTION
    DSH does not talk to Anthropic-style endpoints by env var; it has a provider layer
    (@deepseek-ai/dsh-llm-pi-ai) whose config is the loader entry `llm-pi-ai`. Providers are
    declared with `api` (openai-completions | openai-responses | anthropic-messages), `baseURL`,
    `apiKeyEnv` and a `models` list.

    This script owns a comment-delimited block in a profile's cordis.patch.yml:

        # >>> dsh-provider:openrouter (managed by claude-providers) >>>
        ...
        # <<< dsh-provider:openrouter <<<

    Comments are legal at the top level of a YAML sequence, so the block is inert when removed and
    the rest of the file is never touched. That also makes the edit verifiable without a YAML
    parser (the test suite asserts byte-identical text outside the block).

.PARAMETER Provider
    openrouter | hf | off | status

.PARAMETER Profile
    DSH profile name under ~/.dsh/profiles (web, desktop, acp, sdk). Default: every profile found.

.PARAMETER Models
    Model ids to advertise. Defaults match the lists used by your Claude Code launchers.

.PARAMETER EnvVar
    Environment variable DSH reads the key from. Default OPENROUTER_API_KEY / HF_TOKEN.

.PARAMETER SetEnvVar
    Also persist the variable for your user (setx, no elevation) from the key file. DSH must be
    restarted afterwards so the host process inherits it.

.PARAMETER DryRun
    Print the resulting file content and change nothing.

.EXAMPLE
    .\dsh-provider.ps1 openrouter -DryRun

.EXAMPLE
    .\dsh-provider.ps1 openrouter -SetEnvVar
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('openrouter', 'hf', 'off', 'status')]
    [string]$Provider = 'status',

    [string]$Profile,
    [string[]]$Models,
    [string]$EnvVar,
    [string]$KeyFile,
    [switch]$SetEnvVar,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ClaudeProviders.psm1') -Force

$spec = @{
    openrouter = @{
        Api        = 'openai-completions'
        BaseUrl    = 'https://openrouter.ai/api/v1'
        EnvVar     = 'OPENROUTER_API_KEY'
        KeyName    = 'openrouter.key'
        Display    = 'OpenRouter'
        Defaults   = @('xiaomi/mimo-v2.6-flash', 'deepseek/deepseek-v4.1-flash', 'moonshotai/kimi-k2.7-code')
    }
    hf         = @{
        Api        = 'openai-completions'
        BaseUrl    = 'https://router.huggingface.co/v1'
        EnvVar     = 'HF_TOKEN'
        KeyName    = 'hf.key'
        Display    = 'Hugging Face Router'
        Defaults   = @('zai-org/GLM-5.3-Flash', 'deepseek-ai/DeepSeek-V4-Pro', 'moonshotai/Kimi-K2.7-Code')
    }
}

$paths = Get-DshProfilePaths
if ($Profile) {
    $paths = @($paths | Where-Object { Split-Path -Leaf (Split-Path -Parent $_) -eq $Profile })
    if ($paths.Count -eq 0) { throw "No cordis.patch.yml for profile '$Profile' under ~/.dsh/profiles." }
}
else {
    # Default to the web profile only (the GUI these scripts were written against). Other profiles
    # may not load the llm-pi-ai plugin at all; add them explicitly with -Profile.
    $web = @($paths | Where-Object { Split-Path -Leaf (Split-Path -Parent $_) -eq 'web' })
    if ($web.Count -gt 0) { $paths = $web }
}
if ($paths.Count -eq 0) { throw 'No ~/.dsh/profiles/*/cordis.patch.yml found. Is DSH installed for this user?' }

Write-Host ("profiles : {0}" -f ($paths -join ', '))

if ($Provider -eq 'status') {
    foreach ($p in $paths) {
        $text = Get-Content -LiteralPath $p -Raw
        $has = $text -match '(?m)^# >>> dsh-provider:(?<p>[a-z]+)'
        if ($has) {
            $found = ([regex]::Matches($text, '(?m)^# >>> dsh-provider:([a-z]+)') | ForEach-Object { $_.Groups[1].Value }) -join ', '
            Write-Host ("  {0}: managed block present ({1})" -f $p, $found)
        }
        else {
            Write-Host ("  {0}: no managed block (DSH uses deepseek-account only)" -f $p)
        }
    }
    Write-Host ''
    Write-Host 'Keys live in environment variables DSH already inherits:'
    foreach ($k in @('OPENROUTER_API_KEY', 'HF_TOKEN')) {
        $v = [Environment]::GetEnvironmentVariable($k, 'User')
        $state = if ($v) { 'set (user scope)' } else { 'not set' }
        Write-Host ("  {0}: {1}" -f $k, $state)
    }
    return
}

if ($Provider -eq 'off') {
    foreach ($p in $paths) {
        $r = Remove-DshProviderBlock -Path $p -DryRun:$DryRun
        if ($DryRun) {
            Write-Host ("--- {0} (after removal) ---" -f $p)
            Write-Host $r.After
        }
        elseif ($r.Changed) { Write-Host ("Removed managed provider block from {0}" -f $p) }
        else { Write-Host ("No managed block in {0}" -f $p) }
    }
    if (-not $DryRun) { Write-Host 'Restart DSH to apply.' }
    return
}

$s = $spec[$Provider]
$modelList = if ($Models -and $Models.Count -gt 0) { $Models } else { $s.Defaults }
$envName = if ($EnvVar) { $EnvVar } else { $s.EnvVar }
$keyPath = if ($KeyFile) { $KeyFile } else { Join-Path (Get-ClaudeHome) $s.KeyName }

$block = New-DshProviderBlock -Provider $Provider -BaseUrl $s.BaseUrl -Api $s.Api -ApiKeyEnv $envName -Models $modelList -DisplayName $s.Display

foreach ($p in $paths) {
    $r = Set-DshProviderBlock -Path $p -Block $block -OtherProviders @('openrouter', 'hf') -DryRun:$DryRun
    if ($DryRun) {
        Write-Host ("--- {0} ---" -f $p)
        Write-Host $r.After
    }
    else {
        Write-Host ("Wrote managed provider block into {0}" -f $p)
    }
}

if ($SetEnvVar) {
    $key = Read-KeyFile -Path $keyPath
    if ($DryRun) {
        Write-Host ("would setx {0} <{1} chars from {2}>" -f $envName, $key.Length, $keyPath)
    }
    else {
        [Environment]::SetEnvironmentVariable($envName, $key, 'User')
        Write-Host ("Set user environment variable {0} (from {1})." -f $envName, $keyPath)
    }
}

if (-not $DryRun) {
    Write-Host ''
    Write-Host ("Provider '{0}' registered via {1} -> {2}" -f $Provider, $s.Api, $s.BaseUrl) -ForegroundColor Green
    if (-not $SetEnvVar) {
        $have = [Environment]::GetEnvironmentVariable($envName, 'User')
        if (-not $have) {
            Write-Warning ("{0} is not set. DSH reads the key from that variable: run this script again with -SetEnvVar, or set it yourself, then restart DSH." -f $envName)
        }
    }
    Write-Host 'Restart DSH so the new loader entry and environment variable are picked up.'
}
