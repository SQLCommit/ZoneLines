param(
    [Parameter(Mandatory = $true)][string]$Output,
    [string]$Root = (Join-Path $PSScriptRoot '../..')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'readme-tools.ps1')
$source = (Resolve-Path -LiteralPath (Join-Path $Root 'README.md')).Path
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
if ($source -eq $destination) { throw 'Choose an output path other than the source README.md.' }
$text = ConvertTo-ReleaseReadme ([IO.File]::ReadAllText($source))
[IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
[IO.File]::WriteAllText($destination, $text, (New-Object Text.UTF8Encoding($false)))
Write-Host "Wrote $destination"
