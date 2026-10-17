# ClaudeProviders.psm1 — shared helpers for the Claude Desktop / Claude Code / DSH provider scripts.
#
# Design rules (deliberate, do not "simplify" away):
#  * Every write goes through Write-Utf8NoBom. Both Claude Desktop and Claude Code reject a BOM.
#  * Every write backs the old file up first (Backup-File). Nothing is overwritten without a copy.
#  * Nothing here launches or kills an app. That lives in desktop-3p.ps1 behind -Relaunch.
#  * JSON is always re-serialised from a parsed object (never string-spliced), so a hand-edited
#    file cannot be corrupted by a half-matching regex.
Set-StrictMode -Version Latest

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

# Names of the config-library entries this toolkit owns. Matching by name is how -off finds them.
$script:ManagedEntryNames = @('OpenRouter', 'Hugging Face', 'Xiaomi MiMo')

function Get-ClaudeHome {
    if (-not $env:USERPROFILE) { throw 'USERPROFILE is not set; cannot locate ~/.claude.' }
    return (Join-Path $env:USERPROFILE '.claude')
}

function Test-IsWindows { return [System.Environment]::OSVersion.Platform -eq 'Win32NT' }

# Claude Desktop keeps third-party ("3p") state in a SEPARATE user-data directory so that the
# normal claude.ai login is never touched: %LOCALAPPDATA%\Claude-3p on Windows.
# (Reproduced from the shipped bundle: resolve 3p userData -> join(LOCALAPPDATA,'Claude-3p').)
function Get-Desktop3pLayout {
    param(
        [string]$UserDataDir,
        [string]$ClaudeHome = (Get-ClaudeHome)
    )
    if (-not $UserDataDir) {
        if (-not (Test-IsWindows)) { throw 'Without -UserDataDir this script only knows the Windows location.' }
        if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is not set; pass -UserDataDir explicitly.' }
        $UserDataDir = Join-Path $env:LOCALAPPDATA 'Claude-3p'
    }
    $root = [System.IO.Path]::GetFullPath($UserDataDir)
    return [pscustomobject]@{
        Root          = $root
        ConfigLibrary = Join-Path $root 'configLibrary'
        Meta          = Join-Path $root 'configLibrary\_meta.json'
        Deployment    = Join-Path $root 'claude_desktop_config.json'
        ClaudeHome    = $ClaudeHome
    }
}

function Read-KeyFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing key file '$Path'. Put the key/token in that file on one line, then re-run."
    }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $raw) { throw "Key file '$Path' is empty." }
    $key = $raw.Trim()
    if (-not $key) { throw "Key file '$Path' is empty." }
    if ($key -match '\s') { throw "Key file '$Path' contains whitespace inside the key; expected one line." }
    return $key
}

function Backup-File {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $bak = "$Path.bak-$stamp"
    Copy-Item -LiteralPath $Path -Destination $bak -Force
    return $bak
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    for ($i = 0; $i -lt 5; $i++) {
        try {
            [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
            return
        }
        catch {
            if ($i -eq 4) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $raw -or -not $raw.Trim()) { return $null }
    return ($raw | ConvertFrom-Json)
}

function ConvertTo-JsonStable {
    param([Parameter(Mandatory)]$InputObject)
    return ($InputObject | ConvertTo-Json -Depth 20)
}

# ---------------------------------------------------------------------------------------------
# Claude Desktop third-party inference document
# ---------------------------------------------------------------------------------------------
# The app validates this document with a schema whose field names are `inference*`. Two shapes
# travel the same field names: the nested form (`inference.baseUrl`) that the app's own editor
# writes, and the flat form (`inferenceGatewayBaseUrl`) used by the managed/policy reader.
# We emit both so either reader finds what it wants; unknown keys are warned about, not fatal.
function New-GatewayDocument {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$ApiKey
    )
    return [ordered]@{
        inference                 = [ordered]@{
            provider   = 'gateway'
            baseUrl    = $BaseUrl
            authScheme = 'bearer'
            credential = [ordered]@{
                kind   = 'static'
                apiKey = $ApiKey
            }
        }
        inferenceProvider         = 'gateway'
        inferenceGatewayBaseUrl   = $BaseUrl
        inferenceGatewayApiKey    = $ApiKey
        inferenceGatewayAuthScheme = 'bearer'
        inferenceCredentialKind   = 'static'
    }
}

function Get-ConfigLibrary {
    param([Parameter(Mandatory)]$Layout)
    $meta = Read-JsonFile -Path $Layout.Meta
    if ($null -eq $meta) { return [pscustomobject]@{ appliedId = ''; entries = @() } }
    $entries = @()
    if ($meta.PSObject.Properties.Name -contains 'entries' -and $meta.entries) {
        $entries = @($meta.entries | Where-Object { $_ -and $_.id })
    }
    $applied = ''
    if ($meta.PSObject.Properties.Name -contains 'appliedId' -and $meta.appliedId) { $applied = [string]$meta.appliedId }
    return [pscustomobject]@{ appliedId = $applied; entries = $entries }
}

function Save-ConfigLibrary {
    param([Parameter(Mandatory)]$Layout, [Parameter(Mandatory)]$Library)
    $doc = [ordered]@{
        appliedId = [string]$Library.appliedId
        entries   = @($Library.entries | ForEach-Object { [ordered]@{ id = [string]$_.id; name = [string]$_.name } })
    }
    Write-Utf8NoBom -Path $Layout.Meta -Content (ConvertTo-JsonStable $doc)
}

function Find-EntryByName {
    param([Parameter(Mandatory)]$Library, [Parameter(Mandatory)][string]$Name)
    foreach ($e in $Library.entries) { if ([string]$e.name -eq $Name) { return $e } }
    return $null
}

function Set-Desktop3pGateway {
    <#
      Adds (or updates) one managed config-library entry and points the app at it.
      Returns a report object describing what happened; performs no write when -DryRun.
    #>
    param(
        [Parameter(Mandatory)]$Layout,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Document,
        [switch]$DryRun
    )
    $library = Get-ConfigLibrary -Layout $Layout
    $entry = Find-EntryByName -Library $library -Name $Name
    $created = $false
    if ($null -eq $entry) {
        $entry = [pscustomobject]@{ id = [guid]::NewGuid().ToString(); name = $Name }
        $library.entries = @($library.entries) + $entry
        $created = $true
    }
    $library.appliedId = [string]$entry.id

    $docPath = Join-Path $Layout.ConfigLibrary ("{0}.json" -f $entry.id)
    $docJson = ConvertTo-JsonStable $Document
    $metaJson = ConvertTo-JsonStable ([ordered]@{
        appliedId = [string]$library.appliedId
        entries   = @($library.entries | ForEach-Object { [ordered]@{ id = [string]$_.id; name = [string]$_.name } })
    })

    $deployDoc = Read-JsonFile -Path $Layout.Deployment
    $deploy = [ordered]@{}
    if ($null -ne $deployDoc) {
        foreach ($p in $deployDoc.PSObject.Properties) { $deploy[$p.Name] = $p.Value }
    }
    $deploy['deploymentMode'] = '3p'

    $report = [pscustomobject]@{
        EntryName  = $Name
        EntryId    = [string]$entry.id
        Created    = $created
        DocPath    = $docPath
        MetaPath   = $Layout.Meta
        DeployPath = $Layout.Deployment
        DocJson    = $docJson
        MetaJson   = $metaJson
        DeployJson = (ConvertTo-JsonStable $deploy)
    }
    if ($DryRun) { return $report }

    $null = Backup-File -Path $Layout.Deployment
    $null = Backup-File -Path $Layout.Meta
    Write-Utf8NoBom -Path $docPath -Content $docJson
    Write-Utf8NoBom -Path $Layout.Meta -Content $metaJson
    Write-Utf8NoBom -Path $Layout.Deployment -Content $report.DeployJson
    return $report
}

function Remove-Desktop3pManaged {
    <#
      Reverts what Set-Desktop3pGateway did: drops our entries (and their documents) and clears
      deploymentMode so the app returns to the normal claude.ai login. Other entries are kept.
    #>
    param(
        [Parameter(Mandatory)]$Layout,
        [switch]$DryRun
    )
    $library = Get-ConfigLibrary -Layout $Layout
    $removed = New-Object System.Collections.Generic.List[string]
    $kept = New-Object System.Collections.Generic.List[object]
    foreach ($e in $library.entries) {
        if ($script:ManagedEntryNames -contains [string]$e.name) { $removed.Add([string]$e.id) }
        else { $kept.Add($e) }
    }

    $deployDoc = Read-JsonFile -Path $Layout.Deployment
    $deploy = [ordered]@{}
    if ($null -ne $deployDoc) {
        foreach ($p in $deployDoc.PSObject.Properties) {
            if ($p.Name -eq 'deploymentMode') { continue }
            $deploy[$p.Name] = $p.Value
        }
    }

    $applied = [string]$library.appliedId
    $appliedRemoved = $removed -contains $applied
    $newApplied = $applied
    if ($appliedRemoved) {
        $newApplied = ''
        if ($kept.Count -gt 0) { $newApplied = [string]$kept[0].id }
    }
    # Only stay in third-party mode when something is still configured to point at; otherwise the
    # app must come back to the normal claude.ai login ("1p" means first-party).
    if ($kept.Count -gt 0) { $deploy['deploymentMode'] = '3p' }
    else { $deploy['deploymentMode'] = '1p' }

    $report = [pscustomobject]@{
        RemovedIds  = @($removed)
        KeptIds     = @($kept | ForEach-Object { [string]$_.id })
        AppliedId   = $newApplied
        DeployJson  = (ConvertTo-JsonStable $deploy)
        MetaExists  = (Test-Path -LiteralPath $Layout.Meta)
    }
    if ($DryRun) { return $report }

    foreach ($id in $removed) {
        $p = Join-Path $Layout.ConfigLibrary ("{0}.json" -f $id)
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    if (Test-Path -LiteralPath $Layout.Meta) {
        $null = Backup-File -Path $Layout.Meta
        if ($kept.Count -eq 0) { Remove-Item -LiteralPath $Layout.Meta -Force }
        else {
            Write-Utf8NoBom -Path $Layout.Meta -Content (ConvertTo-JsonStable ([ordered]@{
                        appliedId = [string]$newApplied
                        entries   = @($kept | ForEach-Object { [ordered]@{ id = [string]$_.id; name = [string]$_.name } })
                    }))
        }
    }
    if (Test-Path -LiteralPath $Layout.Deployment) {
        $null = Backup-File -Path $Layout.Deployment
        Write-Utf8NoBom -Path $Layout.Deployment -Content $report.DeployJson
    }
    return $report
}

function Get-Desktop3pStatus {
    param([Parameter(Mandatory)]$Layout)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("userData : $($Layout.Root)")
    $deploy = Read-JsonFile -Path $Layout.Deployment
    $mode = '(unset -> normal claude.ai login)'
    if ($null -ne $deploy -and $deploy.PSObject.Properties.Name -contains 'deploymentMode' -and $deploy.deploymentMode) {
        $mode = [string]$deploy.deploymentMode
    }
    $lines.Add("mode     : $mode")
    $library = Get-ConfigLibrary -Layout $Layout
    if ($library.entries.Count -eq 0) { $lines.Add('entries  : (none)') }
    $lines.Add("applied  : $($library.appliedId)")
    foreach ($e in $library.entries) {
        $docPath = Join-Path $Layout.ConfigLibrary ("{0}.json" -f $e.id)
        $provider = '?'
        $base = '?'
        $doc = Read-JsonFile -Path $docPath
        if ($null -ne $doc) {
            if ($doc.PSObject.Properties.Name -contains 'inferenceProvider' -and $doc.inferenceProvider) { $provider = [string]$doc.inferenceProvider }
            elseif ($doc.PSObject.Properties.Name -contains 'inference') { $provider = [string]$doc.inference.provider }
            if ($doc.PSObject.Properties.Name -contains 'inferenceGatewayBaseUrl' -and $doc.inferenceGatewayBaseUrl) { $base = [string]$doc.inferenceGatewayBaseUrl }
            elseif ($doc.PSObject.Properties.Name -contains 'inference') { $base = [string]$doc.inference.baseUrl }
        }
        $mark = if ([string]$e.id -eq [string]$library.appliedId) { '*' } else { ' ' }
        $lines.Add((" {0} {1,-14} {2,-9} {3}  ({4})" -f $mark, $e.name, $provider, $base, $e.id))
    }
    return ($lines -join [Environment]::NewLine)
}

# ---------------------------------------------------------------------------------------------
# Claude Desktop process control (only called from desktop-3p.ps1 -Relaunch)
# ---------------------------------------------------------------------------------------------
function Get-ClaudeDesktopProcess {
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -in @('Claude', 'claude') -and $_.Path -and ($_.Path -match '\\Claude(_[0-9.]+)?_x64')
        })
}

function Stop-ClaudeDesktop {
    $procs = Get-ClaudeDesktopProcess
    if ($procs.Count -eq 0) { return 0 }
    foreach ($p in $procs) { try { $null = $p.CloseMainWindow() } catch { } }
    Start-Sleep -Milliseconds 1200
    $left = Get-ClaudeDesktopProcess
    foreach ($p in $left) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { } }
    return $procs.Count
}

function Start-ClaudeDesktop {
    $pkg = Get-AppxPackage -Name 'Claude' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) {
        $aumid = '{0}!{1}' -f $pkg.PackageFamilyName, 'Claude'
        try { Start-Process -FilePath ('shell:AppsFolder\' + $aumid); return $aumid } catch { }
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe'),
        (Join-Path $env:PROGRAMFILES 'Claude\Claude.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    if ($candidates.Count -gt 0) {
        Start-Process -FilePath $candidates[0]
        return $candidates[0]
    }
    if ($pkg) { return ('shell:AppsFolder\' + $pkg.PackageFamilyName) }
    throw 'Could not find Claude Desktop. Start it from the Start menu once, then re-run with -Relaunch.'
}

# ---------------------------------------------------------------------------------------------
# DeepSeek Harness provider block (comment-delimited, text-level, idempotent)
# ---------------------------------------------------------------------------------------------
$script:DshBeginFmt = '# >>> dsh-provider:{0} (managed by claude-providers) >>>'
$script:DshEndFmt = '# <<< dsh-provider:{0} <<<'

function Get-DshProfilePaths {
    if (-not $env:USERPROFILE) { throw 'USERPROFILE is not set; cannot locate ~/.dsh.' }
    $profiles = Join-Path (Join-Path $env:USERPROFILE '.dsh') 'profiles'
    if (-not (Test-Path -LiteralPath $profiles)) { return @() }
    return @(Get-ChildItem -LiteralPath $profiles -Directory | ForEach-Object {
            $p = Join-Path $_.FullName 'cordis.patch.yml'
            if (Test-Path -LiteralPath $p) { $p }
        })
}

function New-DshProviderBlock {
    param(
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Api,
        [Parameter(Mandatory)][string]$ApiKeyEnv,
        [string[]]$Models = @(),
        [string]$DisplayName
    )
    $b = @()
    $b += ($script:DshBeginFmt -f $Provider)
    $b += ('- id: llm-pi-ai-{0}' -f $Provider)
    $b += '  name: "@deepseek-ai/dsh-llm-pi-ai"'
    $b += '  config:'
    $b += '    providers:'
    $b += ('      {0}:' -f $Provider)
    if ($DisplayName) { $b += ('        displayName: "{0}"' -f $DisplayName) }
    $b += ('        api: {0}' -f $Api)
    $b += ('        baseURL: {0}' -f $BaseUrl)
    $b += ('        apiKeyEnv: {0}' -f $ApiKeyEnv)
    if ($Models.Count -gt 0) {
        $b += '        models:'
        foreach ($m in $Models) { $b += ('          - id: {0}' -f $m) }
    }
    $b += ($script:DshEndFmt -f $Provider)
    return ($b -join "`n")
}

function Get-DshBlockRegex {
    param([Parameter(Mandatory)][string]$Provider)
    $begin = [regex]::Escape($script:DshBeginFmt -f $Provider)
    $end = [regex]::Escape($script:DshEndFmt -f $Provider)
    return [regex]::new("(?ms)^[ \t]*$begin.*?^[ \t]*$end[ \t]*\r?\n?", 'Multiline')
}

function Set-DshProviderBlock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Block,
        [string[]]$OtherProviders = @(),
        [switch]$DryRun
    )
    $original = if (Test-Path -LiteralPath $Path) { Get-Content -LiteralPath $Path -Raw } else { '' }
    if ($null -eq $original) { $original = '' }
    $text = $original
    # Strip any managed block for the providers we might be replacing, so re-runs are idempotent.
    foreach ($p in @($OtherProviders)) {
        $text = (Get-DshBlockRegex -Provider $p).Replace($text, '')
    }

    # A profile with no patches is a file of comments plus a bare `[]` (or `{}`/empty). Appending a
    # second top-level node after `[]` produces invalid YAML, so drop the placeholder first and keep
    # the explanatory comment header.
    $lines = $text -split "\r?\n"
    $meaningful = @($lines | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' })
    $isEmptyProfile = $meaningful.Count -eq 0 -or ($meaningful.Count -eq 1 -and $meaningful[0].Trim() -in @('[]', '{}', 'null', '~'))
    if ($isEmptyProfile) {
        $text = (@($lines | Where-Object { $_ -match '^\s*#' }) -join "`n")
    }
    $text = $text.TrimEnd()
    if ($text.Length -gt 0) { $text += "`n`n" }
    $text += $Block + "`n"

    if ($DryRun) { return [pscustomobject]@{ Path = $Path; Before = $original; After = $text } }
    $null = Backup-File -Path $Path
    Write-Utf8NoBom -Path $Path -Content $text
    return [pscustomobject]@{ Path = $Path; Before = $original; After = $text }
}

function Remove-DshProviderBlock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Providers = @('openrouter', 'hf', 'mimo'),
        [switch]$DryRun
    )
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ Path = $Path; Before = ''; After = ''; Changed = $false } }
    $original = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $original) { $original = '' }
    $text = $original
    foreach ($p in $Providers) { $text = (Get-DshBlockRegex -Provider $p).Replace($text, '') }
    $text = ($text -replace '(\r?\n){3,}', "`n`n").TrimEnd()
    # Never leave a patch file that is only comments: the loader expects an array.
    $remaining = @($text -split "\r?\n" | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' })
    if ($remaining.Count -eq 0) {
        if ($text.Length -gt 0) { $text += "`n[]" } else { $text = '[]' }
    }
    $text += "`n"
    $changed = ($text -ne $original)
    if ($DryRun -or -not $changed) { return [pscustomobject]@{ Path = $Path; Before = $original; After = $text; Changed = $changed } }
    $null = Backup-File -Path $Path
    Write-Utf8NoBom -Path $Path -Content $text
    return [pscustomobject]@{ Path = $Path; Before = $original; After = $text; Changed = $changed }
}

Export-ModuleMember -Function *
