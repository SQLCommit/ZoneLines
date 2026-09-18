# Shared by the addon release workflows (.github/workflows). The addon-specific part is .github/release.json.
# Every addon repository has an identical copy: change them all together. Works in Windows PowerShell 5.1 and 7.
Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'

function Get-ReleaseConfig {
    param([string]$Root = '.')
    $cfg = Get-Content -Raw (Join-Path $Root '.github/release.json') | ConvertFrom-Json
    foreach ($key in 'name', 'repository', 'addonFolder', 'versionFile', 'versionPattern') {
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

# The files that ship, as @(full path, path inside the zip) pairs. Everything in the source except files and folders
# whose name starts with '.' (.git, .github, .gitignore ...) and anything named in release.json's "exclude" list
# (a folder or file name such as "tests", or a pattern such as "*.bak"; matched against every part of the path).
function Get-PackageFiles {
    param($Cfg, [string]$Source)
    $root = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\', '/')
    $exclude = if ($Cfg.PSObject.Properties.Name -contains 'exclude') { @($Cfg.exclude) } else { @() }
    $files = New-Object System.Collections.Generic.List[object]
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
        $rel = $file.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
        $parts = $rel -split '/'
        if ($parts | Where-Object { $_.StartsWith('.') }) { continue }
        $skip = $false
        foreach ($pattern in $exclude) { if ($parts | Where-Object { $_ -like $pattern }) { $skip = $true; break } }
        if ($skip) { continue }
        $files.Add(@($file.FullName, "addons/$($Cfg.addonFolder)/$rel"))
    }
    if (-not ($files | Where-Object { $_[1] -eq "addons/$($Cfg.addonFolder)/$($Cfg.addonFolder).lua" })) {
        throw "$($Cfg.addonFolder).lua is not in the package: Ashita loads an addon from addons\$($Cfg.addonFolder)\$($Cfg.addonFolder).lua."
    }
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
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath }
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $Files) {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f[0], $f[1], [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $zip.Dispose() }
    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath (Join-Path $outPath 'SHA256SUMS.txt') -Value "$hash  $zipName" -Encoding Ascii
    return $zipName
}

# The Downloads section added to a release's notes. Everything from the marker line down is generated and replaced
# when the files are prepared again; the owner's notes go above it.
$script:NotesMarker = '<!-- release files: generated below this line -->'
function Get-DownloadNotes {
    param($Cfg, [string]$ZipName, [string]$OutDir)
    $sums = Get-Content -LiteralPath (Join-Path $OutDir 'SHA256SUMS.txt')
    $lines = @(
        $script:NotesMarker,
        '### Downloads',
        '',
        "**$ZipName** - extract it into your Ashita folder: it adds ``addons\$($Cfg.addonFolder)\``. Then load it with ``/addon load $($Cfg.addonFolder)``.",
        '',
        "Packed by GitHub Actions from this release's source. Check the download:",
        '```',
        "gh attestation verify $ZipName --repo $($Cfg.repository)"
    )
    $lines += @('```', '', 'SHA-256:', '```') + $sums + @('```')
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
