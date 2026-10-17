<#
.SYNOPSIS
    Point the Claude Desktop APP (chat, Cowork and the Code tab) at OpenRouter, Hugging Face or the
    official Xiaomi MiMo endpoint — the desktop equivalent of claude-or.ps1 / claude-hf.ps1 /
    claude-mimo.ps1, which only cover the Claude Code CLI.

.DESCRIPTION
    Those CLI scripts inject ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN into the `claude` process.
    An already-installed Electron app cannot be handed environment variables that way, so the
    desktop app has its own supported switch: Developer > Configure Third-Party Inference, which
    persists a "gateway" document plus deploymentMode=3p in a separate user-data directory
    (%LOCALAPPDATA%\Claude-3p). This script writes exactly that state, from the command line,
    without touching your normal claude.ai login (%APPDATA%\Claude).

.PARAMETER Provider
    openrouter | hf | mimo | off | status

.PARAMETER KeyFile
    Override the key path. Defaults: ~/.claude/openrouter.key, ~/.claude/hf.key, ~/.claude/mimo.key
    — the same files the CLI launchers use, so there is one copy of each secret.

.PARAMETER DryRun
    Print the exact files/JSON that would be written and change nothing.

.PARAMETER Relaunch
    Quit Claude Desktop, write, then start it again (the app only reads this state at launch).

.PARAMETER Force
    Allow writing while Claude is running (state may be overwritten by the app on exit).

.PARAMETER UserDataDir
    Override the 3p user-data directory. Used by the test suite; you should not need it.

.EXAMPLE
    .\desktop-3p.ps1 openrouter -DryRun

.EXAMPLE
    .\desktop-3p.ps1 openrouter -Relaunch

.EXAMPLE
    .\desktop-3p.ps1 off -Relaunch
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('openrouter', 'hf', 'mimo', 'off', 'status')]
    [string]$Provider = 'status',

    [string]$KeyFile,
    [switch]$DryRun,
    [switch]$Relaunch,
    [switch]$Force,
    [switch]$ShowKey,
    [string]$UserDataDir
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ClaudeProviders.psm1') -Force

$providers = @{
    openrouter = @{
        Name    = 'OpenRouter'
        BaseUrl = 'https://openrouter.ai/api'
        KeyName = 'openrouter.key'
        Hint    = 'Get a key at https://openrouter.ai/keys'
    }
    hf         = @{
        Name    = 'Hugging Face'
        BaseUrl = 'https://router.huggingface.co'
        KeyName = 'hf.key'
        Hint    = 'Token needs the "Make calls to Inference Providers" permission'
    }
    mimo       = @{
        Name    = 'Xiaomi MiMo'
        BaseUrl = 'https://api.xiaomimimo.com/anthropic'
        KeyName = 'mimo.key'
        Hint    = 'Official Xiaomi endpoint, Anthropic-compatible'
    }
}

$layout = Get-Desktop3pLayout -UserDataDir $UserDataDir

if ($Provider -eq 'status') {
    Write-Host (Get-Desktop3pStatus -Layout $layout)
    return
}

$running = Get-ClaudeDesktopProcess
if ($running.Count -gt 0 -and -not ($Relaunch -or $Force) -and -not $DryRun) {
    throw ("Claude Desktop is running ({0} process(es)). The app rewrites this state on exit, so the change would be lost. Re-run with -Relaunch (recommended) or -Force." -f $running.Count)
}
if ($running.Count -gt 0 -and $DryRun) {
    Write-Warning ("Claude Desktop is running ({0} process(es)); -Relaunch would quit it first." -f $running.Count)
}

if ($Provider -eq 'off') {
    $report = Remove-Desktop3pManaged -Layout $layout -DryRun:$DryRun
    if ($DryRun) {
        Write-Host '--- would remove managed entries ---'
        if ($report.RemovedIds.Count -eq 0) { Write-Host '(none found)' } else { $report.RemovedIds | ForEach-Object { Write-Host $_ } }
        Write-Host ''
        Write-Host ("--- {0} ---" -f $layout.Deployment)
        Write-Host $report.DeployJson
        return
    }
    if ($Relaunch) {
        $null = Stop-ClaudeDesktop
        Start-Sleep -Milliseconds 600
        $null = Start-ClaudeDesktop
    }
    Write-Host 'Claude Desktop returned to its normal claude.ai login.' -ForegroundColor Green
    return
}

$spec = $providers[$Provider]
$keyPath = if ($KeyFile) { $KeyFile } else { Join-Path (Get-ClaudeHome) $spec.KeyName }
$key = Read-KeyFile -Path $keyPath
$doc = New-GatewayDocument -BaseUrl $spec.BaseUrl -ApiKey $key

$report = Set-Desktop3pGateway -Layout $layout -Name $spec.Name -Document $doc -DryRun:$DryRun

if ($DryRun) {
    Write-Host ("=== {0} ({1}) ===" -f $spec.Name, $Provider) -ForegroundColor Cyan
    Write-Host ("key      : {0} ({1} chars{2})" -f $keyPath, $key.Length, $(if ($ShowKey) { ', shown' } else { ', masked in this preview' }))
    Write-Host ("entry    : {0} [{1}]" -f $report.EntryName, $report.EntryId)
    # The credential is written inline by the app's own format, so keep it out of console output
    # unless explicitly asked for.
    $docPreview = if ($ShowKey) { $report.DocJson } else { $report.DocJson -replace [regex]::Escape($key), '<redacted>' }
    Write-Host ''
    Write-Host ("--- {0}" -f $report.DocPath)
    Write-Host $docPreview
    Write-Host ''
    Write-Host ("--- {0}" -f $report.MetaPath)
    Write-Host $report.MetaJson
    Write-Host ''
    Write-Host ("--- {0}" -f $report.DeployPath)
    Write-Host $report.DeployJson
    Write-Host ''
    Write-Host "Hint: $($spec.Hint)"
    return
}

if ($Relaunch) {
    $killed = Stop-ClaudeDesktop
    if ($killed -gt 0) { Write-Host ("Quit {0} Claude Desktop process(es)." -f $killed) }
    Start-Sleep -Milliseconds 600
    $target = Start-ClaudeDesktop
    Write-Host ("Started: {0}" -f $target)
}

Write-Host ("{0} is now the desktop app's inference gateway: {1}" -f $spec.Name, $spec.BaseUrl) -ForegroundColor Green
Write-Host ("entry {0} ({1}), applied in {2}" -f $report.EntryName, $report.EntryId, $report.MetaPath)
Write-Host 'At the start screen choose "Continue with Gateway" (shown as "Local configuration" in older builds).'
