<#
.SYNOPSIS
    Test suite for the claude-providers toolkit. Writes only inside a temp directory.

.DESCRIPTION
    Checks, in this order:
      1. syntax  — every .ps1/.psm1 parses with zero PowerShell parse errors
      2. module  — ClaudeProviders.psm1 imports and exports what the scripts call
      3. dry-run — desktop-3p.ps1 prints the exact 3p document/meta/deployment JSON and writes nothing
      4. apply   — against a temp -UserDataDir: files exist, are valid JSON, no BOM, schema-shaped
      5. idempot — a second apply does not duplicate the config-library entry
      6. revert  — "off" drops the managed entry and clears deploymentMode
      7. dsh     — managed block insert is reversible and leaves surrounding text byte-identical
      8. safety  — the real %LOCALAPPDATA%\Claude-3p, ~/.claude/settings.json and every
                   ~/.dsh/profiles/*/cordis.patch.yml are unchanged afterwards
      9. wrapper — code-desktop.ps1 -DryRun touches nothing

    No app is launched, nothing is quit, no key is sent anywhere.

.EXAMPLE
    pwsh -NoProfile -File .\test-scripts.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$results = New-Object System.Collections.Generic.List[object]

function Add-Result([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $results.Add([pscustomobject]@{ Test = $Name; Ok = $Ok; Detail = $Detail })
    $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { " — $Detail" } else { '' })) -ForegroundColor $color
}

function Get-TextHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '<missing>' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-DirFingerprint([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '<missing>' }
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)
    if ($files.Count -eq 0) { return '<empty>' }
    return (($files | ForEach-Object { $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join '|')
}

function Test-NoBom([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return $false }
    return $true
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("claude-providers-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null

try {
    # ------------------------------------------------------------------ safety baseline
    $real3p = Join-Path $env:LOCALAPPDATA 'Claude-3p'
    $realSettings = Join-Path $env:USERPROFILE '.claude\settings.json'
    $realDsh = @(Get-ChildItem (Join-Path $env:USERPROFILE '.dsh\profiles') -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'cordis.patch.yml' } | Where-Object { Test-Path -LiteralPath $_ })

    $before = @{
        ThreeP   = Get-DirFingerprint $real3p
        Settings = Get-TextHash $realSettings
        Dsh      = (@($realDsh | ForEach-Object { Get-TextHash $_ }) -join '|')
    }

    # ------------------------------------------------------------------ 1. syntax
    $files = @(Get-ChildItem -LiteralPath $here -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') })
    $syntaxProblems = New-Object System.Collections.Generic.List[string]
    foreach ($f in $files) {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
        foreach ($e in $errors) {
            $syntaxProblems.Add(("{0}:{1}: {2}" -f $f.Name, $e.Extent.StartLineNumber, $e.Message))
        }
    }
    Add-Result '1. syntax (all .ps1/.psm1 parse)' ($syntaxProblems.Count -eq 0) ($syntaxProblems -join '; ')

    # ------------------------------------------------------------------ 2. module surface
    $modulePath = Join-Path $here 'ClaudeProviders.psm1'
    Import-Module $modulePath -Force
    $needed = @('Get-Desktop3pLayout', 'Read-KeyFile', 'New-GatewayDocument', 'Set-Desktop3pGateway',
        'Remove-Desktop3pManaged', 'Get-Desktop3pStatus', 'Get-ClaudeDesktopProcess',
        'New-DshProviderBlock', 'Set-DshProviderBlock', 'Remove-DshProviderBlock', 'Get-DshProfilePaths')
    $exported = @(Get-Command -Module ClaudeProviders | Select-Object -ExpandProperty Name)
    $missing = @($needed | Where-Object { $exported -notcontains $_ })
    Add-Result '2. module exports' ($missing.Count -eq 0) ($missing -join ', ')

    # ------------------------------------------------------------------ 3. dry run
    $fakeKey = Join-Path $temp 'fake-or.key'
    Set-Content -LiteralPath $fakeKey -Value 'sk-or-v1-test-only-not-a-real-key' -NoNewline -Encoding ascii
    $sandbox = Join-Path $temp 'Claude-3p'
    New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

    $dryOut = & (Join-Path $here 'desktop-3p.ps1') openrouter -KeyFile $fakeKey -UserDataDir $sandbox -DryRun 6>&1 | Out-String
    $dryOk = ($dryOut -match 'inferenceGatewayBaseUrl') -and ($dryOut -match '"deploymentMode":\s*"3p"') -and
             ($dryOut -match '"provider":\s*"gateway"') -and ($dryOut -match 'https://openrouter\.ai/api')
    $wroteNothing = -not (Test-Path -LiteralPath (Join-Path $sandbox 'configLibrary\_meta.json'))
    Add-Result '3. dry-run output + no writes' ($dryOk -and $wroteNothing) $(if (-not $dryOk) { 'expected JSON/providers missing from output' } else { "leaked=$($wroteNothing -eq $false)" })

    # ------------------------------------------------------------------ 4. apply into sandbox
    # -Force: Claude Desktop is running on this machine; the sandbox dir makes the write harmless.
    $applyOut = & (Join-Path $here 'desktop-3p.ps1') openrouter -KeyFile $fakeKey -UserDataDir $sandbox -Force 6>&1 | Out-String
    $metaPath = Join-Path $sandbox 'configLibrary\_meta.json'
    $deployPath = Join-Path $sandbox 'claude_desktop_config.json'
    $applyProblems = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $metaPath)) { $applyProblems.Add('_meta.json missing') }
    if (-not (Test-Path -LiteralPath $deployPath)) { $applyProblems.Add('claude_desktop_config.json missing') }
    $meta = $null
    $deploy = $null
    if (Test-Path -LiteralPath $metaPath) {
        $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
        if (-not (Test-NoBom $metaPath)) { $applyProblems.Add('_meta.json has BOM') }
        if (-not ($meta.appliedId -match '^[a-f0-9-]{36}$')) { $applyProblems.Add('appliedId is not a uuid') }
        if (@($meta.entries).Count -ne 1) { $applyProblems.Add("entries=$(@($meta.entries).Count)") }
        if (@($meta.entries)[0].name -ne 'OpenRouter') { $applyProblems.Add('entry name wrong') }
        $docPath = Join-Path $sandbox ('configLibrary\' + $meta.appliedId + '.json')
        if (-not (Test-Path -LiteralPath $docPath)) { $applyProblems.Add('document file missing') }
        else {
            $doc = Get-Content -LiteralPath $docPath -Raw | ConvertFrom-Json
            if (-not (Test-NoBom $docPath)) { $applyProblems.Add('document has BOM') }
            if ($doc.inference.provider -ne 'gateway') { $applyProblems.Add('inference.provider != gateway') }
            if ($doc.inference.baseUrl -ne 'https://openrouter.ai/api') { $applyProblems.Add('inference.baseUrl wrong') }
            if ($doc.inferenceCredentialKind -ne 'static') { $applyProblems.Add('flat credential kind wrong') }
            if ($doc.inferenceGatewayApiKey -ne 'sk-or-v1-test-only-not-a-real-key') { $applyProblems.Add('flat api key not echoed') }
        }
    }
    if (Test-Path -LiteralPath $deployPath) {
        $deploy = Get-Content -LiteralPath $deployPath -Raw | ConvertFrom-Json
        if ($deploy.deploymentMode -ne '3p') { $applyProblems.Add('deploymentMode != 3p') }
        if (-not (Test-NoBom $deployPath)) { $applyProblems.Add('deployment json has BOM') }
    }
    Add-Result '4. apply -> valid 3p state' ($applyProblems.Count -eq 0) ($applyProblems -join '; ')

    # ------------------------------------------------------------------ 5. idempotency
    $null = & (Join-Path $here 'desktop-3p.ps1') openrouter -KeyFile $fakeKey -UserDataDir $sandbox -Force 6>&1
    $meta2 = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
    Add-Result '5. second apply is idempotent' (@($meta2.entries).Count -eq 1 -and $meta2.appliedId -eq $meta.appliedId) `
        ("entries=$(@($meta2.entries).Count)")

    # ------------------------------------------------------------------ 6. revert
    $offOut = & (Join-Path $here 'desktop-3p.ps1') off -UserDataDir $sandbox -Force 6>&1 | Out-String
    $offProblems = New-Object System.Collections.Generic.List[string]
    $deployAfter = if (Test-Path -LiteralPath $deployPath) { Get-Content -LiteralPath $deployPath -Raw | ConvertFrom-Json } else { $null }
    $modeAfter = if ($null -ne $deployAfter -and $deployAfter.PSObject.Properties.Name -contains 'deploymentMode') { [string]$deployAfter.deploymentMode } else { '' }
    if ($modeAfter -eq '3p') { $offProblems.Add('still in 3p mode') }
    elseif ($modeAfter -notin @('', '1p')) { $offProblems.Add("unexpected deploymentMode '$modeAfter'") }
    if ((Test-Path -LiteralPath $metaPath) -and @((Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json).entries).Count -gt 0) { $offProblems.Add('entry not removed') }
    $leftoverDocs = @(Get-ChildItem -LiteralPath (Join-Path $sandbox 'configLibrary') -Filter '*.json' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne '_meta.json' })
    if ($leftoverDocs.Count -gt 0) { $offProblems.Add("orphan docs: $($leftoverDocs.Name -join ',')") }
    Add-Result '6. off -> back to claude.ai login' ($offProblems.Count -eq 0) ($offProblems -join '; ')

    # ------------------------------------------------------------------ 7. dsh managed block
    # Use the web profile (a non-empty patch list) so "text above the block is unchanged" is a real
    # assertion; the empty-`[]` case is covered separately in 7b.
    $sample = @($realDsh | Where-Object { $_ -match '[\\/]web[\\/]' }) + @($realDsh | Where-Object { $_ -notmatch '[\\/]web[\\/]' })
    $sample = @($sample | Where-Object { (Get-Content -LiteralPath $_ -Raw) -match '(?m)^-\s+id:' }) | Select-Object -First 1
    $yaml = Join-Path $temp 'cordis.patch.yml'
    if ($sample) { Copy-Item -LiteralPath $sample -Destination $yaml -Force }
    else { Set-Content -LiteralPath $yaml -Value "# empty patch layer`n- id: agent-default-model`n  config:`n    provider: deepseek-account`n" -Encoding utf8NoBOM }

    $originalYaml = Get-Content -LiteralPath $yaml -Raw
    $block = New-DshProviderBlock -Provider openrouter -BaseUrl 'https://openrouter.ai/api/v1' `
        -Api 'openai-completions' -ApiKeyEnv 'OPENROUTER_API_KEY' -Models @('xiaomi/mimo-v2.6-flash') -DisplayName 'OpenRouter'
    $ins1 = Set-DshProviderBlock -Path $yaml -Block $block -OtherProviders @('openrouter', 'hf')
    $after1 = Get-Content -LiteralPath $yaml -Raw
    $ins2 = Set-DshProviderBlock -Path $yaml -Block $block -OtherProviders @('openrouter', 'hf')
    $after2 = Get-Content -LiteralPath $yaml -Raw
    $blockCount = ([regex]::Matches($after2, '(?m)^# >>> dsh-provider:openrouter')).Count

    # Removing the block again must restore the original byte-for-byte.
    $null = Remove-DshProviderBlock -Path $yaml -Providers @('openrouter', 'hf')
    $restored = Get-Content -LiteralPath $yaml -Raw
    $dshProblems = New-Object System.Collections.Generic.List[string]
    if ($blockCount -ne 1) { $dshProblems.Add("blocks=$blockCount (expected 1)") }
    if ($after1 -ne $after2) { $dshProblems.Add('second insert changed the file') }
    if (-not ($after1.StartsWith($originalYaml.TrimEnd()))) { $dshProblems.Add('original text not preserved above the block') }
    if ($after1 -notmatch 'apiKeyEnv: OPENROUTER_API_KEY') { $dshProblems.Add('apiKeyEnv missing') }
    if ($after1 -notmatch 'baseURL: https://openrouter\.ai/api/v1') { $dshProblems.Add('baseURL missing') }
    if ($restored.TrimEnd() -ne $originalYaml.TrimEnd()) { $dshProblems.Add('removal did not restore the original text') }
    if (-not (Test-NoBom $yaml)) { $dshProblems.Add('yaml has BOM') }
    Add-Result '7. dsh block insert/remove is reversible' ($dshProblems.Count -eq 0) ($dshProblems -join '; ')

    # ------------------------------------------------------------------ 7b. empty (`[]`) profile
    $emptyYaml = Join-Path $temp 'cordis-empty.yml'
    $header = "# Your patch layer for this dsh profile.`n# comments must survive.`n"
    Set-Content -LiteralPath $emptyYaml -Value ($header + "[]`n") -NoNewline -Encoding utf8NoBOM
    $null = Set-DshProviderBlock -Path $emptyYaml -Block $block -OtherProviders @('openrouter', 'hf')
    $emptyAfter = Get-Content -LiteralPath $emptyYaml -Raw
    $null = Remove-DshProviderBlock -Path $emptyYaml -Providers @('openrouter', 'hf')
    $emptyRestored = Get-Content -LiteralPath $emptyYaml -Raw
    $emptyProblems = New-Object System.Collections.Generic.List[string]
    $bareArray = @($emptyAfter -split "\r?\n" | Where-Object { $_.Trim() -eq '[]' }).Count
    if ($bareArray -ne 0) { $emptyProblems.Add('bare [] survived, so the file would hold two YAML roots') }
    if ($emptyAfter -notmatch 'comments must survive') { $emptyProblems.Add('comment header lost') }
    if ($emptyAfter -notmatch 'llm-pi-ai-openrouter') { $emptyProblems.Add('block missing') }
    if (@($emptyRestored -split "\r?\n" | Where-Object { $_.Trim() -eq '[]' }).Count -ne 1) { $emptyProblems.Add('empty profile not restored to []') }
    if ($emptyRestored -notmatch 'comments must survive') { $emptyProblems.Add('comment header lost on revert') }
    Add-Result '7b. empty [] profile stays valid YAML' ($emptyProblems.Count -eq 0) ($emptyProblems -join '; ')

    # ------------------------------------------------------------------ 8. real state untouched
    $afterState = @{
        ThreeP   = Get-DirFingerprint $real3p
        Settings = Get-TextHash $realSettings
        Dsh      = (@($realDsh | ForEach-Object { Get-TextHash $_ }) -join '|')
    }
    $touched = @()
    foreach ($k in @('ThreeP', 'Settings', 'Dsh')) { if ($before[$k] -ne $afterState[$k]) { $touched += $k } }
    Add-Result '8. real Claude/DSH state untouched' ($touched.Count -eq 0) ($touched -join ', ')

    # ------------------------------------------------------------------ 9. wrapper dry run
    $wrapperOut = & (Join-Path $here 'code-desktop.ps1') on -DryRun 6>&1 | Out-String
    $ok = ($wrapperOut -match 'or-toggle') -and ($wrapperOut -match 'would run')
    Add-Result '9. code-desktop.ps1 dry-run' $ok ''

    # ------------------------------------------------------------------ 10. skill paths resolve
    # Two entry points: skills/claude-providers/SKILL.md (Claude Code, skills.sh, plugin loader) and
    # ./SKILL.md (NAVIG `skill:owner/repo` copies the repo root). Every path either document names
    # must exist from at least one of those roots.
    $skillDir = Split-Path -Parent $here
    # Installed copies are usually junctions/symlinks into the repo (Claude, Codex, Cursor, DSH).
    # Resolve to the real directory first, otherwise walking up from the link finds no repo root.
    $skillItem = Get-Item -LiteralPath $skillDir -Force -ErrorAction SilentlyContinue
    if ($skillItem -and $skillItem.Target) { $skillDir = @($skillItem.Target)[0] }
    # Walk up to the repo root (the dir holding .git or .claude-plugin), so the layout can move.
    $repoRoot = $skillDir
    while ($repoRoot -and -not (Test-Path -LiteralPath (Join-Path $repoRoot '.git')) -and
        -not (Test-Path -LiteralPath (Join-Path $repoRoot '.claude-plugin'))) {
        $parent = Split-Path -Parent $repoRoot
        if ($parent -eq $repoRoot -or -not $parent) { break }
        $repoRoot = $parent
    }
    $pathProblems = New-Object System.Collections.Generic.List[string]
    foreach ($doc in @((Join-Path $skillDir 'SKILL.md'), (Join-Path $repoRoot 'SKILL.md'))) {
        if (-not (Test-Path -LiteralPath $doc)) { $pathProblems.Add("missing $doc"); continue }
        $text = Get-Content -LiteralPath $doc -Raw
        if ($text -notmatch '(?m)^name:\s*claude-providers\s*$') { $pathProblems.Add("$([System.IO.Path]::GetFileName($doc)) has no name: claude-providers") }
        $refs = [regex]::Matches($text, '[A-Za-z0-9_./-]*(?:scripts|references)/[A-Za-z0-9_.-]+\.(?:ps1|psm1|md)') |
            ForEach-Object { $_.Value } | Sort-Object -Unique
        foreach ($r in $refs) {
            $resolved = (Test-Path -LiteralPath (Join-Path $skillDir $r)) -or (Test-Path -LiteralPath (Join-Path $repoRoot $r))
            if (-not $resolved) { $pathProblems.Add("$([System.IO.Path]::GetFileName($doc)) -> $r not found") }
        }
    }
    Add-Result '10. skill entry points + paths resolve' ($pathProblems.Count -eq 0) ($pathProblems -join '; ')

    # ------------------------------------------------------------------ summary
    $failed = @($results | Where-Object { -not $_.Ok })
    Write-Host ''
    Write-Host ("{0}/{1} passed" -f ($results.Count - $failed.Count), $results.Count) -ForegroundColor $(if ($failed.Count -eq 0) { 'Green' } else { 'Red' })
    Write-Host ("sandbox: {0}" -f $temp)
    if ($failed.Count -gt 0) { exit 1 }
    exit 0
}
catch {
    Write-Host ("[FAIL] unhandled: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ('sandbox: {0}' -f $temp)
    exit 1
}
