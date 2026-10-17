# install.ps1 — put this skill where your agents look for skills.
#
#   pwsh -NoProfile -File .\install.ps1                      # Claude Code only
#   pwsh -NoProfile -File .\install.ps1 -Target claude,codex,dsh,navig,cursor
#   pwsh -NoProfile -File .\install.ps1 -Copy                # copy instead of junction
#
# Default is a junction (link, not copy) so `git pull` in this clone updates every agent at once.
# Existing destinations are never deleted silently: they are moved aside with a .bak-<stamp> suffix.
[CmdletBinding()]
param(
    # Comma-separated, so both `-Target claude,codex` (pwsh -File) and `-Target claude -Target codex` work.
    [string]$Target = 'claude',

    [switch]$Copy,

    # Override the skill source (defaults to skills/claude-providers next to this script).
    [string]$Source
)

$ErrorActionPreference = 'Stop'

$allowed = @('claude', 'codex', 'cursor', 'dsh', 'navig')
$Targets = @($Target -split '[,; ]+' | Where-Object { $_ })
foreach ($t in $Targets) {
    if ($allowed -notcontains $t) {
        throw ("unknown target '{0}'. Pick from: {1}" -f $t, ($allowed -join ', '))
    }
}
if ($Targets.Count -eq 0) { $Targets = @('claude') }

function Get-Dest([string]$Name) {
    switch ($Name) {
        'claude' { return (Join-Path $env:USERPROFILE '.claude\skills') }
        'codex' { return (Join-Path $env:USERPROFILE '.codex\skills') }
        'cursor' { return (Join-Path $env:USERPROFILE '.cursor\skills') }
        'dsh' { return (Join-Path $env:USERPROFILE '.dsh\skills') }
        'navig' { return (Join-Path $env:USERPROFILE '.navig\plugins') }
    }
    throw "unknown target '$Name'"
}

if (-not $Source) { $Source = Join-Path $PSScriptRoot 'skills\claude-providers' }
if (-not (Test-Path -LiteralPath (Join-Path $Source 'SKILL.md'))) {
    throw "No SKILL.md under '$Source'. Run this from a clone of the repository."
}
$Source = (Resolve-Path -LiteralPath $Source).Path

foreach ($t in $Targets) {
    $root = Get-Dest $t
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }

    # Claude/Codex/Cursor/DSH get the skill directory; NAVIG gets the plugin root (needs .claude-plugin).
    $payload = if ($t -eq 'navig') { $PSScriptRoot } else { $Source }
    $name = if ($t -eq 'navig') { 'claude-providers' } else { 'claude-providers' }
    $dest = Join-Path $root $name

    if (Test-Path -LiteralPath $dest) {
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $bak = "$dest.bak-$stamp"
        Move-Item -LiteralPath $dest -Destination $bak -Force
        Write-Host ("moved existing {0} -> {1}" -f $dest, $bak)
    }

    if ($Copy) {
        Copy-Item -LiteralPath $payload -Destination $dest -Recurse -Force
        Write-Host ("copied  {0} -> {1}" -f $payload, $dest)
    }
    else {
        try {
            # -ItemType Junction works without elevation on Windows for directories.
            New-Item -ItemType Junction -Path $dest -Target $payload -Force | Out-Null
            Write-Host ("linked  {0} -> {1}" -f $dest, $payload)
        }
        catch {
            Copy-Item -LiteralPath $payload -Destination $dest -Recurse -Force
            Write-Host ("copied  {0} -> {1} (junction unavailable)" -f $payload, $dest)
        }
    }

    $ok = (Test-Path -LiteralPath (Join-Path $dest 'SKILL.md')) -or (Test-Path -LiteralPath (Join-Path $dest 'skills\claude-providers\SKILL.md'))
    Write-Host ("  [{0}] {1}" -f $(if ($ok) { 'ok' } else { 'MISSING SKILL.md' }), $dest) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
}

Write-Host ''
Write-Host 'Verify with:'
Write-Host '  pwsh -NoProfile -File .\skills\claude-providers\scripts\test-scripts.ps1'
Write-Host 'Then ask your agent: "point claude desktop at openrouter" (it should preview with -DryRun first).'
