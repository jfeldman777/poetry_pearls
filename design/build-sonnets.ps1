param(
  [string]$Root = (Split-Path $PSScriptRoot -Parent),
  [switch]$Check,
  [string[]]$ShowPoem = @()
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$outDir = $PSScriptRoot
$cssV = 18
$jsV = 12
$nb = [string][char]0xA0
$emOn = [string][char]1
$emOff = [string][char]2
$cp1252 = [Text.Encoding]::GetEncoding(1252)

function Esc([string]$s) { $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function Read-Src([string]$rel) { [regex]::Replace([IO.File]::ReadAllText((Join-Path $Root $rel), [Text.Encoding]::UTF8), '(?s)<!--new-design-->.*?<!--/new-design-->\s*', '') }
# &#151; and friends decode to C1 controls; browsers read them as Windows-1252, so do we.
function Dec([string]$s) {
  [regex]::Replace([Net.WebUtility]::HtmlDecode($s), '[\u0080-\u009F]', { param($m) $cp1252.GetString([byte[]]@([int][char]$m.Value[0])) })
}
function Plain([string]$s) { ((Dec ([regex]::Replace($s, '<[/!]?[a-zA-Z][^>]*>', ' '))) -replace '[\s\u00A0]+', ' ').Trim() }
function Norm([string]$s) { [regex]::Replace($s.ToLowerInvariant().Replace('ё', 'е'), '[^\p{L}\p{Nd}]', '') }
function Plural([int]$n, [string]$one, [string]$few, [string]$many) {
  $m10 = $n % 10; $m100 = $n % 100
  if ($m10 -eq 1 -and $m100 -ne 11) { return "$n $one" }
  if ($m10 -ge 2 -and $m10 -le 4 -and ($m100 -lt 12 -or $m100 -gt 14)) { return "$n $few" }
  "$n $many"
}
function Roman([int]$n) {
  $v = 100, 90, 50, 40, 10, 9, 5, 4, 1
  $r = 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'
  $s = ''
  for ($i = 0; $i -lt $v.Count; $i++) { while ($n -ge $v[$i]) { $s += $r[$i]; $n -= $v[$i] } }
  $s
}

# A poem is a list of stanzas; a stanza is @{ Lines; Indent }. Italics survive as $emOn/$emOff markers.
function New-Poem($stanzas) { @{ Stanzas = @($stanzas); Epigraph = @(); Notes = @(); Date = $null } }
function Split-Stanzas([string]$text) {
  $out = @()
  $cur = @()
  foreach ($raw in ($text -split "`n")) {
    $line = $raw -replace '[ \t]+', ' '
    $lead = [regex]::Match($line, '^[ \u00A0]*').Value
    $line = $line.Trim()
    if ($lead.Replace(' ', '').Length -ge 4 -and $line) { $line = ($nb * [Math]::Min(48, $lead.Replace(' ', '').Length)) + $line }
    if ($line.Replace($emOn, '').Replace($emOff, '').Trim()) { $cur += $line; continue }
    if ($cur.Count) { $out += , @{ Lines = $cur; Indent = $false }; $cur = @() }
  }
  if ($cur.Count) { $out += , @{ Lines = $cur; Indent = $false } }
  , $out
}
# HTML fragment -> stanzas: <br> breaks a line, block tags break a stanza.
function Get-Poem([string]$html) {
  $s = ($html -replace '\r', '') -replace '\n', ' '
  $s = [regex]::Replace($s, '(?is)<(script|style)\b.*?</\1>', '')
  $s = [regex]::Replace($s, '(?s)<!--.*?-->', '')
  $s = [regex]::Replace($s, '(?i)<br\b[^>]*>', "`n")
  $s = [regex]::Replace($s, '(?i)</?(p|div|dl|dt|dd|h\d|center|table|tr|td|ul|li|hr)\b[^>]*>', "`n`n")
  $s = [regex]::Replace($s, '(?i)<(i|em)\b[^>]*>', $emOn)
  $s = [regex]::Replace($s, '(?i)</(i|em)>', $emOff)
  $s = [regex]::Replace($s, '<[/!]?[a-zA-Z][^>]*>', '')
  $s = Dec $s
  $s = [regex]::Replace($s, "$emOn(\s*)$emOff", '$1')
  New-Poem (Split-Stanzas $s)
}
# Text from a <pre> block: real newlines, blank lines between stanzas.
function Get-PrePoem([string]$text) {
  $s = $text -replace '\r', ''
  $s = [regex]::Replace($s, '(?i)<(hr|br|/?ul)\b[^>]*>', "`n")
  $s = [regex]::Replace($s, '<[/!]?[a-zA-Z][^>]*>', '')
  New-Poem (Split-Stanzas (Dec $s))
}
# Translator's notes and footnotes (after "Примечание..." or a line of dashes) go under the poem.
function Move-Notes($p) {
  $keep = @(); $notes = @(); $on = $false
  foreach ($st in $p.Stanzas) {
    $body = @(); $note = @()
    foreach ($l in $st.Lines) {
      $bare = ($l -replace "[$emOn$emOff]", '').Trim()
      if (-not $on -and ($keep.Count -or $body.Count) -and ($bare -match '^-{8,}$' -or ($bare -match '^Примечани' -and -not $body.Count))) { $on = $true }
      if ($on) { if ($bare -notmatch '^-{8,}$') { $note += $bare } } else { $body += $l }
    }
    if ($body.Count) { $keep += , @{ Lines = $body; Indent = $st.Indent } }
    if ($note.Count) { $notes += ($note -join ' ') }
  }
  $p.Stanzas = $keep
  $p.Notes = $notes
}
function Drop-Number($p, [int]$n) {
  while ($p.Stanzas.Count -and $p.Stanzas[0].Lines.Count -eq 1 -and $p.Stanzas[0].Lines[0] -match '^\d+$') { $p.Stanzas = @($p.Stanzas | Select-Object -Skip 1) }
}
function Poem-Lines($p) { @($p.Stanzas | ForEach-Object { $_.Lines } | ForEach-Object { $_ }) }
function Poem-Text($p) { ((Poem-Lines $p) -join "`n").Replace($emOn, '').Replace($emOff, '').Replace($nb, '') }
function First-Line($p) {
  $s = ((Poem-Lines $p | Select-Object -First 1) -replace "[$emOn$emOff$nb]", '').Trim().TrimEnd(',', ';', ':', '.', '-', '—', ' ')
  # The originals print the first word in capitals: "TIRED with all these".
  $m = [regex]::Match($s, '^(\p{Lu})(\p{Lu}+)\b')
  if ($m.Success) { $s = $m.Groups[1].Value + $m.Groups[2].Value.ToLowerInvariant() + $s.Substring($m.Length) }
  $s
}

# ---------- Sources

$sonnets = @{}
for ($n = 1; $n -le 154; $n++) { $sonnets[$n] = @{ N = $n; En = $null; Old = $null; Tr = New-Object System.Collections.ArrayList } }
$ranges = '1-20', '21-40', '41-60', '61-80', '81-100', '101-120', '121-140', '141-154'
function Range-Of([int]$n) { foreach ($r in $ranges) { $a, $b = $r -split '-'; if ($n -ge [int]$a -and $n -le [int]$b) { return "$r.htm" } } }

# Originals: <A name=N><H3>XVIII.</H3></A>, quatrains in <DT>, the couplet in <DD>.
foreach ($r in $ranges) {
  $t = Read-Src "sonnets/$r.htm"
  foreach ($m in [regex]::Matches($t, '(?is)<A\s+name="?(\d+)"?>\s*<H3>.*?</H3>\s*</A>(.*?)(?=<HR>|<A\s+name="?\d|</body>)')) {
    $n = [int]$m.Groups[1].Value
    $quat = @(); $coup = @()
    foreach ($l in [regex]::Matches($m.Groups[2].Value, '(?is)<(DT|DD)>(.*?)(?=<DT>|<DD>|</DD>|</DL>|$)')) {
      $line = Plain $l.Groups[2].Value
      if (-not $line) { continue }
      if ($l.Groups[1].Value -ieq 'DT') { $quat += $line } else { $coup += $line }
    }
    $st = @(@{ Lines = $quat; Indent = $false })
    if ($coup.Count) { $st += @{ Lines = $coup; Indent = $true } }
    $sonnets[$n].En = New-Poem $st
  }
}

function Add-Tr([int]$n, [string]$key, [string]$name, [string]$kind, $poem, [string]$credit) {
  [void]$sonnets[$n].Tr.Add(@{ Key = $key; Name = $name; Kind = $kind; Poem = $poem; Credit = $credit; Second = $false })
}

# Feldman's variations: var/sonN.htm (son902 is a second variation on 90), plus the dedication.
$feldman = New-Object System.Collections.ArrayList
$epiRx = '(?is)^(?:\s|&nbsp;|</?(?:p|br|div|center)\b[^>]*>)*(?:<i>\s*)?<font size=-1>(.*?)</font>(?:\s*</i>)?(?:\s*</div>)?'
foreach ($f in Get-ChildItem (Join-Path $Root 'var') -Filter 'son*.htm' -File) {
  if ($f.BaseName -notmatch '^son(\d+)$') { continue }
  $num = $Matches[1]
  $n = if ($num -eq '902') { 90 } else { [int]$num }
  $second = $num -eq '902'
  $t = Read-Src "var/$($f.Name)"
  $head = $t.IndexOf('Вариации на сонеты')
  $m = [regex]::Match($t.Substring($head), '(?is)<b>\s*(?:<(?:font|span)\b[^>]*>\s*)?(?:&nbsp;)*(\d+)(?:\(\d\))?\s*(?:</(?:font|span)>\s*)?</b>')
  if (-not $m.Success) { throw "number not found in $($f.Name)" }
  $from = $head + $m.Index + $m.Length
  $body = $t.Substring($from, $t.IndexOf('</td>', $from, [StringComparison]::OrdinalIgnoreCase) - $from)
  $epi = @()
  while (($e = [regex]::Match($body, $epiRx)).Success) {
    $line = Plain $e.Groups[1].Value
    if ($line) { $epi += $line }
    $body = $body.Substring($e.Length)
  }
  $p = Get-Poem $body
  $p.Epigraph = $epi
  $key = if ($second) { 'feldman-2' } else { 'feldman' }
  $credit = if ($second) { 'Вариация: <b>Яков Фельдман</b> · вторая вариация' } else { 'Вариация: <b>Яков Фельдман</b>' }
  Add-Tr $n $key 'Яков Фельдман' 'var' $p $credit
  if ($second) { $sonnets[$n].Tr[-1].Second = $true }
  [void]$feldman.Add(@{ N = $n; Second = $second; Poem = $p; Credit = $credit })
}
$feldman = @($feldman | Sort-Object { $_.N }, { $_.Second })
$posvHtml = Read-Src 'var/posv.htm'
$m = [regex]::Match($posvHtml, '(?is)ПОСВЯЩЕНИЕ</font></i></b>')
$from = $m.Index + $m.Length
$posv = Get-Poem $posvHtml.Substring($from, $posvHtml.IndexOf('</td>', $from, [StringComparison]::OrdinalIgnoreCase) - $from)

# Marshak and Finkel: <pre> text, sonnets separated by <a name=N></a>СОНЕТ N.
function Read-Pre([string]$file, [string]$key, [string]$name) {
  $t = Read-Src $file
  $pre = ([regex]::Matches($t, '(?is)<pre>(.*?)</pre>') | ForEach-Object { $_.Groups[1].Value }) -join "`n"
  $parts = [regex]::Split($pre, '(?i)<a name=(\d+)></a>')
  for ($i = 1; $i -lt $parts.Count; $i += 2) {
    $n = [int]$parts[$i]
    $text = [regex]::Replace($parts[$i + 1], '(?i)^\s*(?:</ul>)?\s*сонет\s+\d+\s*(?:</ul>)?', '')
    $p = Get-PrePoem $text
    Move-Notes $p
    Add-Tr $n $key $name 'tr' $p "Перевод: <b>$name</b>"
  }
}
Read-Pre 'sonnets/marshak.html' 'marshak' 'С. Маршак'
Read-Pre 'sonnets/finkel.htm' 'finkel' 'А. Финкель'

# Older translations (more.htm): translator per sonnet comes from the contents list.
$moreHtml = Read-Src 'sonnets/more.htm'
$oldTr = @{
  'Н. Гербеля' = 'Н. Гербель', 'gerbel'; 'М. Чайковского' = 'М. Чайковский', 'chaykovsky'; 'В. Брюсова' = 'В. Брюсов', 'bryusov'
  'В. Лихачева' = 'В. Лихачёв', 'likhachev'; 'К. Случевского' = 'К. Случевский', 'sluchevsky'; 'Б. Бера' = 'Б. Бер', 'ber'
  'Ф. Червинского' = 'Ф. Червинский', 'chervinsky'; 'И. Мамуны' = 'И. Мамуна', 'mamuna'
}
$moreBy = @{}
foreach ($m in [regex]::Matches($moreHtml, '(?is)<A HREF="#(\d{4})">.*?</A>\s*Перевод\s+(.*?)(?=<BR>|<A HREF="#|<HR)')) {
  $g = Plain $m.Groups[2].Value
  if (-not $oldTr.ContainsKey($g)) { throw "unknown translator in more.htm: '$g'" }
  $moreBy[[int]$m.Groups[1].Value] = $oldTr[$g]
}
$moreSource = 'Шекспир У. Сонеты. — М.: Летопись, 1996'
$moreBody = $moreHtml.Substring($moreHtml.IndexOf('<A NAME="0001">'))
$moreBody = $moreBody.Substring(0, $moreBody.IndexOf('<p><hr>'))
$parts = [regex]::Split($moreBody, '<A NAME="(\d{4})"></A>')
for ($i = 1; $i -lt $parts.Count; $i += 2) {
  $n = [int]$parts[$i]
  $p = Get-Poem $parts[$i + 1]
  Drop-Number $p $n
  Move-Notes $p
  $name, $key = $moreBy[$n]
  $sonnets[$n].Old = @{ Name = $name; Key = $key }
  Add-Tr $n $key $name 'tr' $p "Перевод: <b>$name</b> · $moreSource"
}

# Sonnet 66 in many translations (rPoets/Shakespeare.htm), collected on V. Zelenkov's site.
$r66 = Read-Src 'rPoets/Shakespeare.htm'
$start = $r66.IndexOf('<hr>', $r66.IndexOf('</table>'))
$end = $r66.IndexOf('Другие сайты')
$blocks = [regex]::Split($r66.Substring($start, $end - $start), '(?i)<hr>') | Where-Object { $_ -match '\p{IsCyrillic}' }
$extra66 = @()
foreach ($b in $blocks) {
  $nm = [regex]::Match($b, '(?is)<a name="(\w+)"></a>(.*?)<br>')
  if ($nm.Success) {
    $key = $nm.Groups[1].Value
    $name = (Plain ($nm.Groups[2].Value -replace '<[^>]+>', '')) -replace '\.(?=\p{Lu})', '. '
  } else {
    $key = 'pod'; $name = 'Подстрочный перевод'
  }
  $cut = [regex]::Match($b, '(?is)restful\s+death\s+I\s+cry</a>(?:\s|</?b>|<br>)*</p>')
  if (-not $cut.Success) { throw "66: header not found for $key" }
  $p = Get-Poem ($b.Substring($cut.Index + $cut.Length) -replace '<p><Я', '<p>Я')
  $last = $p.Stanzas[-1]
  if ($last.Lines.Count -eq 1 -and $last.Lines[0] -notmatch '\p{L}{2}') {
    $p.Date = $last.Lines[0]
    $p.Stanzas = @($p.Stanzas | Select-Object -SkipLast 1)
  }
  $extra66 += @{ Key = $key; Name = $name; Poem = $p }
}
$have = @{}
foreach ($t in $sonnets[66].Tr) { $have[(Norm (Poem-Text $t.Poem))] = $t }
foreach ($x in $extra66) {
  $norm = Norm (Poem-Text $x.Poem)
  $dup = $have.Keys | Where-Object { $_ -eq $norm -or $_.Contains($norm) } | Select-Object -First 1
  if ($dup) { continue }
  $kind = if ($x.Key -eq 'pod') { 'pod' } else { 'tr' }
  $credit = if ($kind -eq 'pod') { 'Подстрочный перевод' } else { "Перевод: <b>$($x.Name)</b>" }
  $key = $x.Key
  $same = $sonnets[66].Tr | Where-Object { $_.Name -eq $x.Name } | Select-Object -First 1
  if ($same) { $key = "$($same.Key)-2"; $credit += ' · другой вариант текста' }
  if ($x.Key -eq 'zel') { $credit += ' · <a href="https://web.archive.org/web/2002/http://libelli.narod.ru/">libelli.narod.ru</a> (архив)' }
  Add-Tr 66 $key $x.Name $kind $x.Poem $credit
  if ($same) { $sonnets[66].Tr[-1].Second = $true }
}

# Display order: the variation first, then Marshak, Finkel, the old translation, then the rest; "-2" right after its namesake.
for ($n = 1; $n -le 154; $n++) {
  $list = $sonnets[$n].Tr
  $ordered = New-Object System.Collections.ArrayList
  foreach ($t in @($list | Where-Object { -not $_.Second })) {
    [void]$ordered.Add($t)
    foreach ($s in @($list | Where-Object { $_.Second -and $_.Name -eq $t.Name })) { [void]$ordered.Add($s) }
  }
  if ($ordered.Count -ne $list.Count) { throw "sonnet ${n}: lost translations while ordering" }
  $sonnets[$n].Tr = $ordered
}

if ($Check) {
  for ($n = 1; $n -le 154; $n++) {
    $s = $sonnets[$n]
    $en = (Poem-Lines $s.En).Count
    $tr = ($s.Tr | ForEach-Object { "$($_.Key)=$((Poem-Lines $_.Poem).Count)" + $(if ($_.Poem.Notes.Count) { "+$($_.Poem.Notes.Count)n" }) }) -join ' '
    $odd = ($en -ne 14) -or ($s.Tr | Where-Object { $_.Kind -ne 'pod' -and (Poem-Lines $_.Poem).Count -ne 14 -and $_.Key -notmatch '^feldman' }) -or ($s.Tr | Where-Object { $_.Poem.Notes.Count })
    if ($odd -or $n -eq 66) { "{0,3}: en={1} {2}" -f $n, $en, $tr }
  }
  "feldman: $($feldman.Count) + posv $((Poem-Lines $posv).Count) lines; epigraphs: " + (($feldman | Where-Object { $_.Poem.Epigraph.Count } | ForEach-Object { $_.N }) -join ', ')
  $c1 = @(); for ($n = 1; $n -le 154; $n++) { foreach ($t in $sonnets[$n].Tr) { if ((Poem-Text $t.Poem) -match '[\u0080-\u009F]') { $c1 += "${n}:$($t.Key)" } } }
  "C1 left: $($c1 -join ' ')"
  foreach ($k in $ShowPoem) {
    $n, $key = $k -split ':'
    $t = $sonnets[[int]$n].Tr | Where-Object { $_.Key -eq $key }
    "----- $k"; $t.Poem.Stanzas | ForEach-Object { ($_.Lines -join "`n"); '' }; $t.Poem.Notes | ForEach-Object { "NOTE: $_" }; if ($t.Poem.Date) { "DATE: $($t.Poem.Date)" }
  }
  "66: " + (($sonnets[66].Tr | ForEach-Object { "$($_.Key):$($_.Name)" + $(if ($_.Poem.Date) { "[$($_.Poem.Date)]" }) }) -join '; ')
  return
}

# ---------- Rendering

$poetRu = 'Уильям Шекспир'
$poetEn = 'William Shakespeare'
$upIcon = '<a class="poem-up" href="#" aria-label="Наверх"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19V5M5 12l7-7 7 7"/></svg></a>'

function Stanza-Html([string[]]$lines) {
  $h = (($lines | ForEach-Object { Esc $_ }) -join "`n")
  $open = ([regex]::Matches($h, $emOn)).Count - ([regex]::Matches($h, $emOff)).Count
  if ($open -gt 0) { $h += $emOff * $open }
  $h.Replace($emOn, '<em>').Replace($emOff, '</em>')
}
function Verse-Html($p) {
  $out = @()
  if ($p.Epigraph.Count) { $out += '<p class="epigraph">' + (Stanza-Html $p.Epigraph) + '</p>' }
  foreach ($st in $p.Stanzas) {
    $cls = if ($st.Indent) { 'stanza indent' } else { 'stanza' }
    $out += "<p class=""$cls"">" + (Stanza-Html $st.Lines) + '</p>'
  }
  if ($p.Date) { $out += '<p class="date">' + (Esc $p.Date) + '</p>' }
  foreach ($note in $p.Notes) { $out += '<p class="note">' + (Esc $note) + '</p>' }
  $out -join "`n"
}
function Label-Of([string]$kind) { switch ($kind) { 'var' { 'Вариация' } 'pod' { 'Подстрочник' } default { 'Перевод' } } }
function Tr-Title($t) {
  if ($t.Kind -eq 'pod') { return 'Подстрочник' }
  if ($t.Second) { return "$($t.Name) (2)" }
  $t.Name
}

function Write-Page([string]$file, [string]$title, [string]$desc, [string]$old, [string]$body) {
  $html = @"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(Esc $title) — Жемчужины английской поэзии</title>
<meta name="description" content="$(Esc $desc)">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500&family=Inter:wght@400;500;600&family=Literata:opsz,wght@7..72,400;7..72,500&display=swap">
<link rel="stylesheet" href="pearls.css?v=$cssV">
</head>
<body>

<header class="site-header">
  <div class="wrap">
    <a class="brand" href="index.html"><span class="pearl" aria-hidden="true"></span><span>Жемчужины<small>английской поэзии</small></span></a>
    <nav class="nav" aria-label="Разделы">
      <a href="index.html">Поэты</a>
      <a href="catalog.html">Каталог</a>
      <a href="search.html">Поиск</a>
      <a href="articles.html">Статьи</a>
      <a href="gallery.html">Галерея</a>
      <a href="selection.html">Подборка</a>
      <a href="../ePoets/Shakespeare.htm">English</a>
    </nav>
    <div class="tools">
      <button class="chip" id="theme" type="button" title="Светлая / тёмная тема">◐</button>
      <a class="chip" href="$old">Старая версия</a>
    </div>
  </div>
</header>

$body

<footer class="site-footer">
  <div class="wrap">
    <span>© 1998–2026 Елена и Яков Фельдман · Жемчужины английской поэзии</span>
    <span><a href="index.html">Поэты</a> · <a href="Shakespeare.html">Уильям Шекспир</a> · <a href="sonnets.html">Сонеты</a> · <a href="catalog.html">Каталог</a> · <a href="articles.html">Статьи</a> · <a href="https://aromatic-keyboard-369.notion.site/22522db3cb0880f1a1fffd512d49ceba" target="_blank" rel="noopener">Об авторе</a></span>
  </div>
</footer>

<a class="to-top" href="#" aria-label="Наверх">↑</a>

<script src="pearls.js?v=$jsV"></script>
</body>
</html>
"@
  [IO.File]::WriteAllText((Join-Path $outDir $file), $html, $utf8)
}

$crumbs = '<a href="index.html">Поэты</a> · <a href="Shakespeare.html">Уильям Шекспир</a>'
$readerBar = @"
<div class="reader-bar" id="poems">
  <div class="wrap">
    <span>Как читать</span>
    <div class="segmented" role="group" aria-label="Режим чтения">
      <button type="button" data-mode="both" aria-pressed="true">Рядом</button>
      <button type="button" data-mode="ru" aria-pressed="false">{0}</button>
      <button type="button" data-mode="en" aria-pressed="false">{1}</button>
    </div>
  </div>
</div>
"@

# ---------- One page per sonnet

$written = 0
for ($n = 1; $n -le 154; $n++) {
  $s = $sonnets[$n]
  $first = First-Line $s.En
  $roman = Roman $n
  $vars = @($s.Tr | Where-Object { $_.Kind -eq 'var' }).Count
  $trs = @($s.Tr | Where-Object { $_.Kind -eq 'tr' }).Count
  $meta = @('Оригинал')
  if ($vars -eq 1) { $meta += 'вариация Якова Фельдмана' } elseif ($vars) { $meta += "$vars вариации Якова Фельдмана" }
  $meta += Plural $trs 'перевод' 'перевода' 'переводов'
  if ($s.Tr | Where-Object { $_.Kind -eq 'pod' }) { $meta += 'подстрочник' }
  $chips = ($s.Tr | ForEach-Object { "<li><a href=""#$($_.Key)"">$(Esc (Tr-Title $_))</a></li>" }) -join "`n      "
  $source = ''
  if ($n -eq 66) {
    $source = "`n    <p class=""son-source"">Большинство переводов собрано на сайте В. Зеленкова (minsk.isir.by/~zelenkov), которого больше нет в сети.</p>"
  }
  $articles = New-Object System.Text.StringBuilder
  foreach ($t in $s.Tr) {
    $h2 = Esc (Tr-Title $t)
    if ($t.Second) { $h2 = (Esc $t.Name) + '<span class="tr-note">' + $(if ($t.Kind -eq 'var') { 'вторая вариация' } else { 'другой вариант' }) + '</span>' }
    [void]$articles.Append(@"

      <article class="poem sonnet-tr" id="$($t.Key)" data-title="Сонет $n" data-en-title="$(Esc $first)" data-en="original">
        <header class="poem-head"><h2>$h2</h2></header>
        <div class="col col-ru">
          <p class="label">$(Label-Of $t.Kind)</p>
          <div class="verse">
$(Verse-Html $t.Poem)
          </div>
          <p class="credit">$($t.Credit)</p>
        </div>
      </article>
"@)
  }
  $pager = @()
  if ($n -gt 1) { $pager += "<a class=""prev"" href=""sonnet-$($n - 1).html""><small>← Предыдущий</small><span>Сонет $($n - 1)</span></a>" }
  if ($n -lt 154) { $pager += "<a class=""next"" href=""sonnet-$($n + 1).html""><small>Следующий →</small><span>Сонет $($n + 1)</span></a>" }
  $body = @"
<section class="section first son-head">
  <div class="wrap">
    <header class="art-head wide">
      <p class="eyebrow">$crumbs · <a href="sonnets.html">Сонеты</a></p>
      <h1>Сонет $n</h1>
      <p class="alt">$(Esc $first)</p>
      <p class="meta">$(Esc ($meta -join ' · '))</p>
    </header>
    <nav class="series-nav wide" aria-label="Переводы">
      <p>На этой странице</p>
      <ol>
      $chips
      </ol>
    </nav>$source
  </div>
</section>

$($readerBar -f 'Переводы', 'Оригинал')

<main data-mode="both" class="sonnet" data-poet-ru="$poetRu" data-poet-en="$poetEn">
  <div class="wrap sonnet-grid">
    <article class="poem sonnet-orig" id="original" data-title="Сонет $n" data-en-title="$(Esc $first)">
      <header class="poem-head"><h2 lang="en">Sonnet $roman</h2></header>
      <div class="col col-en" lang="en">
        <p class="label">Оригинал</p>
        <div class="verse">
$(Verse-Html $s.En)
        </div>
      </div>
    </article>
    <div class="sonnet-trs">$($articles.ToString())
    </div>
  </div>
</main>

<section class="section">
  <div class="wrap">
    <nav class="essay-pager" aria-label="Сонеты">
      $($pager -join "`n      ")
    </nav>
  </div>
</section>
"@
  $desc = "Сонет $n Шекспира ($first): оригинал и переводы — " + (($s.Tr | Where-Object { $_.Kind -ne 'pod' -and -not $_.Second } | ForEach-Object { $_.Name }) -join ', ') + '.'
  Write-Page "sonnet-$n.html" "Сонет $n — Уильям Шекспир" $desc "../sonnets/$(Range-Of $n)#$n" $body
  $written++
}

# ---------- Collections: one translator (or the original) for all sonnets

function Render-Item([string]$id, [string]$title, [string]$enTitle, $en, $ru, [string]$label, [string]$credit, [string]$link, [bool]$isFirst) {
  $up = if ($isFirst) { '' } else { $upIcon }
  $single = if ($en -and $ru) { '' } else { ' single' }
  $other = if ($link) { "`n          <p class=""credit other""><a href=""$link"">Все переводы сонета →</a></p>" } else { '' }
  $enCol = ''
  $ruCol = ''
  if ($en) {
    $enOther = if ($ru) { '' } else { $other }
    $enCol = @"

        <div class="col col-en" lang="en">
          <p class="label">Оригинал</p>
          <div class="verse">
$(Verse-Html $en)
          </div>$enOther
        </div>
"@
  }
  if ($ru) {
    $cr = if ($credit) { "`n          <p class=""credit"">$credit</p>" } else { '' }
    $ruCol = @"

        <div class="col col-ru">
          <p class="label">$label</p>
          <div class="verse">
$(Verse-Html $ru)
          </div>$cr$other
        </div>
"@
  }
  $enT = if ($enTitle) { "`n        <p class=""en-title"">$(Esc $enTitle)</p>" } else { '' }
  @"

  <article class="poem" id="$id">
    <div class="wrap">
      <header class="poem-head">
        <h2>$(Esc $title)$up</h2>$enT
      </header>
      <div class="parallel$single">$enCol$ruCol
      </div>
    </div>
  </article>
"@
}

function Write-Collection([string]$file, [string]$h1, [string]$alt, [string]$meta, [string]$old, [string]$search, [string]$desc, $items, [string[]]$modes) {
  $nums = ($items | Where-Object { $_.Num } | ForEach-Object { "<a href=""#$($_.Id)"">$($_.Num)</a>" }) -join ' '
  $sb = New-Object System.Text.StringBuilder
  $i = 0
  foreach ($it in $items) {
    [void]$sb.Append((Render-Item $it.Id $it.Title $it.EnTitle $it.En $it.Ru $it.Label $it.Credit $it.Link ($i -eq 0)))
    $i++
  }
  $bar = if ($modes) { "`n" + ($readerBar -f $modes[0], $modes[1]) + "`n" } else { '' }
  $searchRu, $searchEn = $search -split '\|'
  $noOrig = if ($items | Where-Object { $_.Ru }) { ' data-search-original="0"' } else { '' }
  $body = @"
<section class="section first">
  <div class="wrap">
    <header class="art-head wide">
      <p class="eyebrow">$crumbs · <a href="sonnets.html">Сонеты</a></p>
      <h1>$(Esc $h1)</h1>
      <p class="alt">$(Esc $alt)</p>
      <p class="meta">$meta</p>
    </header>
    <nav class="son-nums" aria-label="Номера сонетов">$nums</nav>
  </div>
</section>
$bar
<main data-mode="both" data-poet-ru="$poetRu" data-poet-en="$poetEn" data-search-ru="$(Esc $searchRu)" data-search-en="$(Esc $searchEn)"$noOrig>$($sb.ToString())
</main>

<section class="section">
  <div class="wrap">
    <nav class="essay-pager" aria-label="Сонеты">
      <a class="prev" href="sonnets.html"><small>← Все сонеты</small><span>Сонеты Шекспира</span></a>
    </nav>
  </div>
</section>
"@
  Write-Page $file $h1 $desc $old $body
}

function Sonnet-Item([int]$n, $t) {
  @{ Id = "s$n"; Num = "$n"; Title = "Сонет $n"; EnTitle = (First-Line $sonnets[$n].En); En = $sonnets[$n].En; Ru = $t.Poem; Label = (Label-Of $t.Kind); Credit = $t.Credit; Link = "sonnet-$n.html" }
}

$items = @(@{ Id = 'posv'; Num = $null; Title = 'Посвящение'; EnTitle = $null; En = $null; Ru = $posv; Label = 'Стихотворение'; Credit = '<b>Яков Фельдман</b>'; Link = $null })
foreach ($f in $feldman) {
  $t = $sonnets[$f.N].Tr | Where-Object { $_.Kind -eq 'var' -and $_.Second -eq $f.Second }
  $it = Sonnet-Item $f.N $t
  if ($f.Second) { $it.Id = "s$($f.N)-2"; $it.Num = "$($f.N)²"; $it.Title = "Сонет $($f.N) · вторая вариация" }
  $items += $it
}
Write-Collection 'sonnets-feldman.html' 'Вариации на сонеты Шекспира' 'Яков Фельдман' (Esc "$(Plural $feldman.Count 'вариация' 'вариации' 'вариаций') и посвящение · рядом с оригиналом") '../var/cont.htm' "Яков Фельдман · вариации на сонеты Шекспира|Jacob Feldman · Variations on Shakespeare's Sonnets" "Вариации Якова Фельдмана на сонеты Шекспира — $($feldman.Count) стихотворений рядом с оригиналом." $items @('Вариации', 'Оригинал')

foreach ($c in @(
    @{ Key = 'marshak'; File = 'sonnets-marshak.html'; H1 = 'Сонеты в переводе С. Маршака'; Alt = 'Самуил Яковлевич Маршак'; Old = '../sonnets/marshak.html'; Search = 'Уильям Шекспир · пер. С. Маршака|William Shakespeare · tr. S. Marshak' },
    @{ Key = 'finkel'; File = 'sonnets-finkel.html'; H1 = 'Сонеты в переводе А. Финкеля'; Alt = 'Александр Моисеевич Финкель'; Old = '../sonnets/finkel.htm'; Search = 'Уильям Шекспир · пер. А. Финкеля|William Shakespeare · tr. A. Finkel' }
  )) {
  $items = @(for ($n = 1; $n -le 154; $n++) { Sonnet-Item $n ($sonnets[$n].Tr | Where-Object { $_.Key -eq $c.Key }) })
  Write-Collection $c.File $c.H1 $c.Alt '154 сонета · рядом с оригиналом' $c.Old $c.Search "$($c.H1): все 154 сонета Шекспира рядом с оригиналом." $items @('Перевод', 'Оригинал')
}

$items = @(for ($n = 1; $n -le 154; $n++) { Sonnet-Item $n ($sonnets[$n].Tr | Where-Object { $_.Key -eq $sonnets[$n].Old.Key -and -not $_.Second }) })
$oldNames = @($oldTr.Values | ForEach-Object { $_[0] } | Sort-Object { ($_ -split ' ')[-1] })
Write-Collection 'sonnets-classic.html' 'Сонеты в старых переводах' ($oldNames -join ', ') (Esc "154 сонета · рядом с оригиналом · источник: $moreSource") '../sonnets/more.htm' 'Уильям Шекспир · старые переводы|William Shakespeare · early Russian translations' "Сонеты Шекспира в переводах XIX — начала XX века: $($oldNames -join ', ')." $items @('Перевод', 'Оригинал')

$items = @(for ($n = 1; $n -le 154; $n++) { @{ Id = "s$n"; Num = "$n"; Title = "Сонет $n"; EnTitle = "Sonnet $(Roman $n)"; En = $sonnets[$n].En; Ru = $null; Label = $null; Credit = $null; Link = "sonnet-$n.html" } })
Write-Collection 'sonnets-original.html' 'The Sonnets' $poetEn '154 сонета · оригинальный текст' '../sonnets/1-20.htm' 'Уильям Шекспир · сонеты в оригинале|William Shakespeare · The Sonnets' 'The Sonnets of William Shakespeare: все 154 сонета в оригинале.' $items $null

# ---------- Hub

$grid = (1..154 | ForEach-Object {
    $v = if ($sonnets[$_].Tr | Where-Object { $_.Kind -eq 'var' }) { ' class="v"' } else { '' }
    "<li><a$v href=""sonnet-$_.html"" title=""$(Esc (First-Line $sonnets[$_].En))"">$_</a></li>"
  }) -join "`n      "
$toc = (1..154 | ForEach-Object {
    $m = $sonnets[$_].Tr | Where-Object { $_.Key -eq 'marshak' }
    "<li><a class=""ru"" href=""sonnet-$_.html"">$(Esc (First-Line $m.Poem))</a><span class=""en"">$(Esc (First-Line $sonnets[$_].En))</span></li>"
  }) -join "`n      "
$n66 = @($sonnets[66].Tr | Where-Object { $_.Kind -eq 'tr' }).Count
function Card([string]$href, [string]$title, [string]$sub) { "<li><a href=""$href""><b>$title</b><span>$sub</span></a></li>" }
$read = @(
  (Card 'sonnets-feldman.html' 'Вариации на сонеты Шекспира' "Яков Фельдман · $(Plural $feldman.Count 'вариация' 'вариации' 'вариаций') и посвящение")
  (Card 'sonnets-marshak.html' 'Перевод С. Маршака' '154 сонета · рядом с оригиналом')
  (Card 'sonnets-finkel.html' 'Перевод А. Финкеля' '154 сонета · рядом с оригиналом')
  (Card 'sonnets-classic.html' 'Старые переводы' (Esc ($oldNames -join ', ')))
  (Card 'sonnets-original.html' 'The Sonnets' 'Оригинальный текст · 154 сонета')
  (Card 'sonnet-66.html' "Сонет 66 в $n66 переводах" 'Tired with all this, for restful death I cry')
) -join "`n      "
$more = @(
  (Card 'Shakespeare.html' 'Уильям Шекспир' 'Страница поэта: песни, сонеты, монолог Гамлета')
  (Card 'st-shakespeare.html' 'Трагедии Шекспира и уровни его персонажей' 'Яков Фельдман · статья')
  (Card '../Lectures/Gasparov.htm' 'Сонеты Шекспира — переводы Маршака' 'М. Л. Гаспаров')
  (Card '../Lectures/plach.htm' 'Плач по Шекспиру' 'Т. А. Ладошкина')
) -join "`n      "
$sites = @(
  (Card 'https://web.archive.org/web/2002/http://www.aha.ru/~kozh/s/shakes.htm' 'Шекспир на русском' 'aha.ru/~kozh · архив')
  (Card 'https://web.archive.org/web/2013/http://www.aai.ee/~vladislav/poesia/rus/poets/Shakespeare.html' 'Стихи Шекспира в Коллекции Влада' 'aai.ee/~vladislav · архив')
  (Card 'https://web.archive.org/web/2000/http://kulichki.rambler.ru/vv/ovys/teatr/hamlet.html' 'Vysotsky v teatre. &quot;Hamlet&quot; — Shakespeare' 'Высоцкий играет Гамлета — фотографии, текст на английском, заметки о Шекспире · архив')
  (Card 'https://shakespeare.mit.edu/' 'The Complete Works of William Shakespeare' 'shakespeare.mit.edu')
  (Card 'https://web.archive.org/web/1997/http://www.ipl.org/reading/shakespeare/shakespeare.html' 'Shakespeare Bookshelf' "William Shakespeare's Complete Works · ipl.org · архив")
) -join "`n      "
$body = @"
<section class="section first">
  <div class="wrap">
    <header class="art-head wide">
      <p class="eyebrow">$crumbs</p>
      <h1>Сонеты Шекспира</h1>
      <p class="alt">The Sonnets of William Shakespeare</p>
      <p class="meta">154 сонета в оригинале · переводы С. Маршака и А. Финкеля · старые переводы · $(Plural $feldman.Count 'вариация' 'вариации' 'вариаций') Якова Фельдмана</p>
    </header>
    <div class="section-head sub">
      <h2>Все сонеты</h2>
      <p>На странице сонета — оригинал и все переводы</p>
    </div>
    <ol class="son-grid">
      $grid
    </ol>
    <p class="legend"><i></i>есть вариация Якова Фельдмана</p>
  </div>
</section>

<section class="section">
  <div class="wrap">
    <div class="section-head sub">
      <h2>Читать подряд</h2>
      <p>Один переводчик — все сонеты</p>
    </div>
    <ul class="art-other">
      $read
    </ul>
  </div>
</section>

<section class="section" id="contents">
  <div class="wrap">
    <div class="section-head">
      <h2>Содержание</h2>
      <p>Перевод С. Маршака · оригинал</p>
    </div>
    <ol class="toc">
      $toc
    </ol>
  </div>
</section>

<section class="section">
  <div class="wrap">
    <div class="section-head sub">
      <h2>Ещё о Шекспире</h2>
    </div>
    <ul class="art-other">
      $more
    </ul>
    <div class="section-head sub">
      <h2>Другие сайты</h2>
      <p>Ссылки 2002 года; где сайт закрылся — копия в веб-архиве</p>
    </div>
    <ul class="art-other">
      $sites
    </ul>
    <p class="legend">Не сохранились: William Shakespeare (surbis.ru/berry), сайт В. Зеленкова (minsk.isir.by/~zelenkov).</p>
  </div>
</section>
"@
Write-Page 'sonnets.html' 'Сонеты Шекспира' "Все 154 сонета Шекспира: оригинал, переводы С. Маршака, А. Финкеля, старые переводы, $($feldman.Count) вариаций Якова Фельдмана, сонет 66 в $n66 переводах." '../sonnets/all.htm' $body

"sonnets: $written pages + hub + 5 collections; translations: $((1..154 | ForEach-Object { $sonnets[$_].Tr.Count } | Measure-Object -Sum).Sum); Feldman: $($feldman.Count) + posv"
