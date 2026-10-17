<#
.SYNOPSIS
    Switch Claude Code — the CLI and the Code tab inside the Claude Desktop app — between
    OpenRouter, Hugging Face, the official Xiaomi MiMo API and the Claude subscription.

.DESCRIPTION
    The Code tab in Claude Desktop launches the same Claude Code engine, and that engine reads
    ~/.claude/settings.json (its `env` block), not the shell you started it from. So the existing
    ~/.claude/scripts/or-toggle.ps1 already covers the desktop Code tab as well as the CLI.

    This wrapper exists so the whole toolkit is driven the same way, and so the desktop app is
    relaunched (and therefore re-reads settings.json) after a switch. It delegates to your own
    or-toggle.ps1 — it does not reimplement the settings surgery.

.PARAMETER Mode
    on (OpenRouter) | hf | mimo | off (subscription) | status

.PARAMETER Relaunch
    Quit and restart Claude Desktop afterwards, so Code sessions pick the new env up immediately.

.PARAMETER DryRun
    Show which scripts/files would be touched and change nothing.

.EXAMPLE
    .\code-desktop.ps1 status

.EXAMPLE
    .\code-desktop.ps1 on -Relaunch
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('on', 'hf', 'mimo', 'off', 'status')]
    [string]$Mode = 'status',

    [switch]$Relaunch,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ClaudeProviders.psm1') -Force

$toggle = Join-Path (Get-ClaudeHome) 'scripts\or-toggle.ps1'
$settings = Join-Path (Get-ClaudeHome) 'settings.json'

if (-not (Test-Path -LiteralPath $toggle)) {
    throw "Not found: $toggle. Re-copy your or-toggle.ps1 there, or use desktop-3p.ps1 (app-wide gateway) instead."
}

Write-Host ("or-toggle : {0}" -f $toggle)
Write-Host ("settings  : {0}" -f $settings)

if ($DryRun) {
    Write-Host ''
    Write-Host ("would run : pwsh -NoProfile -File `"{0}`" {1}" -f $toggle, $Mode)
    if ($Relaunch) { Write-Host 'would then quit + start Claude Desktop' }
    return
}

if ($Mode -eq 'status') {
    & $toggle status
    return
}

& $toggle $Mode
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "or-toggle.ps1 $Mode failed with exit code $LASTEXITCODE." }

if ($Relaunch) {
    $killed = Stop-ClaudeDesktop
    if ($killed -gt 0) { Write-Host ("Quit {0} Claude Desktop process(es)." -f $killed) }
    Start-Sleep -Milliseconds 600
    Write-Host ("Started: {0}" -f (Start-ClaudeDesktop))
}
else {
    Write-Host 'If Claude Desktop is already open: restart it (or "Developer: Reload Window") before new Code sessions.'
}
