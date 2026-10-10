param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$outDir = $PSScriptRoot
$lectDir = Join-Path $Root 'Lectures'

function Esc([string]$s) { $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function Plain([string]$s) { ([Net.WebUtility]::HtmlDecode([regex]::Replace($s, '(?s)<[^>]+>', ' ')) -replace '[\s\u00A0]+', ' ').Trim() }
function Norm-T([string]$s) { ((Plain $s).ToLower().Replace('ё', 'е') -replace '[^\p{L}\p{Nd}]+', '') }
function Fix-Anchor([string]$a) { ($a.Trim() -replace '\s+', '-') }

$seriesName = 'Изобразительные средства поэтического текста'
function A($g, $slug, $file, $from, $to, $title, $sub, $extra) {
  $o = [ordered]@{ Group = $g; Slug = $slug; File = $file; From = $from; To = $to; Title = $title; Sub = $sub; Part = $null; Lang = $null; Note = $null; Drop = @(); Strip = @(); Start = 0; End = 0; Html = ''; Min = 0 }
  if ($extra) { foreach ($k in $extra.Keys) { $o[$k] = $extra[$k] } }
  [pscustomobject]$o
}
$list = @(
  A 1 'shakespeare' 'school.htm' 'ws' $null 'Трагедии Шекспира и уровни его персонажей' "Shakespeare's plays and levels' theory" @{ Lang = 'en'; Note = 'Русский оригинал этой статьи не сохранился — здесь её английская версия.'; Strip = @('William Sheakespeare tragedies and levels of his heroes'); Drop = @('Russian origin of the paper') }
  A 2 'concept' 'concept.htm' $null $null 'Как, когда и почему я позволяю себе менять концепцию стихотворения при его переводе' 'Истинная и позитивная картина мира — на примерах Харди и Грейвза'
  A 3 'byron' 'byronLT.htm' $null $null 'Байрон и другие' 'Одно стихотворение Байрона в переводах Лермонтова и Тютчева'
  A 4 'fonetika-primery' 'teorYakov1.htm' 'fon3' $null 'Фонетика — примеры' "Почему «мне до фонаря» — лучший перевод «I don't care»"
  A 5 'credo' 'credo.htm' $null $null 'Кредо нашей библиотеки' 'Чем «Жемчужины» отличаются от других электронных библиотек'
  A 6 'toporov' 'examples.htm' '11' '22' 'По ложному следу' 'Топоров переводит Мореса'
  A 7 'kushner' 'examples.htm' '22' '33' 'Философ или психолог?' 'Кушнер переводит Мореса'
  A 8 'dickinson' 'examples.htm' '33' 'kudm' 'Острый глаз, тугое ухо' 'Переводя Э. Дикинсон'
  A 8 'perevody-k-statyam' 'examples.htm' 'kudm' $null 'Переводы к статьям' 'Полные тексты переводов А. Кушнера и В. Топорова' @{ Part = 'appendix' }
  A 9 'vvedenie' 'teorYakov1.htm' 'vved' 'obraz' 'Введение' 'Что такое поэтический текст' @{ Part = '' }
  A 9 'obraz' 'teorYakov1.htm' 'obraz' 'formula' 'Образ' $null @{ Part = '1' }
  A 9 'formula' 'teorYakov1.htm' 'formula' 'styl' 'Формула' $null @{ Part = '2' }
  A 9 'stil' 'teorYakov1.htm' 'styl' 'phonetika' 'Стиль' $null @{ Part = '3' }
  A 9 'fonetika' 'teorYakov1.htm' 'phonetika' 'smisl dinamik conz' 'Фонетика' $null @{ Part = '4' }
  A 9 'smysl' 'teorYakov1.htm' 'smisl dinamik conz' 'fon3' 'Смысл, динамика, концепция' $null @{ Part = '5' }
  A 9 'rifma' 'Lx1.htm' $null $null 'Рифма, ритм, движение' $null @{ Part = '6' }
  A 9 'ponyatie' 'Lx2.htm' $null $null 'Понятие, факт, ощущение' $null @{ Part = '7' }
  A 9 'zaklyuchenie' 'Zakluchenie.htm' $null $null 'Заключение' 'Десять каналов поэтического текста' @{ Part = ''; Subst = @{ 'узнать здесь и <a' = 'узнать <a' } }
  A 10 'tri-energii' 'trienerg.htm' $null $null 'Три энергии поэтического текста' 'Эпическая, драматическая, лирическая'
  A 11 'trud' 'Lx3.htm' 'zametki' 'naprav' 'Труд поэта, труд переводчика' $null
  A 12 'napravleniya' 'Lx3.htm' 'naprav' 'plastmas' 'Направления в поэзии и в поэтическом переводе' $null
  A 13 'plastmassovyi-vek' 'Lx3.htm' 'plastmas' $null 'Пластмассовый век русской поэзии' $null
  A 14 'volnye-perevody' 'Lx4.htm' $null $null 'О вольных переводах' 'Шесть персонажей в поисках истины'
  A 15 'pushkin' 'Pushkin.htm' $null $null 'Переводчик имеет право' 'Пушкинский перевод шотландской баллады'
  A 16 'kak-ya-perevozhu' 'Perevod.htm' $null $null 'Как я перевожу стихи' $null
)
$alias = @{ 'lect3.htm' = 'stil' }
$bySlug = @{}
foreach ($a in $list) { $bySlug[$a.Slug] = $a }

$raw = @{}
function Get-Raw([string]$f) {
  $k = $f.ToLower()
  if (-not $raw.ContainsKey($k)) { $raw[$k] = [IO.File]::ReadAllText((Join-Path $lectDir $f), [Text.Encoding]::UTF8) }
  $raw[$k]
}
function Anchor-Rx([string]$name) { '(?i)<a\s[^>]*?\bname\s*=\s*"?' + [regex]::Escape($name) + '"?(?=[\s>])' }
function Find-Anchor([string]$t, [string]$name) {
  $m = [regex]::Match($t, (Anchor-Rx $name))
  if (-not $m.Success) { throw "anchor '$name' not found" }
  $opens = [regex]::Matches($t.Substring(0, $m.Index), '(?i)<(p|h[1-6])\b')
  if ($opens.Count -eq 0) { return $m.Index }
  $bs = $opens[$opens.Count - 1].Index
  if ($t.Substring($bs, $m.Index - $bs) -match '(?i)</(p|h[1-6]|table|div|td)>') { return $m.Index }
  $bs
}
function Body-Start([string]$t) { $m = [regex]::Match($t, '(?i)<body\b[^>]*>'); if ($m.Success) { $m.Index + $m.Length } else { 0 } }
function Footer-Start([string]$t, [int]$from) {
  $rest = $t.Substring($from)
  $e = $t.Length
  foreach ($rx in '(?i)</body>', '(?i)<!--\s*BEGIN WEBSIDESTORY') {
    $m = [regex]::Match($rest, $rx)
    if ($m.Success) { $e = [Math]::Min($e, $from + $m.Index) }
  }
  $c = [regex]::Match($rest, '(?i)frsCatalogs|EngCatalog\.htm')
  if ($c.Success) {
    $tb = $t.LastIndexOf('<table', $from + $c.Index, [StringComparison]::OrdinalIgnoreCase)
    if ($tb -gt $from) { $e = [Math]::Min($e, $tb) }
  }
  $e
}
foreach ($a in $list) {
  $t = Get-Raw $a.File
  $a.Start = if ($a.From) { Find-Anchor $t $a.From } else { Body-Start $t }
  $fe = Footer-Start $t $a.Start
  $a.End = if ($a.To) { [Math]::Min((Find-Anchor $t $a.To), $fe) } else { $fe }
}

function Find-Seg([string]$file, [string]$frag) {
  $k = $file.ToLower()
  if ($alias.ContainsKey($k)) { return $bySlug[$alias[$k]] }
  $segs = @($list | Where-Object { $_.File -ieq $file } | Sort-Object Start)
  if (-not $segs.Count) { return $null }
  if (-not $frag) { return $segs[0] }
  $m = [regex]::Match((Get-Raw $segs[0].File), (Anchor-Rx $frag))
  if (-not $m.Success) { return $segs[0] }
  foreach ($sg in $segs) { if ($m.Index -ge $sg.Start -and $m.Index -lt $sg.End) { return $sg } }
  if ($m.Index -lt $segs[0].Start) { return $segs[0] }
  $segs[-1]
}
function Resolve-Rel([string]$path) {
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($x in ('Lectures/' + $path) -split '/') {
    if ($x -eq '..') { if ($parts.Count) { $parts.RemoveAt($parts.Count - 1) } }
    elseif ($x -ne '.' -and $x -ne '') { $parts.Add($x) }
  }
  $parts -join '/'
}
$designFiles = @{}
Get-ChildItem $outDir -Filter *.html | ForEach-Object { $designFiles[$_.BaseName.ToLower()] = $_.Name }

$linkFixes = @{}
Get-Content (Join-Path $outDir 'link-fixes.tsv') -Encoding UTF8 | Select-Object -Skip 1 | ForEach-Object {
  $f = $_ -split "`t"
  if ($f[0]) { $linkFixes[$f[0]] = $f[1] }
}

function Map-Href([string]$href, $cur) {
  $h = [Net.WebUtility]::HtmlDecode($href).Trim()
  if ($h -eq '' -or $h -match '^(?i)javascript:') { return $null }
  if ($h -match '^(?i)mailto:') { return $h }
  $isRoot = $false
  if ($h -match '^(?i)https?://members\.tripod\.com/poetry_pearls/(.*)$') { $h = $Matches[1]; $isRoot = $true }
  elseif ($h -match '^(?i)[a-z]+://') {
    if ($linkFixes.ContainsKey($h)) { if ($linkFixes[$h]) { return $linkFixes[$h] } else { return $null } }
    if ($h -match '(?i)tripod\.com|hitbox\.com|geocities') { return $null }
    return $h
  }
  $path, $frag = $h -split '#', 2
  if ($frag) { $frag = [uri]::UnescapeDataString($frag) }
  $rel = if (-not $path) { "Lectures/$($cur.File)" } elseif ($isRoot) { Resolve-Rel "../$path" } else { Resolve-Rel $path }
  $fx = if ($frag) { '#' + (Fix-Anchor $frag) } else { '' }
  if ($rel -match '^(?i)lst/rbooks\.htm$') { return 'https://jfeldman777.github.io/gala/' }
  if ($rel -match '^(?i)Lectures/([^/]+)$') {
    $seg = Find-Seg $Matches[1] $frag
    if ($seg) {
      $top = (-not $frag) -or $frag -eq $seg.From
      if ($seg.Slug -eq $cur.Slug) { if ($top) { return '#top' } else { return $fx } }
      if ($top) { return "st-$($seg.Slug).html" }
      return "st-$($seg.Slug).html$fx"
    }
  }
  if ($rel -match '^(?i)e?Poets/([^/]+)\.htm$') {
    $k = $Matches[1].ToLower()
    if ($designFiles.ContainsKey($k)) { return $designFiles[$k] + $fx }
  }
  "../$rel" + $(if ($frag) { "#$frag" } else { '' })
}

$keepTags = @{ p = 'p'; br = 'br'; b = 'b'; strong = 'strong'; i = 'i'; em = 'em'; u = 'u'; sup = 'sup'; sub = 'sub'; a = 'a'; img = 'img'; h1 = 'h2'; h2 = 'h2'; h3 = 'h3'; h4 = 'h3'; h5 = 'h3'; h6 = 'h3'; ul = 'ul'; ol = 'ol'; li = 'li'; table = 'table'; tr = 'tr'; td = 'td'; th = 'th'; blockquote = 'blockquote'; hr = 'hr'; pre = 'pre'; dl = 'dl'; dt = 'dt'; dd = 'dd' }
$script:cur = $null
$tagEval = [Text.RegularExpressions.MatchEvaluator] {
  param($m)
  $tag = $m.Groups[2].Value.ToLower()
  if (-not $keepTags.ContainsKey($tag)) { return '' }
  $nt = $keepTags[$tag]
  if ($m.Groups[1].Value -eq '/') { if ($nt -eq 'br' -or $nt -eq 'hr' -or $nt -eq 'img') { return '' }; return "</$nt>" }
  $at = @{}
  foreach ($am in [regex]::Matches($m.Groups[3].Value, '(?i)\b(href|name|src|alt|colspan|rowspan)\s*=\s*(?:"([^"]*)"|''([^'']*)''|([^\s>]+))')) {
    $at[$am.Groups[1].Value.ToLower()] = $am.Groups[2].Value + $am.Groups[3].Value + $am.Groups[4].Value
  }
  if ($nt -eq 'a') {
    $out = ''
    if ($at['name']) { $out += ' id="' + (Esc (Fix-Anchor ([uri]::UnescapeDataString($at['name'])))) + '"' }
    if ($at['href']) { $u = Map-Href $at['href'] $script:cur; if ($u) { $out += ' href="' + (Esc $u) + '"' } }
    return "<a$out>"
  }
  if ($nt -eq 'img') {
    $src = $at['src']
    if (-not $src -or $src -match '(?i)pearls/|hitbox|^[a-z]+://') { return '' }
    return '<img src="../' + (Esc (Resolve-Rel $src)) + '" alt="' + (Esc $at['alt']) + '" loading="lazy">'
  }
  if ($nt -eq 'td' -or $nt -eq 'th') {
    $out = ''
    foreach ($k in 'colspan', 'rowspan') { if ($at[$k] -match '^\d+$') { $out += " $k=""$($at[$k])""" } }
    return "<$nt$out>"
  }
  "<$nt>"
}
function Anchors-Of([string]$s) { ([regex]::Matches($s, '<a id="[^"]*">') | ForEach-Object { $_.Value + '</a>' }) -join '' }
$blockRx = '(?is)<(p|h2|h3)>((?:(?!<(?:p|h2|h3)>).)*?)</\1>'
$navEval = [Text.RegularExpressions.MatchEvaluator] {
  param($m)
  $inner = $m.Groups[2].Value
  $txt = Plain $inner
  $ids = Anchors-Of $inner
  if ($txt -eq '' -and $inner -notmatch '<img') { return $ids }
  if ($txt -match '(?i)главную страницу|main page') { return $ids }
  if ($txt -match '^(Я(ков)?\.?\s*Фельдман|Jacob Feldman|Yacov Feldman)\s*\.?$') { return $ids }
  if ($txt -match '^©') { return $ids }
  $links = [regex]::Matches($inner, '(?is)<a\s[^>]*href[^>]*>.*?</a>')
  if ($links.Count -ge 2) {
    $rest = $inner
    foreach ($l in $links) { $rest = $rest.Replace($l.Value, '') }
    if (((Plain $rest) -replace '[^\p{L}]', '').Length -le 12) { return $ids }
  }
  $m.Value
}
function Remove-Heading([string]$s, [string[]]$titles) {
  foreach ($t in $titles) {
    if (-not $t) { continue }
    $nt = Norm-T $t
    if ($nt.Length -lt 3) { continue }
    $done = $false
    foreach ($b in [regex]::Matches($s, $blockRx)) {
      if ($b.Index -gt 2500) { break }
      $pt = Plain $b.Groups[2].Value
      if ((Norm-T $pt).Contains($nt) -and $pt.Length -le $t.Length + 80) {
        $s = $s.Remove($b.Index, $b.Length).Insert($b.Index, (Anchors-Of $b.Groups[2].Value))
        $done = $true; break
      }
    }
    if ($done) { return $s }
    $words = @($t -split '[^\p{L}\p{Nd}]+' | Where-Object { $_ })
    $rx = '(?i)' + (($words | ForEach-Object { [regex]::Escape($_) -replace '[её]', '[её]' }) -join '(?:[^\p{L}\p{Nd}<]|<[^>]*>)*')
    $head = $s.Substring(0, [Math]::Min(2500, $s.Length))
    $m = [regex]::Match($head, $rx)
    if ($m.Success) { return $s.Remove($m.Index, $m.Length) }
  }
  $s
}
$verseEval = [Text.RegularExpressions.MatchEvaluator] {
  param($m)
  $lines = @($m.Groups[1].Value -split '<br>' | ForEach-Object { Plain $_ } | Where-Object { $_ })
  if ($lines.Count -ge 2) {
    $avg = ($lines | Measure-Object Length -Average).Average
    $max = ($lines | Measure-Object Length -Maximum).Maximum
    if ($avg -le 60 -and $max -le 90) { return '<p class="verse">' + $m.Groups[1].Value + '</p>' }
  }
  $m.Value
}
$tableEval = [Text.RegularExpressions.MatchEvaluator] {
  param($m)
  if ([regex]::Matches($m.Value, '<br>').Count -ge 3) { return '<table class="pair">' + $m.Groups[1].Value + '</table>' }
  $m.Value
}
function Fix-P([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  $open = $false; $pos = 0
  foreach ($m in [regex]::Matches($s, '<(/?)(p|h2|h3|table|ul|ol|blockquote|hr|tr|td|th)\b[^>]*>')) {
    [void]$sb.Append($s, $pos, $m.Index - $pos); $pos = $m.Index + $m.Length
    if ($m.Groups[2].Value -eq 'p') {
      if ($open) { [void]$sb.Append('</p>'); $open = $false }
      if ($m.Groups[1].Value -ne '/') { [void]$sb.Append('<p>'); $open = $true }
      continue
    }
    if ($open) { [void]$sb.Append('</p>'); $open = $false }
    [void]$sb.Append($m.Value)
  }
  [void]$sb.Append($s, $pos, $s.Length - $pos)
  if ($open) { [void]$sb.Append('</p>') }
  $sb.ToString()
}
function Clean([string]$html, $a) {
  $script:cur = $a
  $s = [regex]::Replace($html, '(?is)<(script|style|noscript|select|textarea|form|title|head)\b.*?</\1\s*>', '')
  $s = [regex]::Replace($s, '(?s)<!--.*?-->', '')
  $s = [regex]::Replace($s, '(?is)<!\[.*?\]>|<\?xml[^>]*>', '')
  $s = ($s -replace '(?i)&nbsp;', ' ').Replace([string][char]0xA0, ' ') -replace '\s+', ' '
  foreach ($d in $a.Drop) { $s = [regex]::Replace($s, '(?i)' + [regex]::Escape($d), '') }
  $s = [regex]::Replace($s, '(?is)<p\b[^>]*class="?topicHead"?[^>]*>(.*?)</p>', '<h3>$1</h3>')
  $s = [regex]::Replace($s, '(?is)<p\b[^>]*>\s*<font\b[^>]*size\s*=\s*"?\+?[4-7]"?[^>]*>((?:(?!</?p\b).){1,300}?)</font>\s*</p>', '<h3>$1</h3>')
  $s = [regex]::Replace($s, '<(/?)([a-zA-Z][\w:]*)([^>]*)>', $tagEval)
  $s = Fix-P $s
  $s = [regex]::Replace($s, '(?is)<a>(.*?)</a>', '$1')
  $s = [regex]::Replace($s, '\s*<br>\s*', '<br>')
  for ($i = 0; $i -lt 4; $i++) {
    $s = [regex]::Replace($s, '<(p|h2|h3|li|td)>\s*(?:<br>\s*)+', '<$1>')
    $s = [regex]::Replace($s, '(?:<br>\s*)+</(p|h2|h3|li|td)>', '</$1>')
    $s = [regex]::Replace($s, '<(b|strong|i|em|u|sup|sub)>(\s*)</\1>', '$2')
    $s = [regex]::Replace($s, '<(p|h2|h3|li|blockquote)>\s*</\1>', '')
  }
  $s = [regex]::Replace($s, $blockRx, $navEval)
  $s = Remove-Heading $s (@($a.Title) + @($a.Strip))
  $s = [regex]::Replace($s, '(?is)<(p|h2|h3)>\s*[\d.\s]*\s*</\1>', '')
  $s = [regex]::Replace($s, '<(p|h2|h3|li|blockquote)>\s*</\1>', '')
  $s = [regex]::Replace($s, '(?:<hr>\s*){2,}', '<hr>')
  $s = [regex]::Replace($s, '^(?:\s|<hr>|<br>)+|(?:\s|<hr>|<br>)+$', '')
  $s = [regex]::Replace($s, '<p>\s*<(b|strong)>([^<]{2,60}?)</\1>\s*</p>', { param($m) if ($m.Groups[2].Value.Trim() -match '[,;:]$') { $m.Value } else { '<h3>' + $m.Groups[2].Value.Trim() + '</h3>' } })
  $s = [regex]::Replace($s, '(?s)<p>((?:(?!</?p>).)*?)</p>', $verseEval)
  $s = [regex]::Replace($s, '(?s)<table>(.*?)</table>', $tableEval)
  $s = [regex]::Replace($s, '(?i)(</(?:p|h2|h3|table|tr|ul|ol|li|blockquote)>|<hr>)', "`$1`n")
  $s.Trim()
}

foreach ($a in $list) {
  $t = Get-Raw $a.File
  $a.Html = Clean $t.Substring($a.Start, $a.End - $a.Start) $a
  if ($a.Subst) { foreach ($k in $a.Subst.Keys) { $a.Html = $a.Html.Replace($k, $a.Subst[$k]) } }
  $words = @((Plain $a.Html) -split '\s+' | Where-Object { $_ }).Count
  $a.Min = [Math]::Max(1, [int][Math]::Round($words / 180))
}

function Min-Label([int]$n) { "$n мин" }
function Part-Label($a) { if ($a.Part) { "$($a.Part). $($a.Title)" } else { $a.Title } }
function Page([string]$title, [string]$oldHref, [string]$main) {
@"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(Esc $title) — Жемчужины английской поэзии</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500&family=Inter:wght@400;500;600&family=Literata:opsz,wght@7..72,400;7..72,500&display=swap">
<link rel="stylesheet" href="pearls.css?v=14">
</head>
<body>

<header class="site-header">
  <div class="wrap">
    <a class="brand" href="index.html"><span class="pearl" aria-hidden="true"></span><span>Жемчужины<small>английской поэзии</small></span></a>
    <nav class="nav" aria-label="Разделы">
      <a href="index.html">Поэты</a>
      <a href="catalog.html">Каталог</a>
      <a href="articles.html" aria-current="page">Статьи</a>
      <a href="gallery.html">Галерея</a>
      <a href="../e_index.htm">English</a>
    </nav>
    <div class="tools">
      <button class="chip" id="theme" type="button" title="Светлая / тёмная тема">◐</button>
      <a class="chip" href="$oldHref">Старая версия</a>
    </div>
  </div>
</header>

<main id="top">
$main
</main>

<footer class="site-footer">
  <div class="wrap">
    <span>© 1998–2026 Елена и Яков Фельдман · Жемчужины английской поэзии</span>
    <span><a href="index.html">Поэты</a> · <a href="catalog.html">Каталог</a> · <a href="articles.html">Статьи</a> · <a href="gallery.html">Галерея</a></span>
  </div>
</footer>

<script src="pearls.js?v=8"></script>
</body>
</html>
"@
}

$series = @($list | Where-Object { $_.Group -eq 9 })
for ($i = 0; $i -lt $list.Count; $i++) {
  $a = $list[$i]
  $old = "../Lectures/$($a.File)" + $(if ($a.From) { '#' + [uri]::EscapeDataString($a.From) } else { '' })
  $eyebrow = if ($a.Group -eq 9) { "<a href=""articles.html"">Статьи</a> · Цикл лекций" } elseif ($a.Part -eq 'appendix') { "<a href=""articles.html"">Статьи</a> · Приложение" } else { "<a href=""articles.html"">Статьи</a> · Яков Фельдман" }
  $sub = if ($a.Sub) { "<p class=""alt"">$(Esc $a.Sub)</p>" } else { '' }
  $h1 = if ($a.Group -eq 9 -and $a.Part) { "<span class=""num"">$($a.Part)</span>$(Esc $a.Title)" } else { Esc $a.Title }
  $seriesNav = ''
  if ($a.Group -eq 9) {
    $items = ($series | ForEach-Object {
        $cur = if ($_.Slug -eq $a.Slug) { ' aria-current="page"' } else { '' }
        "<li><a href=""st-$($_.Slug).html""$cur>$(Esc (Part-Label $_))</a></li>"
      }) -join ''
    $seriesNav = "<nav class=""series-nav"" aria-label=""Цикл""><p>$seriesName</p><ol>$items</ol></nav><script>var c=document.querySelector('.series-nav [aria-current]'),o=c.closest('ol');o.scrollLeft+=c.getBoundingClientRect().left-o.getBoundingClientRect().left-24;</script>"
  }
  $note = if ($a.Note) { "<p class=""essay-note"">$(Esc $a.Note)</p>" } else { '' }
  $lang = if ($a.Lang) { " lang=""$($a.Lang)""" } else { '' }
  $pager = ''
  if ($i -gt 0) { $p = $list[$i - 1]; $pager += "<a class=""prev"" href=""st-$($p.Slug).html""><small>← Назад</small><span>$(Esc $p.Title)</span></a>" }
  if ($i -lt $list.Count - 1) { $n = $list[$i + 1]; $pager += "<a class=""next"" href=""st-$($n.Slug).html""><small>Дальше →</small><span>$(Esc $n.Title)</span></a>" }
  $main = @"
<section class="section first">
  <div class="wrap">
    <header class="art-head">
      <p class="eyebrow">$eyebrow</p>
      <h1>$h1</h1>
      $sub
      <p class="meta">Яков Фельдман · $(Min-Label $a.Min) чтения</p>
    </header>
    $seriesNav
    $note
    <article class="essay"$lang>
$($a.Html)
    </article>
    <nav class="essay-pager" aria-label="Статьи">$pager</nav>
  </div>
</section>
"@
  [IO.File]::WriteAllText((Join-Path $outDir "st-$($a.Slug).html"), (Page $a.Title $old $main), $utf8)
}

# --- Index
$rows = New-Object System.Text.StringBuilder
foreach ($g in ($list | Group-Object Group | Sort-Object { [int]$_.Name })) {
  $n = '{0:00}' -f [int]$g.Name
  if ([int]$g.Name -eq 9) {
    $tot = ($g.Group | Measure-Object Min -Sum).Sum
    $parts = ($g.Group | ForEach-Object { "<li><a href=""st-$($_.Slug).html""><span>$(Esc (Part-Label $_))</span><span class=""m"">$(Min-Label $_.Min)</span></a></li>" }) -join ''
    [void]$rows.AppendLine("<li class=""art-series""><span class=""n"">$n</span><div><b>$seriesName</b><i>Цикл из $($g.Group.Count) лекций · $(Min-Label $tot)</i><ol>$parts</ol></div></li>")
    continue
  }
  foreach ($a in $g.Group) {
    $sub = if ($a.Sub) { "<i>$(Esc $a.Sub)</i>" } else { '' }
    if ($a.Part -eq 'appendix') {
      [void]$rows.AppendLine("<li class=""art-extra""><a class=""row"" href=""st-$($a.Slug).html""><span class=""n""></span><span class=""t""><b>$(Esc $a.Title)</b>$sub</span><span class=""m"">$(Min-Label $a.Min)</span></a></li>")
      continue
    }
    $en = if ($a.Lang -eq 'en') { ' <em>in English</em>' } else { '' }
    [void]$rows.AppendLine("<li><a class=""row"" href=""st-$($a.Slug).html""><span class=""n"">$n</span><span class=""t""><b>$(Esc $a.Title)$en</b>$sub</span><span class=""m"">$(Min-Label $a.Min)</span></a></li>")
  }
}
$others = @(
  @('Gasparov.htm', 'М. Л. Гаспаров', 'Сонеты Шекспира — переводы Маршака'),
  @('tinanov1.htm', 'Юрий Тынянов', 'Тютчев и Гейне'),
  @('plach.htm', 'Т. А. Ладошкина', 'Плач по Шекспиру'),
  @('info.htm', 'М. Волькенштейн', 'Стихи как сложная информационная система'),
  @('Mavlevich2.htm', 'Наталия Мавлевич', 'Переводчик и время'),
  @('Lect0.htm#geiman', 'Александр Гейман', 'Тексты и смыслы'),
  @('answers5.htm', 'Бойченко, Борисов, Гейман, Визель, Немцов, Фельдман', 'Проблемы перевода поэтического текста с английского языка на русский'),
  @('contentsP.htm', 'Практикум', 'Варианты переводов'),
  @('backOffice.htm', 'Об авторах', 'Кто пишет в «Лаборатории»')
)
$otherHtml = ($others | ForEach-Object { "<li><a href=""../Lectures/$($_[0])""><b>$(Esc $_[2])</b><span>$(Esc $_[1])</span></a></li>" }) -join "`n"
$engHtml = (@(
    @('../Lectures/school.htm', 'Poetry as a calculus'),
    @('../theory/whynhow.htm', 'What, Why and How I am translating'),
    @('../Lectures/ePushkin.htm', 'What Good Translator is allowed to do')
  ) | ForEach-Object { "<li><a href=""$($_[0])"" lang=""en""><b>$(Esc $_[1])</b><span>Jacob Feldman</span></a></li>" }) -join "`n"
$cnt = @($list | Group-Object Group).Count
$main = @"
<section class="section first">
  <div class="wrap">
    <header class="art-head wide">
      <p class="eyebrow">Лаборатория · Яков Фельдман</p>
      <h1>Статьи</h1>
      <p class="alt">Теория поэтического текста и поэтического перевода</p>
      <p class="meta">$cnt статей · образ, формула, стиль, фонетика, ритм — и как всё это переводить</p>
    </header>
    <ol class="art-list">
$($rows.ToString())
    </ol>
  </div>
</section>
<section class="section">
  <div class="wrap">
    <div class="section-head"><h2>Другие авторы</h2><p>Статьи из «Лаборатории» в прежнем оформлении</p></div>
    <ul class="art-other">
$otherHtml
    </ul>
    <div class="section-head sub"><h2>In English</h2></div>
    <ul class="art-other">
$engHtml
    </ul>
  </div>
</section>
"@
[IO.File]::WriteAllText((Join-Path $outDir 'articles.html'), (Page 'Статьи' '../Lectures/contents.htm' $main), $utf8)
"articles: $($list.Count) pages, " + (($list | ForEach-Object { "$($_.Slug)=$($_.Min)m" }) -join ' ')
