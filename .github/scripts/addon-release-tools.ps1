# ZoneLines release packaging. File selection is defined in .github/release.json.
# Works in Windows PowerShell 5.1 and 7.
Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'readme-tools.ps1')

function Get-ReleaseConfig {
    param([string]$Root = '.')
    $cfg = Get-Content -Raw (Join-Path $Root '.github/release.json') | ConvertFrom-Json
    foreach ($key in 'name', 'repository', 'addonFolder', 'versionFile', 'versionPattern', 'files') {
        if ($cfg.PSObject.Properties.Name -notcontains $key) { throw ".github/release.json has no '$key'." }
    }
    return $cfg
}

# The version the addon reports (addon.version, for example "1.3.1"), read from the source at $Source.
function Get-AddonVersion {
    param($Cfg, [string]$Source = '.')
    $file = Join-Path $Source $Cfg.versionFile
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "$($Cfg.versionFile) (versionFile in .github/release.json) is not in the source." }
    $m = [regex]::Match((Get-Content -Raw -LiteralPath $file), $Cfg.versionPattern)
    if (-not $m.Success) { throw "No version found in $($Cfg.versionFile) (pattern $($Cfg.versionPattern))." }
    return $m.Groups[1].Value
}

# Adds a line to the run's summary page (and the log).
function Write-Summary {
    param([string]$Text)
    Write-Host $Text
    if ($env:GITHUB_STEP_SUMMARY) { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $Text }
}

# Runs gh with up to three tries (GitHub's API times out now and then) and returns its output as one string. With
# -AllowNotFound a "not found" answer returns $null; any other failure after three tries stops the run.
$script:GhRetryDelay = 5
function Invoke-Gh {
    param([string[]]$Arguments, [switch]$AllowNotFound)
    $message = ''
    for ($try = 1; $try -le 3; $try++) {
        $saved = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $out = @(& gh @Arguments 2>&1)
        $code = $LASTEXITCODE
        $ErrorActionPreference = $saved
        $message = ($out | ForEach-Object { "$_" }) -join "`n"
        if ($code -eq 0) { $global:LASTEXITCODE = 0; return $message }
        if ($AllowNotFound -and $message -match '(HTTP 404|release not found|Not Found)') { $global:LASTEXITCODE = 0; return $null }
        if ($try -lt 3) { Start-Sleep -Seconds ($script:GhRetryDelay * $try) }
    }
    throw "gh $(($Arguments | Select-Object -First 2) -join ' ') failed: $message"
}

# Require every listed file; unrelated source-folder contents never enter the ZIP.
function Get-PackageFiles {
    param($Cfg, [string]$Source)
    $root = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\', '/')
    $files = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($entry in $Cfg.files) {
        $rel = "$entry".Replace('\', '/')
        if (-not $rel -or $rel -match '(^/|:|[?*]|(^|/)\.[^/]*(/|$)|//)') {
            throw "Invalid release file path: $entry"
        }
        if ($seen.ContainsKey($rel)) { throw "Duplicate release file: $rel" }
        $seen[$rel] = $true
        $path = Join-Path $root $rel
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required release file missing: $rel" }
        $partPath = $root
        foreach ($part in ($rel -split '/')) {
            $partPath = Join-Path $partPath $part
            if ((Get-Item -LiteralPath $partPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Release files cannot use symbolic links or junctions: $rel"
            }
        }
        $files.Add(@($path, "addons/$($Cfg.addonFolder)/$rel"))
    }
    if (-not $seen.ContainsKey("$($Cfg.addonFolder).lua")) { throw 'The addon entry point is missing from the release file list.' }
    return , $files
}

# In $OutDir: <Name>-v<Version>.zip, holding addons/<folder>/... so it extracts straight into the Ashita folder, and
# SHA256SUMS.txt. Returns the zip's file name.
function New-AddonPackage {
    param($Cfg, $Files, [string]$Version, [string]$OutDir)
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $outPath = (Resolve-Path -LiteralPath $OutDir).Path
    $zipName = "$($Cfg.name)-v$Version.zip"
    $zipPath = Join-Path $outPath $zipName
    $readmes = @{}
    foreach ($f in $Files) {
        if ((Split-Path $f[0] -Leaf) -ieq 'README.md') {
            $readmes[$f[0]] = ConvertTo-ReleaseReadme ([IO.File]::ReadAllText($f[0]))
        }
    }
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath }
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $Files) {
            if ($readmes.ContainsKey($f[0])) {
                $entry = $zip.CreateEntry($f[1], [IO.Compression.CompressionLevel]::Optimal)
                $writer = New-Object IO.StreamWriter($entry.Open(), (New-Object Text.UTF8Encoding($false)))
                try { $writer.Write($readmes[$f[0]]) } finally { $writer.Dispose() }
            } else {
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f[0], $f[1], [IO.Compression.CompressionLevel]::Optimal)
            }
        }
    } finally { $zip.Dispose() }
    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath (Join-Path $outPath 'SHA256SUMS.txt') -Value "$hash  $zipName" -Encoding Ascii
    return $zipName
}

# A link to this version's section of the changelog as it is at $Tag: the first heading below the title that names
# the version, in CHANGELOG.md, else in README.md (a Version History section). $null when neither has one. The anchor
# follows GitHub's heading ids (lower case, punctuation dropped, spaces to hyphens, -1/-2 for repeats).
function Get-HeadingSlug {
    param([string]$Text)
    $t = $Text -replace '\[([^\]]*)\]\([^)]*\)', '$1'
    $t = ($t -replace '[`*]', '').ToLowerInvariant()
    $t = [regex]::Replace($t, '[^\p{L}\p{M}\p{N}\p{Pc} -]', '')
    return $t.Replace(' ', '-')
}
function Get-ChangelogLink {
    param($Cfg, [string]$Version, [string]$Tag, [string]$Root = '.')
    $pattern = '(?<![\w.])v?' + [regex]::Escape($Version) + '(?![\w.])'
    foreach ($file in 'CHANGELOG.md', 'README.md') {
        $path = Join-Path $Root $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $seen = @{}
        $fence = $false
        foreach ($line in Get-Content -LiteralPath $path) {
            if ($line -match '^\s*(```|~~~)') { $fence = -not $fence; continue }
            if ($fence -or $line -notmatch '^(#{1,6})\s+(.+?)\s*#*\s*$') { continue }
            $level = $Matches[1].Length
            $text = $Matches[2]
            $slug = Get-HeadingSlug $text
            $n = if ($seen.ContainsKey($slug)) { $seen[$slug] } else { 0 }
            $seen[$slug] = $n + 1
            if ($level -ge 2 -and $text -match $pattern) {
                $anchor = if ($n -gt 0) { "$slug-$n" } else { $slug }
                return "https://github.com/$($Cfg.repository)/blob/$Tag/$file#$anchor"
            }
        }
    }
    return $null
}

# The download footer added to a release's notes: a What's new link to the changelog (when it has a section for
# this version), a rule, then a Note box with the Download line and the
# verification details folded away. Everything from the marker line down is generated and replaced when the files are prepared again; the
# owner's notes go above it.
$script:NotesMarker = '<!-- release files: generated below this line -->'
function Get-DownloadNotes {
    param($Cfg, [string]$ZipName, [string]$OutDir, [string]$Changelog = '')
    $hash = ((Get-Content -LiteralPath (Join-Path $OutDir 'SHA256SUMS.txt') | Select-Object -First 1) -split '\s+')[0]
    $lines = @($script:NotesMarker, '')
    if ($Changelog) { $lines += @("**What's new:** see the [changelog]($Changelog).", '') }
    $lines += @(
        '---',
        '',
        '> [!NOTE]',
        "> **Download:** ``$ZipName`` - extract it into your Ashita folder (adds ``addons\$($Cfg.addonFolder)\``), then ``/addon load $($Cfg.addonFolder)``.",
        '>',
        '> <details><summary>Verify this download</summary>',
        '>',
        "> - SHA-256: ``$hash``",
        "> - Attestation: ``gh attestation verify $ZipName --repo $($Cfg.repository)``",
        '>',
        '> </details>'
    )
    return ($lines -join "`n")
}
function Join-ReleaseNotes {
    param([string]$Body, [string]$Downloads)
    if ($null -eq $Body) { $Body = '' }
    $at = $Body.IndexOf($script:NotesMarker)
    if ($at -ge 0) { $Body = $Body.Substring(0, $at) }
    $Body = $Body.TrimEnd()
    if ($Body) { return "$Body`n`n$Downloads`n" }
    return "$Downloads`n"
}
