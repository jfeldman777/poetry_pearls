param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$outDir = $PSScriptRoot

function Esc([string]$s) { $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function Plain([string]$s) { ([Net.WebUtility]::HtmlDecode([regex]::Replace($s, '(?s)<[^>]+>', ' ')) -replace '[\s\u00A0]+', ' ').Trim() }
function Plural([int]$n, [string]$one, [string]$few, [string]$many) {
  $m10 = $n % 10; $m100 = $n % 100
  if ($m10 -eq 1 -and $m100 -ne 11) { return $one }
  if ($m10 -ge 2 -and $m10 -le 4 -and ($m100 -lt 12 -or $m100 -gt 14)) { return $few }
  $many
}
function Roman([int]$n) {
  $map = @(@(10, 'X'), @(9, 'IX'), @(5, 'V'), @(4, 'IV'), @(1, 'I'))
  $r = ''
  foreach ($p in $map) { while ($n -ge $p[0]) { $r += $p[1]; $n -= $p[0] } }
  $r
}
function Read-Page([string]$name) { [IO.File]::ReadAllText((Join-Path $Root $name), [Text.Encoding]::UTF8) }
function Get-Lines([string]$html) {
  $s = [regex]::Replace($html, '(?is)<(script|style|select)\b.*?</\1>', '') -replace '\r?\n', ' '
  $s = [regex]::Replace($s, '(?i)<br\b[^>]*>|</p>|</li>|</tr>|<hr\b[^>]*>', "`n")
  @($s -split "`n" | Where-Object { (Plain $_) -ne '' })
}
function Get-Bases([string]$html) {
  @([regex]::Matches($html, '(?i)href\s*=\s*"?\s*(?:\.\./)?(?<![A-Za-z])e?Poets/([^"#/\s>]+?)\.htm') | ForEach-Object { $_.Groups[1].Value.ToLower() } | Select-Object -Unique)
}
function Norm-Q([string]$s) { ($s.ToLower() -replace 'ё', 'е') }

$poets = @(Get-Content (Join-Path $outDir 'poets.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
$byBase = @{}
foreach ($p in $poets) { $byBase[$p.Base.ToLower()] = $p }
$small = @{}
Get-ChildItem (Join-Path $Root 'PortSmall') -File | ForEach-Object { $small[$_.BaseName.ToLower()] = $_.Name }
$nonPersons = @('balladesc', 'nurs_rhymes')
$totalPoems = ($poets | Measure-Object Count -Sum).Sum

function Get-RuKey($p) {
  $n = if ($p.Ru) { $p.Ru } else { $p.Base }
  if ($nonPersons -contains $p.Base.ToLower()) { return $n }
  $tokens = @((($n -split ',')[0] -split '[\s.]+') | Where-Object { $_ })
  $k = $tokens.Count - 1
  while ($k -gt 0 -and $tokens[$k] -cmatch '^[IVX]+$') { $k-- }
  "$($tokens[$k]) $n"
}
function Get-Letter([string]$key) {
  $c = $key.Substring(0, 1).ToUpper()
  if ($c -eq 'Ё') { 'Е' } else { $c }
}

function Render-Poet($p, [string]$name, [string]$alt) {
  $b = $p.Base.ToLower()
  $ph = if ($small.ContainsKey($b)) { "<img class=""ph"" src=""../PortSmall/$($small[$b])"" alt="""" loading=""lazy"">" } else { "<span class=""ph"">$(Esc ($name.Substring(0, 1)))</span>" }
  $cnt = "$($p.Count) $(Plural $p.Count 'стих.' 'стих.' 'стих.')"
  $yrs = if ($p.Years) { "$(Esc $p.Years)<small>$cnt</small>" } else { "<small>$cnt</small>" }
  $q = Esc (Norm-Q "$($p.Ru) $($p.En) $($p.Base)")
  "<li data-q=""$q""><a href=""$($p.Base).html"">$ph<span class=""nm""><b>$(Esc $name)</b><i>$(Esc $alt)</i></span><span class=""yrs"">$yrs</span></a></li>"
}

# --- А–Я
$ruView = New-Object System.Text.StringBuilder
$groups = $poets | Sort-Object { Get-RuKey $_ } | Group-Object { Get-Letter (Get-RuKey $_) }
[void]$ruView.AppendLine('<nav class="letters" aria-label="Буквы">' + (($groups | ForEach-Object { "<a href=""#ru-$($_.Name)"">$($_.Name)</a>" }) -join '') + '</nav>')
foreach ($g in $groups) {
  [void]$ruView.AppendLine("<div class=""cat-group"" id=""ru-$($g.Name)""><h3>$($g.Name)</h3><ul class=""cat-list"">")
  foreach ($p in $g.Group) { [void]$ruView.AppendLine((Render-Poet $p $(if ($p.Ru) { $p.Ru } else { $p.Base }) $p.En)) }
  [void]$ruView.AppendLine('</ul></div>')
}

# --- A–Z
$engHtml = Read-Page 'EngCatalog.htm'
$enOrder = @{}; $enName = @{}
$i = 0
foreach ($line in Get-Lines $engHtml) {
  $bs = Get-Bases $line
  if ($bs.Count -eq 0) { continue }
  $b = $bs[0]
  if ($enOrder.ContainsKey($b) -or -not $byBase.ContainsKey($b)) { continue }
  $enOrder[$b] = $i++
  $t = Plain $line
  $m = [regex]::Match($t, '^\s*([A-Za-z][^,(]*?)\s*,\s*([^(]*?)\s*\(')
  if ($m.Success -and $m.Groups[2].Value -notmatch '\p{IsCyrillic}') { $enName[$b] = "$($m.Groups[1].Value.Trim()), $($m.Groups[2].Value.Trim())".TrimEnd(',', ' ') }
}
$enSorted = $poets | Sort-Object @{ Expression = { $b = $_.Base.ToLower(); if ($enOrder.ContainsKey($b)) { $enOrder[$b] } else { 100000 } } }, @{ Expression = { $t = @(($_.En + '') -split '\s+'); $t[-1] } }
$enView = New-Object System.Text.StringBuilder
$enGroups = $enSorted | Group-Object { $b = $_.Base.ToLower(); $n = if ($enName.ContainsKey($b)) { $enName[$b] } elseif ($_.En) { $_.En } else { $_.Base }; $n.Substring(0, 1).ToUpper() }
[void]$enView.AppendLine('<nav class="letters" aria-label="Letters">' + (($enGroups | ForEach-Object { "<a href=""#en-$($_.Name)"">$($_.Name)</a>" }) -join '') + '</nav>')
foreach ($g in $enGroups) {
  [void]$enView.AppendLine("<div class=""cat-group"" id=""en-$($g.Name)""><h3>$($g.Name)</h3><ul class=""cat-list"" lang=""en"">")
  foreach ($p in $g.Group) {
    $b = $p.Base.ToLower()
    $n = if ($enName.ContainsKey($b)) { $enName[$b] } elseif ($p.En) { $p.En } else { $p.Base }
    [void]$enView.AppendLine((Render-Poet $p $n $p.Ru))
  }
  [void]$enView.AppendLine('</ul></div>')
}

# --- Эпохи
$ageOrder = @(Get-Bases (Read-Page 'AgeCatalog.htm') | Where-Object { $_ -and $byBase.ContainsKey($_) })
$rest = @($poets | Where-Object { $ageOrder -notcontains $_.Base.ToLower() } | Sort-Object Born | ForEach-Object { $_.Base.ToLower() })
$ageView = New-Object System.Text.StringBuilder
$cur = 0; $open = $false; $prev = 0
foreach ($b in @($ageOrder) + @($rest)) {
  $p = $byBase[$b]
  $c = if ($p.Born -gt 0) { [int][Math]::Floor(($p.Born - 1) / 100) + 1 } else { $prev }
  $prev = $c
  if ($c -ne $cur -or -not $open) {
    if ($open) { [void]$ageView.AppendLine('</ul></div>') }
    $label = if ($c -gt 0) { "$(Roman $c) век" } else { 'Даты неизвестны' }
    $sub = if ($c -gt 0) { "<small>$(($c - 1) * 100 + 1)–$($c * 100)</small>" } else { '' }
    [void]$ageView.AppendLine("<div class=""cat-group"" id=""age-$c""><h3>$label $sub</h3><ul class=""cat-list"">")
    $cur = $c; $open = $true
  }
  [void]$ageView.AppendLine((Render-Poet $p $(if ($p.Ru) { $p.Ru } else { $p.Base }) $p.En))
}
if ($open) { [void]$ageView.AppendLine('</ul></div>') }
$ageNav = ([regex]::Matches($ageView.ToString(), 'id="age-(\d+)"><h3>([^<]+?) <') | ForEach-Object { "<a href=""#age-$($_.Groups[1].Value)"">$($_.Groups[2].Value -replace ' век', '')</a>" }) -join ''
$ageViewHtml = "<nav class=""letters wide"" aria-label=""Века"">$ageNav</nav>`n" + $ageView.ToString()

# --- Дни рождения
$monthsEn = 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'
$monthsRu = 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
$cal = [regex]::Replace((Read-Page 'calendarPoets.htm'), '(?i)(<br\b[^>]*>)\s*(\d{1,2})\s*(?=<br\b)', '$1<a name="$2"></a>')
$bd = New-Object System.Collections.ArrayList
$seen = @{}
$m = 0; $d = 0
foreach ($t in [regex]::Matches($cal, '(?i)<a\s+name\s*=\s*"?(' + ($monthsEn -join '|') + '|\d{1,2})"?|href\s*=\s*"?\s*(?<![A-Za-z])Poets/([^"#/\s>]+?)\.htm')) {
  if ($t.Groups[1].Success) {
    $v = $t.Groups[1].Value
    if ($v -match '^\d+$') { $d = [int]$v } else { $m = [array]::IndexOf($monthsEn, ($monthsEn | Where-Object { $_ -ieq $v })) + 1; $d = 0 }
    continue
  }
  $b = $t.Groups[2].Value.ToLower()
  if ($m -eq 0 -or $d -eq 0 -or -not $byBase.ContainsKey($b)) { continue }
  $k = "$m-$d-$b"
  if ($seen.ContainsKey($k)) { continue }
  $seen[$k] = $true
  [void]$bd.Add([pscustomobject]@{ M = $m; D = $d; Base = $b })
}
$bdView = New-Object System.Text.StringBuilder
[void]$bdView.AppendLine('<div class="months">')
for ($mi = 1; $mi -le 12; $mi++) {
  $rows = @($bd | Where-Object { $_.M -eq $mi } | Sort-Object D)
  [void]$bdView.AppendLine("<div class=""month cat-group""><h3>$($monthsRu[$mi - 1])</h3><ul>")
  foreach ($r in $rows) {
    $p = $byBase[$r.Base]
    $n = if ($p.Ru) { $p.Ru } else { $p.Base }
    $q = Esc (Norm-Q "$($p.Ru) $($p.En) $($p.Base)")
    [void]$bdView.AppendLine("<li data-md=""$mi-$($r.D)"" data-q=""$q""><span class=""day"">$($r.D)</span><a href=""$($p.Base).html"">$(Esc $n)</a><span class=""yrs"">$(Esc $p.Years)</span></li>")
  }
  [void]$bdView.AppendLine('</ul></div>')
}
[void]$bdView.AppendLine('</div>')

# --- Премии
function Strip-Ru([string]$t) { ([regex]::Replace($t, '\s*\([^()]*\p{IsCyrillic}[^()]*\)', '') -replace '\s+', ' ').Trim() }
function Render-PrizeRow([string]$period, [string]$what, [string]$note, $bases) {
  $on = @($bases | Where-Object { $_ -and $byBase.ContainsKey($_) })
  $named = @($on | Where-Object { $what -match [regex]::Escape((($byBase[$_].En + ' ' + $_) -split '\s+' | Where-Object { $_ })[-2]) })
  if ($on.Count -gt 1 -and $named.Count) { $on = $named }
  $links = ($on | ForEach-Object { $p = $byBase[$_]; "<a href=""$($p.Base).html"">$(Esc $(if ($p.Ru) { $p.Ru } else { $p.Base }))</a>" }) -join ', '
  $cls = if ($on.Count) { ' class="on"' } else { '' }
  $q = Esc (Norm-Q ("$what " + (($on | ForEach-Object { "$($byBase[$_].Ru) $($byBase[$_].En)" }) -join ' ')))
  $noteHtml = if ($note) { "<small>$(Esc $note)</small>" } else { '' }
  $linkHtml = if ($links) { "<span class=""site"">→ $links</span>" } else { '' }
  "<li$cls data-q=""$q""><span class=""yr"">$(Esc $period)</span><span class=""what"" lang=""en"">$(Esc $what)$noteHtml$linkHtml</span></li>"
}
function Get-LaurRows([string]$html) {
  $out = @()
  foreach ($line in Get-Lines $html) {
    $t = Strip-Ru (Plain $line)
    $mm = [regex]::Match($t, '^(.*?)[\s,]*(\d{4}\s*[-–]\s*(?:\d{4}|…|\.\.\.)?)\s*(.*)$')
    if (-not $mm.Success -or $mm.Groups[1].Value -notmatch '[A-Za-z]') { continue }
    $note = ($mm.Groups[3].Value -replace '^[\s–—-]+', '').Trim()
    $out += Render-PrizeRow ($mm.Groups[2].Value -replace '\s*[-–]\s*', '–') $mm.Groups[1].Value.Trim(' ', ',') $note (Get-Bases $line)
  }
  $out
}
function Get-YearRows([string]$html) {
  $out = @()
  foreach ($line in Get-Lines $html) {
    $t = Strip-Ru (Plain $line)
    $mm = [regex]::Match($t, '^(\d{4})\s+(.+)$')
    if (-not $mm.Success) { continue }
    $out += Render-PrizeRow $mm.Groups[1].Value $mm.Groups[2].Value.Trim() $null (Get-Bases $line)
  }
  $out
}
function Get-Between([string]$html, [string]$from, [string]$to) {
  $a = [regex]::Match($html, $from)
  if (-not $a.Success) { return '' }
  $rest = $html.Substring($a.Index + $a.Length)
  $b = [regex]::Match($rest, $to)
  if ($b.Success) { $rest.Substring(0, $b.Index) } else { $rest }
}
$laur = Read-Page 'Catalog_Laur.htm'
$pul = Read-Page 'Catalog_Pulitzer.htm'
$bol = Read-Page 'Catalog_Bollingen.htm'
$footRx = '(?i)<table|Библиотека|©'
$prizes = @(
  @{ Id = 'laur-uk'; Title = 'Поэты-лауреаты Англии'; Desc = 'Пожизненный титул придворного поэта; после смерти лауреата избирается следующий.'; Rows = Get-LaurRows (Get-Between $laur '(?i)name\s*=\s*"?eng"?[^>]*>' '(?i)name\s*=\s*"?usa"?') },
  @{ Id = 'laur-us'; Title = 'Поэты-лауреаты США'; Desc = 'С 1986 года титул присуждается ежегодно, иногда одному поэту несколько раз подряд.'; Rows = Get-LaurRows (Get-Between $laur '(?i)name\s*=\s*"?usa"?[^>]*>' $footRx) },
  @{ Id = 'pulitzer'; Title = 'Пулитцеровская премия'; Desc = 'Номинация «Поэзия»; официально с 1922 года, премии 1918 и 1919 годов — от Поэтического общества.'; Rows = Get-YearRows (Get-Between $pul '(?i)The Pulitzer Prize Winners' $footRx) },
  @{ Id = 'bollingen'; Title = 'Боллингенская премия'; Desc = 'Присуждается Библиотекой Йельского университета.'; Rows = Get-YearRows (Get-Between $bol '(?i)The Bollingen Prize Winners' $footRx) }
)
$prView = New-Object System.Text.StringBuilder
[void]$prView.AppendLine('<nav class="letters wide" aria-label="Премии">' + (($prizes | ForEach-Object { "<a href=""#$($_.Id)"">$($_.Title)</a>" }) -join '') + '</nav>')
[void]$prView.AppendLine('<div class="prizes">')
foreach ($pz in $prizes) {
  [void]$prView.AppendLine("<div class=""prize cat-group"" id=""$($pz.Id)""><h3>$($pz.Title)</h3><p>$($pz.Desc)</p><ol>")
  foreach ($r in $pz.Rows) { [void]$prView.AppendLine($r) }
  [void]$prView.AppendLine('</ol></div>')
}
[void]$prView.AppendLine('</div>')
[void]$prView.AppendLine('<p class="legend"><i></i>поэт есть на сайте — ссылка ведёт на его страницу</p>')

# --- Page
$n = $poets.Count
$page = @"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Каталог поэтов — Жемчужины английской поэзии</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500&family=Inter:wght@400;500;600&family=Literata:opsz,wght@7..72,400;7..72,500&display=swap">
<link rel="stylesheet" href="pearls.css?v=5">
</head>
<body>

<header class="site-header">
  <div class="wrap">
    <a class="brand" href="index.html"><span class="pearl" aria-hidden="true"></span><span>Жемчужины<small>английской поэзии</small></span></a>
    <nav class="nav" aria-label="Разделы">
      <a href="index.html">Поэты</a>
      <a href="catalog.html" aria-current="page">Каталог</a>
      <a href="../Gallery/frsGallery.htm">Галерея</a>
      <a href="../e_index.htm">English</a>
    </nav>
    <div class="tools">
      <button class="chip" id="theme" type="button" title="Светлая / тёмная тема">◐</button>
      <a class="chip" href="../RusCatalog.htm">Старая версия</a>
    </div>
  </div>
</header>

<main class="catalog">
<section class="section first">
  <div class="wrap">
    <div class="section-head">
      <h2>Каталог</h2>
      <p>$n $(Plural $n 'поэт' 'поэта' 'поэтов') · $totalPoems $(Plural $totalPoems 'стихотворение' 'стихотворения' 'стихотворений')</p>
    </div>
    <p class="cat-today" hidden></p>
    <div class="cat-bar">
      <div class="segmented cat-tabs" role="tablist" aria-label="Вид каталога">
        <button type="button" data-view="ru" aria-pressed="true">А–Я</button>
        <button type="button" data-view="en" aria-pressed="false">A–Z</button>
        <button type="button" data-view="age" aria-pressed="false">Эпохи</button>
        <button type="button" data-view="bd" aria-pressed="false">Дни рождения</button>
        <button type="button" data-view="prize" aria-pressed="false">Премии</button>
      </div>
      <input class="cat-search" type="search" placeholder="Найти поэта…" aria-label="Найти поэта">
    </div>
    <p class="cat-empty" hidden>Ничего не найдено.</p>
    <div class="cat-view" data-view="ru">
$($ruView.ToString())
    </div>
    <div class="cat-view" data-view="en" hidden>
$($enView.ToString())
    </div>
    <div class="cat-view" data-view="age" hidden>
$ageViewHtml
    </div>
    <div class="cat-view" data-view="bd" hidden>
$($bdView.ToString())
    </div>
    <div class="cat-view" data-view="prize" hidden>
$($prView.ToString())
    </div>
  </div>
</section>
</main>

<footer class="site-footer">
  <div class="wrap">
    <span>© 1998–2026 Елена и Яков Фельдман · Жемчужины английской поэзии</span>
    <span><a href="index.html">Поэты</a> · <a href="catalog.html">Каталог</a> · <a href="../Gallery/frsGallery.htm">Галерея</a></span>
  </div>
</footer>

<script src="pearls.js?v=5"></script>
</body>
</html>
"@
[IO.File]::WriteAllText((Join-Path $outDir 'catalog.html'), $page, $utf8)
"catalog: $n poets, birthdays $($bd.Count), prizes " + (($prizes | ForEach-Object { "$($_.Id)=$(@($_.Rows).Count)" }) -join ' ')
