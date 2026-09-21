Set-StrictMode -Version 3

function ConvertTo-ReleaseReadme {
    param([Parameter(Mandatory = $true)][string]$Markdown)

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $fence = ''
    foreach ($line in ($Markdown -split '\r?\n')) {
        if ($fence) {
            $lines.Add($line)
            if ($line -match ('^ {0,3}' + [regex]::Escape($fence[0]) + '{' + $fence.Length + ',}\s*$')) { $fence = '' }
            continue
        }
        if ($line -match '^ {0,3}(`{3,}|~{3,})') {
            $fence = $Matches[1]
            $lines.Add($line)
            continue
        }

        # Leave code examples and command placeholders intact.
        if ($line -match '^(    |\t)') { $lines.Add($line); continue }
        $code = New-Object 'System.Collections.Generic.List[string]'
        $text = [regex]::Replace($line, '(`+)(.+?)\1(?!`)', {
            param($m)
            $key = "@@README_CODE_$($code.Count)@@"
            $code.Add($m.Value)
            return $key
        })

        # Decorative images become text; badge links keep their destinations.
        $text = $text -replace '^(#{1,6})\s+!\[([^\]]+)\]\(https://readme-typing-svg\.demolab\.com/[^\s]*\)\s*$', '$1 $2'
        $text = $text -replace '!\[([^\]]+)\]\(https://(?:custom-icon-badges\.demolab\.com|img\.shields\.io)/[^\s]*?\)', '$1'
        $text = $text -replace '</?(?:div|p|details|dl|dd)(?:\s+[^<>]*)?>', ''
        if ($text -match '^\s*<summary><strong>(.*?)</strong>\s*(?:\u2014|&mdash;|-)\s*(.*?)</summary>\s*$') {
            $text = "### $($Matches[1])`n`n$($Matches[2])"
        } else {
            $text = $text -replace '<summary>\s*', "`n### " -replace '</summary>', "`n"
        }
        $text = $text -replace '</?(?:strong|b)>', '**' -replace '</?(?:em|i)>', '*'
        $text = $text -replace '<br\s*/?>', "`n" -replace '<hr\s*/?>', "`n---`n"
        if ($text -match '</?[A-Za-z][A-Za-z0-9]*(?:\s+[^<>]*|/?)>' -or
            $text -match 'https://(?:readme-typing-svg|custom-icon-badges)\.demolab\.com/') {
            throw "Unsupported README formatting: $line"
        }
        $text = [Net.WebUtility]::HtmlDecode($text)
        for ($i = 0; $i -lt $code.Count; $i++) { $text = $text.Replace("@@README_CODE_${i}@@", $code[$i]) }
        foreach ($part in ($text -split "`n")) {
            if (-not $part.Trim() -and ($lines.Count -eq 0 -or $lines[$lines.Count - 1] -eq '')) { continue }
            if ($part.Trim()) { $lines.Add($part) } else { $lines.Add('') }
        }
    }
    return (($lines -join "`n").Trim() + "`n")
}
