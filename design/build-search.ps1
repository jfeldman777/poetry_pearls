param(
  [string]$Root = (Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'
$outDir = Join-Path $Root 'design'
$utf8 = New-Object System.Text.UTF8Encoding $false

function Plural([int]$n, [string]$one, [string]$few, [string]$many) {
  $m10 = $n % 10; $m100 = $n % 100
  if ($m10 -eq 1 -and $m100 -ne 11) { return "$n $one" }
  if ($m10 -ge 2 -and $m10 -le 4 -and ($m100 -lt 12 -or $m100 -gt 14)) { return "$n $few" }
  "$n $many"
}
function Get-Text([string]$html) {
  $t = ($html -replace '\r', '') -replace '(?i)<br\s*/?>', "`n" -replace '<[^>]+>', ''
  [System.Net.WebUtility]::HtmlDecode($t).Trim()
}
function Get-Verse([string]$col) {
  $stanzas = [regex]::Matches($col, '(?s)<p class="stanza">(.*?)</p>')
  if ($stanzas.Count) { return (($stanzas | ForEach-Object { Get-Text $_.Groups[1].Value }) -join "`n`n") }
  $verse = [regex]::Match($col, '(?s)<div class="verse">(.*?)</div>')
  if ($verse.Success) { return Get-Text $verse.Groups[1].Value }
  ''
}

# --- Индекс: по каждому поэту [страница, имя, English name, стихи: [id, название, English title, перевод, оригинал]]
$poets = New-Object System.Collections.Generic.List[object]
$total = 0
foreach ($f in Get-ChildItem $outDir -Filter *.html -File | Sort-Object Name) {
  $html = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
  if ($html -notmatch '<main data-mode') { continue }
  $articles = [regex]::Matches($html, '(?s)<article class="poem" id="([^"]+)">(.*?)</article>')
  if (-not $articles.Count) { continue }
  $hero = [regex]::Match($html, '(?s)<h1>(.*?)</h1>\s*(?:<p class="alt">(.*?)</p>)?')
  $poetRu = Get-Text $hero.Groups[1].Value
  $poetEn = if ($hero.Groups[2].Success) { Get-Text $hero.Groups[2].Value } else { $poetRu }
  $items = New-Object System.Collections.Generic.List[object]
  foreach ($a in $articles) {
    $body = $a.Groups[2].Value
    $title = Get-Text ([regex]::Match($body, '(?s)<h2>(.*?)</h2>').Groups[1].Value)
    $enTitle = Get-Text ([regex]::Match($body, '(?s)<p class="en-title">(.*?)</p>').Groups[1].Value)
    $iEn = $body.IndexOf('<div class="col col-en"')
    $iRu = $body.IndexOf('<div class="col col-ru"')
    $en = ''
    $ru = ''
    if ($iEn -ge 0) { $en = Get-Verse $(if ($iRu -gt $iEn) { $body.Substring($iEn, $iRu - $iEn) } else { $body.Substring($iEn) }) }
    if ($iRu -ge 0) { $ru = Get-Verse $(if ($iEn -gt $iRu) { $body.Substring($iRu, $iEn - $iRu) } else { $body.Substring($iRu) }) }
    if (-not $ru -and -not $en) { continue }
    $items.Add(@($a.Groups[1].Value, $title, $enTitle, $ru, $en))
  }
  if (-not $items.Count) { continue }
  $total += $items.Count
  $poets.Add(@($f.Name, $poetRu, $poetEn, $items.ToArray()))
}

$json = ConvertTo-Json -InputObject $poets.ToArray() -Depth 5 -Compress
$json = $json.Replace([string][char]0x2028, '\u2028').Replace([string][char]0x2029, '\u2029')
$data = "window.PEARLS_SEARCH=$json;`n"
[IO.File]::WriteAllText((Join-Path $outDir 'search-data.js'), $data, $utf8)
$sha = [Security.Cryptography.SHA1]::Create()
$ver = (($sha.ComputeHash($utf8.GetBytes($data)) | Select-Object -First 4 | ForEach-Object { $_.ToString('x2') }) -join '')

# --- Страница поиска
$page = @"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Поиск — Жемчужины английской поэзии</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500&family=Inter:wght@400;500;600&family=Literata:opsz,wght@7..72,400;7..72,500&display=swap">
<link rel="stylesheet" href="pearls.css?v=17">
</head>
<body>

<header class="site-header">
  <div class="wrap">
    <a class="brand" href="index.html"><span class="pearl" aria-hidden="true"></span><span>Жемчужины<small>английской поэзии</small></span></a>
    <nav class="nav" aria-label="Разделы">
      <a href="index.html">Поэты</a>
      <a href="catalog.html">Каталог</a>
      <a href="search.html" aria-current="page">Поиск</a>
      <a href="articles.html">Статьи</a>
      <a href="gallery.html">Галерея</a>
      <a href="selection.html">Подборка</a>
      <a href="../e_index.htm">English</a>
    </nav>
    <div class="tools">
      <button class="chip" id="theme" type="button" title="Светлая / тёмная тема">◐</button>
    </div>
  </div>
</header>

<main class="search">
<section class="section first">
  <div class="wrap">
    <div class="section-head">
      <h2>Поиск</h2>
      <p class="search-count">$(Plural $total 'стихотворение' 'стихотворения' 'стихотворений') · $(Plural $poets.Count 'поэт' 'поэта' 'поэтов')</p>
    </div>
    <form class="search-form" role="search" action="search.html">
      <input class="search-input" type="search" name="q" placeholder="Строка, название или поэт — по-русски или по-английски" aria-label="Что искать" autocomplete="off" spellcheck="false" autofocus>
    </form>
    <p class="search-hint">Строчку можно вводить не целиком и без знаков препинания. Поиск идёт по переводам и оригиналам, названиям и именам поэтов.</p>
    <div class="search-results" aria-live="polite"></div>
  </div>
</section>
</main>

<footer class="site-footer">
  <div class="wrap">
    <span>© 1998–2026 Елена и Яков Фельдман · Жемчужины английской поэзии</span>
    <span><a href="index.html">Поэты</a> · <a href="catalog.html">Каталог</a> · <a href="articles.html">Статьи</a> · <a href="gallery.html">Галерея</a> · <a href="https://aromatic-keyboard-369.notion.site/22522db3cb0880f1a1fffd512d49ceba" target="_blank" rel="noopener">Об авторе</a></span>
  </div>
</footer>

<script src="search-data.js?v=$ver"></script>
<script src="search.js?v=1"></script>
<script src="pearls.js?v=11"></script>
</body>
</html>
"@
[IO.File]::WriteAllText((Join-Path $outDir 'search.html'), $page, $utf8)
"search: $($poets.Count) poets, $total poems, data $([math]::Round($utf8.GetByteCount($data) / 1KB)) KB"
