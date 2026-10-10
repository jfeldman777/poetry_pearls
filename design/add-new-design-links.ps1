param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$designDir = Join-Path $Root 'design'
$designFiles = @{}
Get-ChildItem $designDir -Filter *.html -File | ForEach-Object { $designFiles[$_.BaseName.ToLowerInvariant()] = $_.Name }

function Banner([string]$href, [string]$label) {
  "<!--new-design--><div align=""center"" style=""margin:4px 0 8px;font-family:Arial;font-size:11pt""><a href=""$href"" style=""display:inline-block;padding:6px 16px;background:#1d1d1f;color:#f3efe6;text-decoration:none;border-radius:16px""><b>$label &rarr;</b></a></div><!--/new-design-->"
}

$targets = New-Object System.Collections.ArrayList
foreach ($dir in 'Poets', 'ePoets', 'eEPoets') {
  $label = if ($dir -eq 'Poets') { 'Новый дизайн сайта' } else { 'New design' }
  Get-ChildItem (Join-Path $Root $dir) -Filter *.htm -File | ForEach-Object {
    $k = $_.BaseName.ToLowerInvariant()
    $page = if ($designFiles.ContainsKey($k)) { $designFiles[$k] } else { 'index.html' }
    [void]$targets.Add(@{ Path = $_.FullName; Href = "../design/$page"; Label = $label })
  }
}
foreach ($name in 'RusCatalog.htm', 'AgeCatalog.htm', 'calendarPoets.htm', 'Catalog_Laur.htm', 'Catalog_Pulitzer.htm', 'Catalog_Bollingen.htm', 'PortAllPoets.htm', 'EngCatalog.htm') {
  $label = if ($name -eq 'EngCatalog.htm') { 'New design' } else { 'Новый дизайн сайта' }
  [void]$targets.Add(@{ Path = (Join-Path $Root $name); Href = 'design/catalog.html'; Label = $label })
}

$done = 0; $skipped = @()
foreach ($t in $targets) {
  if (-not (Test-Path -LiteralPath $t.Path)) { $skipped += $t.Path; continue }
  $bytes = [IO.File]::ReadAllBytes($t.Path)
  $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  $enc = New-Object System.Text.UTF8Encoding $bom
  $html = [IO.File]::ReadAllText($t.Path, $enc)
  $html = [regex]::Replace($html, '(?s)<!--new-design-->.*?<!--/new-design-->\r?\n?', '')
  $m = [regex]::Match($html, '(?i)<body\b[^>]*>')
  if (-not $m.Success) { $skipped += $t.Path; continue }
  $at = $m.Index + $m.Length
  $html = $html.Substring(0, $at) + "`n" + (Banner $t.Href $t.Label) + "`n" + $html.Substring($at).TrimStart("`r", "`n")
  [IO.File]::WriteAllText($t.Path, $html, $enc)
  $done++
}
"new-design links: $done pages; skipped: $($skipped.Count) $($skipped -join ', ')"
