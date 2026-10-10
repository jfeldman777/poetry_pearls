param(
  [string]$Start = 'design/catalog.html',
  [string]$Scope = '^design/',
  [string]$Out = (Join-Path $env:TEMP 'links-report.tsv'),
  [switch]$External
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding $false

Push-Location $Root
$tracked = @{}
$trackedLower = @{}
git -c core.quotepath=off ls-files | ForEach-Object { $tracked[$_] = $true; $trackedLower[$_.ToLowerInvariant()] = $_ }
Pop-Location

function Resolve-Rel([string]$from, [string]$href) {
  $dir = if ($from -match '/') { $from.Substring(0, $from.LastIndexOf('/')) } else { '' }
  $parts = New-Object System.Collections.ArrayList
  if ($dir) { $dir -split '/' | ForEach-Object { [void]$parts.Add($_) } }
  foreach ($seg in ($href -replace '\\', '/') -split '/') {
    if ($seg -eq '' -or $seg -eq '.') { continue }
    if ($seg -eq '..') { if ($parts.Count -eq 0) { return $null }; $parts.RemoveAt($parts.Count - 1); continue }
    [void]$parts.Add($seg)
  }
  $parts -join '/'
}

$queue = New-Object System.Collections.Queue
$seen = @{}
$queue.Enqueue($Start); $seen[$Start] = $true
$broken = New-Object System.Collections.ArrayList
$externals = @{}
$pages = 0
while ($queue.Count -gt 0) {
  $page = $queue.Dequeue()
  $path = Join-Path $Root ($page -replace '/', '\')
  if (-not (Test-Path -LiteralPath $path)) { continue }
  $pages++
  $html = [IO.File]::ReadAllText($path, $utf8)
  $html = [regex]::Replace($html, '(?s)<!--.*?-->', '')
  $html = [regex]::Replace($html, '(?is)<script\b.*?</script>', '')
  $html = [regex]::Replace($html, '(?i)<link\b[^>]*\brel\s*=\s*"?(preconnect|dns-prefetch)[^>]*>', '')
  foreach ($m in [regex]::Matches($html, '(?i)<(a|img|frame|iframe|link|area)\b[^>]*?\s(href|src)\s*=\s*("([^"]*)"|''([^'']*)''|([^\s>]+))')) {
    $tag = $m.Groups[1].Value.ToLower()
    $raw = if ($m.Groups[4].Success) { $m.Groups[4].Value } elseif ($m.Groups[5].Success) { $m.Groups[5].Value } else { $m.Groups[6].Value }
    $h = [Net.WebUtility]::HtmlDecode($raw).Trim()
    if ($h -eq '' -or $h -match '^(?i)(#|mailto:|javascript:|tel:|data:)') { continue }
    if ($h -match '^(?i)https?://jfeldman777\.github\.io/poetry_pearls/(.*)$') { $h = '/' + $Matches[1] }
    if ($h -match '^(?i)(https?:)?//') {
      $u = if ($h.StartsWith('//')) { 'https:' + $h } else { $h }
      $u = ($u -split '#', 2)[0]
      if (-not $externals.ContainsKey($u)) { $externals[$u] = New-Object System.Collections.ArrayList }
      [void]$externals[$u].Add($page)
      continue
    }
    if ($h -match '^(?i)[a-z][a-z0-9+.-]*:') { [void]$broken.Add([pscustomobject]@{ Page = $page; Tag = $tag; Href = $raw; Target = ''; Why = 'scheme' }); continue }
    $p = ($h -split '[#?]', 2)[0]
    if ($p -eq '') { continue }
    try { $p = [uri]::UnescapeDataString($p) } catch { }
    $target = if ($p.StartsWith('/')) { $p.TrimStart('/') } else { Resolve-Rel $page $p }
    if (-not $target) { [void]$broken.Add([pscustomobject]@{ Page = $page; Tag = $tag; Href = $raw; Target = ''; Why = 'outside' }); continue }
    if ($target.EndsWith('/') -or -not ($target -match '\.[A-Za-z0-9]+$')) {
      $idx = ($target.TrimEnd('/') + '/index.html').TrimStart('/')
      $idx2 = ($target.TrimEnd('/') + '/index.htm').TrimStart('/')
      if ($tracked.ContainsKey($idx)) { $target = $idx } elseif ($tracked.ContainsKey($idx2)) { $target = $idx2 }
    }
    if (-not $tracked.ContainsKey($target)) {
      $why = if ($trackedLower.ContainsKey($target.ToLowerInvariant())) { "case:$($trackedLower[$target.ToLowerInvariant()])" } else { 'missing' }
      [void]$broken.Add([pscustomobject]@{ Page = $page; Tag = $tag; Href = $raw; Target = $target; Why = $why })
      continue
    }
    if ($tag -eq 'a' -or $tag -eq 'frame' -or $tag -eq 'iframe' -or $tag -eq 'area') {
      if ($target -match '\.html?$' -and $target -match $Scope -and -not $seen.ContainsKey($target)) { $seen[$target] = $true; $queue.Enqueue($target) }
    }
  }
}

if ($External) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  foreach ($u in $externals.Keys) {
    if ($u -match '^https?://web\.archive\.org/') { continue }
    $code = $null
    foreach ($method in 'Head', 'Get') {
      try {
        $r = Invoke-WebRequest -Uri $u -Method $method -UseBasicParsing -TimeoutSec 20 -MaximumRedirection 10 -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) PoetryPearlsLinkCheck/1.0'
        $code = [int]$r.StatusCode; break
      } catch {
        $resp = $_.Exception.Response
        $code = if ($resp) { [int]$resp.StatusCode } else { $_.Exception.Message -replace '\s+', ' ' }
        if ($code -is [int] -and $code -ne 405 -and $code -ne 403 -and $code -ne 501) { break }
      }
    }
    if (-not ($code -is [int] -and $code -lt 400)) {
      foreach ($pg in ($externals[$u] | Select-Object -Unique)) { [void]$broken.Add([pscustomobject]@{ Page = $pg; Tag = 'a'; Href = $u; Target = ''; Why = "http:$code" }) }
    }
  }
}

$lines = @("Page`tTag`tHref`tTarget`tWhy") + ($broken | ForEach-Object { "$($_.Page)`t$($_.Tag)`t$($_.Href)`t$($_.Target)`t$($_.Why)" })
[IO.File]::WriteAllLines($Out, $lines, $utf8)
$extList = Join-Path (Split-Path $Out) ((Split-Path $Out -Leaf) -replace '\.tsv$', '-external.txt')
[IO.File]::WriteAllLines($extList, @($externals.Keys | Sort-Object | ForEach-Object { "$_`t$(@($externals[$_] | Select-Object -Unique).Count)" }), $utf8)
"pages crawled: $pages; broken: $($broken.Count); external urls: $($externals.Count)"
