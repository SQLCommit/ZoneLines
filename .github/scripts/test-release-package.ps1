param(
    [string]$Source = (Join-Path $PSScriptRoot '../..'),
    [string]$ConfigRoot = $Source
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'addon-release-tools.ps1')
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
$cfg = Get-ReleaseConfig -Root $ConfigRoot
$originalFiles = Get-PackageFiles $cfg -Source $Source
$originalHashes = @{}
foreach ($f in $originalFiles) { $originalHashes[$f[0]] = (Get-FileHash -LiteralPath $f[0]).Hash }
foreach ($lua in Get-ChildItem -LiteralPath $Source -File -Filter '*.lua') {
    Assert-True ($cfg.files -contains $lua.Name) "Runtime module missing from release.json: $($lua.Name)"
}
$fixture = @'
<div align="center">
# ![ZoneLines](https://readme-typing-svg.demolab.com/?lines=ZoneLines)
[![Download](https://custom-icon-badges.demolab.com/badge/download?logo=data%3Abase64%2Ctest)](https://example.com/releases)
</div>
<details><summary><strong>Feature</strong> &mdash; Keep the summary.</summary>
Preserve `/zl <name>`, `<details>`, and [ordinary links](https://example.com/a_(b)).
</details>
```html
<details>Preserve this code.</details>
```
'@
$plain = ConvertTo-ReleaseReadme $fixture
foreach ($want in @('# ZoneLines', '### Feature', 'Keep the summary.', '[Download](https://example.com/releases)',
    '`/zl <name>`', '`<details>`', '[ordinary links](https://example.com/a_(b))', '<details>Preserve this code.</details>')) {
    Assert-True ($plain.Contains($want)) "README conversion lost: $want"
}
Assert-True ($plain -notmatch 'demolab|base64') 'Decorative URLs remain.'
Assert-True ((ConvertTo-ReleaseReadme $plain) -ceq $plain) 'Plain Markdown changed on a second conversion.'

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('zonelines-release-test-' + [guid]::NewGuid().ToString('N'))
$staged = Join-Path $scratch 'source'
try {
    foreach ($name in $cfg.files) {
        $dest = Join-Path $staged $name
        [IO.Directory]::CreateDirectory((Split-Path $dest -Parent)) | Out-Null
        Copy-Item -LiteralPath (Join-Path $Source $name) -Destination $dest
    }
    foreach ($name in @('DEV_TRACKING.md', 'DISCORD_POST.md', 'Screenshot.png', 'renderer.lua.bak', 'renderer.spans.json',
        '.env', 'tools/private.lua', 'tests/capture.txt', 'fonts/unlisted.ttf', 'gdifonts/debug.log')) {
        $dest = Join-Path $staged $name
        [IO.Directory]::CreateDirectory((Split-Path $dest -Parent)) | Out-Null
        [IO.File]::WriteAllText($dest, 'must not ship')
    }
    $files = Get-PackageFiles $cfg -Source $staged
    Assert-True ($files.Count -eq $cfg.files.Count) 'Unexpected package file count.'
    $readmePath = Join-Path $staged 'README.md'
    $originalReadme = [IO.File]::ReadAllText($readmePath)
    foreach ($revision in 1, 2) {
        $readme = $originalReadme
        if ($revision -eq 2) { $readme += "`nDocumentation edited before packaging.`n" }
        [IO.File]::WriteAllText($readmePath, $readme)
        $out = Join-Path $scratch 'out'
        $zipName = New-AddonPackage $cfg -Files $files -Version (Get-AddonVersion $cfg -Source $staged) -OutDir $out
        $zipPath = Join-Path $out $zipName
        $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            Assert-True ($zip.Entries.Count -eq $cfg.files.Count) 'ZIP contains unlisted files.'
            foreach ($f in $files) {
                $entry = $zip.GetEntry($f[1])
                Assert-True ($null -ne $entry) "ZIP entry missing: $($f[1])"
                $memory = New-Object IO.MemoryStream
                $stream = $entry.Open()
                try { $stream.CopyTo($memory); $actual = $memory.ToArray() } finally { $stream.Dispose(); $memory.Dispose() }
                if ((Split-Path $f[0] -Leaf) -ieq 'README.md') {
                    Assert-True ([Text.Encoding]::UTF8.GetString($actual) -ceq (ConvertTo-ReleaseReadme $readme)) 'Wrong packaged README.'
                } else {
                    Assert-True ([Convert]::ToBase64String($actual) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($f[0]))) "File changed during packaging: $($f[1])"
                }
            }
        } finally { $zip.Dispose() }
        $hash = (Get-FileHash -LiteralPath $zipPath).Hash.ToLowerInvariant()
        Assert-True ((Get-Content -LiteralPath (Join-Path $out 'SHA256SUMS.txt')).Trim() -eq "$hash  $zipName") 'Wrong ZIP checksum.'
        Assert-True ([IO.File]::ReadAllText($readmePath) -ceq $readme) 'Source README overwritten.'
    }
    foreach ($badPath in @('../README.md', '/README.md', 'C:/README.md', '*.lua', 'README.md/../LICENSE')) {
        $bad = $cfg | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $bad.files = @($badPath)
        $rejected = $false
        try { Get-PackageFiles $bad -Source $staged | Out-Null } catch { $rejected = $true }
        Assert-True $rejected "Invalid manifest path accepted: $badPath"
    }
    foreach ($required in @('gdifonts/gdifonttexture.dll', 'gdifonts/LICENSE', 'fonts/GrammaraNormal-RvLv.ttf', 'fonts/MysticGate.ttf', 'fonts/Oswald-Regular.ttf')) {
        $path = Join-Path $staged $required
        Remove-Item -LiteralPath $path
        $rejected = $false
        try { Get-PackageFiles $cfg -Source $staged | Out-Null } catch { $rejected = $true }
        Assert-True $rejected "Missing required asset did not stop packaging: $required"
        Copy-Item -LiteralPath (Join-Path $Source $required) -Destination $path
    }
    foreach ($f in $originalFiles) {
        Assert-True ((Get-FileHash -LiteralPath $f[0]).Hash -eq $originalHashes[$f[0]]) "Source file changed: $($f[0])"
    }
    Write-Host 'PASS: release file list, exclusions, required files, README conversion, ZIP bytes, and checksum.'
} finally { if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force } }
