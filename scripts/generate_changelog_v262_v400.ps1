$outFile = 'DOCS/CHANGELOG_V262_TO_V400.md'
$pattern = '^v(26[2-9]|2[7-9][0-9]|3[0-9][0-9]|400)\b'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$raw = git -c i18n.logOutputEncoding=UTF-8 log --all --date=short --pretty=format:"%h|%ad|%s" --perl-regexp --grep $pattern --no-color

$items = @()
foreach ($line in $raw) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }

  $parts = $line -split '\|', 3
  if ($parts.Count -lt 3) { continue }

  $hash = $parts[0].Trim()
  $date = $parts[1].Trim()
  $subject = $parts[2].Trim()

  if ($subject -match '^v(26[2-9]|2[7-9][0-9]|3[0-9][0-9]|400)\b\s*[:\-]?\s*(.*)$') {
    $version = [int]$matches[1]
    $summary = $matches[2].Trim()
    if ([string]::IsNullOrWhiteSpace($summary)) { $summary = '(no summary text)' }
    $summary = $summary -replace '\|', '/'

    $items += [pscustomobject]@{
      Version = $version
      Date = $date
      Commit = $hash
      Summary = $summary
      Subject = $subject
    }
  }
}

$items = $items | Sort-Object Version, Date, Commit

$lines = @()
$lines += '# Changelog v262 den v400'
$lines += ''
$lines += 'Generated: 2026-04-19'
$lines += 'Source: git log --all (version-tagged commits only)'
$lines += 'Filter: versions v262..v400'
$lines += ''
$lines += "Tong so dong release tim thay: $($items.Count)"
$lines += ''
$lines += '| Version | Date | Commit | Noi dung |'
$lines += '| --- | --- | --- | --- |'

foreach ($it in $items) {
  $lines += "| v$($it.Version) | $($it.Date) | $($it.Commit) | $($it.Summary) |"
}

Set-Content -Path $outFile -Value $lines -Encoding UTF8
Write-Output "WROTE: $outFile"
Write-Output "COUNT: $($items.Count)"
