param(
  [string]$Root = (Split-Path $PSScriptRoot -Parent),
  [string[]]$Only = @(),
  [string[]]$Skip = @('Milne')
)
$ErrorActionPreference = 'Stop'
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

$utf8 = New-Object System.Text.UTF8Encoding $false
$outDir = Join-Path $Root 'design'
$LB = [string][char]3
$PB = [string][char]4
$EO = [string][char]1
$EC = [string][char]2

function Esc([string]$s) { $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function Dec([string]$s) { [System.Net.WebUtility]::HtmlDecode($s) }
function Plain([string]$s) {
  $t = [regex]::Replace($s, '(?s)<[^>]+>', ' ')
  $t = Dec $t
  ([regex]::Replace($t, '[\s\u00A0]+', ' ')).Trim()
}
function Norm([string]$s) { [regex]::Replace($s.ToLowerInvariant(), '[^\p{L}\p{N}]', '') }

function Plural([int]$n, [string]$one, [string]$few, [string]$many) {
  $m10 = $n % 10; $m100 = $n % 100
  if ($m10 -eq 1 -and $m100 -ne 11) { return $one }
  if ($m10 -ge 2 -and $m10 -le 4 -and ($m100 -lt 12 -or $m100 -gt 14)) { return $few }
  return $many
}

function Roman([int]$n) {
  $map = @(@(10, 'X'), @(9, 'IX'), @(5, 'V'), @(4, 'IV'), @(1, 'I'))
  $r = ''
  foreach ($p in $map) { while ($n -ge $p[0]) { $r += $p[1]; $n -= $p[0] } }
  $r
}

function Get-AnchorRegex([string]$id) {
  '(?i)<a\s[^>]*\bname\s*=\s*["'']?' + [regex]::Escape($id) + '["'']?(?=[\s>/])[^>]*>'
}

function Get-Chunk([string]$html, [string]$id, [string[]]$stops) {
  $m = [regex]::Match($html, (Get-AnchorRegex $id))
  if (-not $m.Success) { return $null }
  $rest = $html.Substring($m.Index + $m.Length)
  $end = $rest.Length
  foreach ($pat in '(?i)<hr\b', '(?i)</body', '(?i)<!--\s*BEGIN WEBSIDESTORY', '(?i)<table[^>]*\bcols\s*=', '(?i)<div align="?center"?>\s*<center>') {
    $x = [regex]::Match($rest, $pat)
    if ($x.Success -and $x.Index -lt $end) { $end = $x.Index }
  }
  foreach ($a in [regex]::Matches($rest, '(?i)<a\s[^>]*\bname\s*=\s*["'']?([^"''\s>]+)')) {
    if ($a.Index -ge $end) { break }
    if ($stops -contains $a.Groups[1].Value -or $a.Groups[1].Value -match $script:serviceIds) { $end = $a.Index; break }
  }
  $rest.Substring(0, $end)
}

function Render-Line([string]$line, [ref]$inEm) {
  $sb = New-Object System.Text.StringBuilder
  if ($inEm.Value) { [void]$sb.Append('<em>') }
  foreach ($part in [regex]::Split($line, "([$EO$EC])")) {
    if ($part -eq $EO) { if (-not $inEm.Value) { [void]$sb.Append('<em>'); $inEm.Value = $true } }
    elseif ($part -eq $EC) { if ($inEm.Value) { [void]$sb.Append('</em>'); $inEm.Value = $false } }
    else { [void]$sb.Append((Esc $part)) }
  }
  if ($inEm.Value) { [void]$sb.Append('</em>') }
  $r = $sb.ToString() -replace '<em>(\s*)</em>', '$1'
  $r.Trim()
}

# Returns list of stanzas; each stanza is a list of @{ Html; Text }
function Get-Stanzas([string]$chunk) {
  $s = $chunk
  $close = [regex]::Match($s, '(?i)</pre\s*>')
  $open = [regex]::Match($s, '(?i)<pre\b')
  if ($close.Success -and (-not $open.Success -or $open.Index -gt $close.Index)) { $s = '<pre>' + $s }
  $s = [regex]::Replace($s, '(?s)<!--.*?-->', '')
  $s = [regex]::Replace($s, '(?is)<(script|style)\b.*?</\1>', '')
  $s = [regex]::Replace($s, '(?is)<pre\b[^>]*>(.*?)</pre>', { param($m) $PB + ($m.Groups[1].Value -replace '\r?\n', $LB) + $PB })
  $s = [regex]::Replace($s, '(?is)<a\s[^>]*href\s*=\s*["'']?[^"''>]*\.htm#[^>]*>.*?</a>', '')
  $s = [regex]::Replace($s, '(?is)<img\b[^>]*>', '')
  $s = $s -replace '[\r\n\t]+', ' '
  $s = [regex]::Replace($s, '(?i)<br\b[^>]*>', $LB)
  $s = [regex]::Replace($s, '(?i)</?(p|div|h[1-6]|dl|blockquote|table|tr|ul|ol|center|pre)\b[^>]*>', $PB)
  $s = [regex]::Replace($s, '(?i)</dt\s*>', '')
  $s = [regex]::Replace($s, '(?i)<dt\b[^>]*>', $LB)
  $s = [regex]::Replace($s, '(?i)</li\s*>', $LB)
  $s = [regex]::Replace($s, '(?i)</td\s*>', $PB)
  $s = [regex]::Replace($s, '(?i)</?dd\b[^>]*>', $PB)
  $s = [regex]::Replace($s, '(?i)<(i|em)\b[^>]*>', $EO)
  $s = [regex]::Replace($s, '(?i)</(i|em)\s*>', $EC)
  $s = [regex]::Replace($s, '(?s)<[^>]+>', '')
  $s = Dec $s
  $s = $s -replace '[ \u00A0]+', ' '
  $s = $s.Replace($PB, "$LB$LB")

  $stanzas = New-Object System.Collections.ArrayList
  $cur = New-Object System.Collections.ArrayList
  $inEm = $false
  foreach ($raw in $s.Split([char]3)) {
    $visible = ($raw -replace "[$EO$EC\s]", '')
    if ($visible -eq '') {
      foreach ($c in $raw.ToCharArray()) { if ([string]$c -eq $EO) { $inEm = $true } elseif ([string]$c -eq $EC) { $inEm = $false } }
      if ($cur.Count -gt 0) { [void]$stanzas.Add($cur); $cur = New-Object System.Collections.ArrayList }
      continue
    }
    $line = $raw.Trim()
    $html = Render-Line $line ([ref]$inEm)
    $text = (($line -replace "[$EO$EC]", '') -replace '\s+', ' ').Trim()
    [void]$cur.Add(@{ Html = $html; Text = $text })
  }
  if ($cur.Count -gt 0) { [void]$stanzas.Add($cur) }
  , $stanzas
}

function Get-Mode($stanzas, [int]$skipFirst) {
  $counts = @{}
  for ($i = $skipFirst; $i -lt $stanzas.Count; $i++) { $n = $stanzas[$i].Count; $counts[$n] = 1 + [int]$counts[$n] }
  if ($counts.Count -eq 0) { return -1 }
  ($counts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
}

$creditRx = '^\(?\s*(Перев[её]л[аи]?|Перевод(?:чик)?|Пер\.|Translated by|Translation by)\s*(:?)\s*(.*?)\s*\)?\s*$'

function Get-Credit([string]$text) {
  if ($text -notmatch $creditRx) { return $null }
  $verb = $Matches[1]; $colon = $Matches[2]; $name = $Matches[3].Trim().TrimEnd('.', ',', ';')
  if (-not $name -or $name.Length -gt 80) { return $null }
  if ($verb -like 'Перевод*' -and -not $colon) {
    return @{ Display = "Перевод <b>$(Esc $name)</b>"; Name = $null }
  }
  @{ Display = "Перевод: <b>$(Esc $name)</b>"; Name = $name }
}

function Remove-EmptyEdges($stanzas) {
  foreach ($pass in 'head', 'tail') {
    while ($stanzas.Count -gt 0) {
      $si = if ($pass -eq 'head') { 0 } else { $stanzas.Count - 1 }
      $st = $stanzas[$si]
      $idx = if ($pass -eq 'head') { 0 } else { $st.Count - 1 }
      if ($st.Count -gt 0 -and $st[$idx].Text -notmatch '[\p{L}\p{N}]') { $st.RemoveAt($idx) }
      elseif ($st.Count -eq 0) { $stanzas.RemoveAt($si) }
      else { break }
    }
  }
}

function Clean-Poem($stanzas, [string[]]$titles, [string]$ownTitle) {
  $result = @{ Stanzas = $stanzas; Subtitle = $null; Credits = @() }
  $tn = @($titles | Where-Object { $_ } | ForEach-Object { Norm $_ } | Where-Object { $_ })
  $own = Norm $ownTitle
  Remove-EmptyEdges $stanzas
  $total = 0; foreach ($st in $stanzas) { $total += $st.Count }
  if ($total -eq 1 -and $stanzas[0][0].Text.Length -lt 40) { $stanzas.Clear(); return $result }

  # translator credits near the end (credit line and anything after it)
  if ($stanzas.Count -gt 0) {
    $last = $stanzas[$stanzas.Count - 1]
    for ($k = [Math]::Max(0, $last.Count - 3); $k -lt $last.Count; $k++) {
      $c = Get-Credit $last[$k].Text
      if ($c) {
        $result.Credits += $c
        while ($last.Count -gt $k) { $last.RemoveAt($last.Count - 1) }
        if ($last.Count -eq 0) { $stanzas.RemoveAt($stanzas.Count - 1) }
        break
      }
    }
  }
  # bare translator name ("Д.Г.Орловская") as the last one-line stanza
  if ($stanzas.Count -gt 1) {
    $last = $stanzas[$stanzas.Count - 1]
    $nm = $last[0].Text.Trim()
    if ($last.Count -eq 1 -and $nm -cmatch '^(?:[А-ЯЁ]\.\s*){1,2}[А-ЯЁ][а-яё]+(?:-[А-ЯЁ][а-яё]+)?$') {
      $result.Credits += @{ Display = "Перевод: <b>$(Esc $nm)</b>"; Name = $nm }
      $stanzas.RemoveAt($stanzas.Count - 1)
    }
  }
  # credit at the very beginning
  if ($stanzas.Count -gt 1) {
    $c = Get-Credit $stanzas[0][0].Text
    if ($c) {
      $result.Credits += $c
      $stanzas[0].RemoveAt(0)
      if ($stanzas[0].Count -eq 0) { $stanzas.RemoveAt(0) }
    }
  }
  Remove-EmptyEdges $stanzas

  # leading titles
  $guard = 0
  while ($stanzas.Count -gt 0 -and $guard -lt 4) {
    $guard++
    $first = $stanzas[0]
    $ln = Norm $first[0].Text
    $isTitle = $false
    foreach ($t in $tn) {
      if ($ln -eq $t) { $isTitle = $true; break }
      if ($first.Count -eq 1 -and $ln.Length -ge 4 -and $t.Length -ge 4 -and ($ln.StartsWith($t) -or $t.StartsWith($ln))) { $isTitle = $true; break }
    }
    if ($isTitle) {
      if ($first.Count -eq 1) { $stanzas.RemoveAt(0); continue }
      $allTitles = $true
      foreach ($fl in $first) { if ($tn -notcontains (Norm $fl.Text)) { $allTitles = $false; break } }
      if ($allTitles -and $stanzas.Count -gt 1) { $stanzas.RemoveAt(0); continue }
      $mode = Get-Mode $stanzas 1
      if ($ln -eq $own -and $stanzas.Count -ge 3 -and ($first.Count - 1) -eq $mode) { $first.RemoveAt(0); continue }
      break
    }
    $c = Get-Credit $first[0].Text
    if ($c -and $stanzas.Count -gt 1) {
      $result.Credits += $c
      $first.RemoveAt(0)
      if ($first.Count -eq 0) { $stanzas.RemoveAt(0) }
      continue
    }
    if ($first.Count -eq 1 -and $stanzas.Count -gt 1 -and -not $result.Subtitle -and $first[0].Text.Length -le 70 -and $first[0].Text -notmatch '[.,;:!?…—–-]$') {
      $result.Subtitle = $first[0].Html
      $stanzas.RemoveAt(0)
      continue
    }
    break
  }
  $result
}

function Get-Region([string]$html) {
  $body = [regex]::Match($html, '(?i)<body\b')
  $start = if ($body.Success) { $body.Index } else { 0 }
  foreach ($a in [regex]::Matches($html, '(?i)<a\s[^>]*\bname\s*=\s*["'']?([^"''\s>]+)')) {
    if ($a.Index -lt $start) { continue }
    $id = $a.Groups[1].Value
    $before = $html.Substring(0, $a.Index)
    if ($before -match ('(?i)href\s*=\s*["'']?[^"''>#]*#' + [regex]::Escape($id) + '["''\s>]')) {
      return $html.Substring($start, $a.Index - $start)
    }
  }
  $hr = [regex]::Match($html.Substring($start), '(?i)<hr\b')
  $html.Substring($start)
}

function Get-TocEntries([string]$ruHtml, [string]$file) {
  $region = Get-Region $ruHtml
  $own = [regex]::Escape($file)
  $rowSplit = if ($region -match '(?i)<tr\b') { '(?i)<tr\b' } else { '(?i)<br\b[^>]*>|</p>|</li>|</dt>' }
  $rows = [regex]::Split($region, $rowSplit)
  $ru = New-Object System.Collections.ArrayList
  $en = New-Object System.Collections.ArrayList
  $bare = @{}
  $pos = 0
  for ($r = 0; $r -lt $rows.Count; $r++) {
    foreach ($m in [regex]::Matches($rows[$r], '(?is)<a\s[^>]*href\s*=\s*["'']?([^"''>\s]*)["'']?[^>]*>(.*?)</a>')) {
      $href = $m.Groups[1].Value
      $text = Plain $m.Groups[2].Value
      if (-not ($text -match '\p{L}')) { continue }
      $pos++
      if ($href -match "(?i)^(?:(?:\.\./Poets/)?$own)?#(.+)$" -or ($text -match '[\p{IsCyrillic}]' -and $href -match "(?i)ePoets/$own#(.+)$")) {
        [void]$ru.Add(@{ Id = $Matches[1]; Title = $text; Row = $r; Pos = $pos; Used = $false })
      } elseif ($text -notmatch '[\p{IsCyrillic}]' -and $href -match "(?i)(?:ePoets/$own|rPoets/[^/#]+\.htm|eEPoets/[^/#]+\.htm)#(.+)$") {
        [void]$en.Add(@{ Id = $Matches[1]; Title = $text; Row = $r; Pos = $pos; Used = $false })
      } elseif ($text -notmatch '[\p{IsCyrillic}]' -and $href -match "(?i)ePoets/$own$" -and -not $bare.ContainsKey($r)) {
        $bare[$r] = $text
      }
    }
  }
  $entries = New-Object System.Collections.ArrayList
  $seen = @{}
  foreach ($x in $ru) {
    if ($seen.ContainsKey($x.Id) -or $x.Id -match $script:serviceIds) { $x.Used = $true; continue }
    $seen[$x.Id] = $true
    $match = $en | Where-Object { -not $_.Used -and $_.Id -eq $x.Id } | Select-Object -First 1
    if (-not $match) { $match = $en | Where-Object { -not $_.Used -and $_.Row -eq $x.Row } | Select-Object -First 1 }
    if ($match) { $match.Used = $true }
    $x.Used = $true
    $enTitle = if ($match) { $match.Title } elseif ($bare.ContainsKey($x.Row)) { $bare[$x.Row] }
    if (-not $match -and $bare.ContainsKey($x.Row)) { $bare.Remove($x.Row) }
    [void]$entries.Add(@{ RuId = $x.Id; RuTitle = $x.Title; EnId = $(if ($match) { $match.Id }); EnTitle = $enTitle; Pos = $x.Pos })
  }
  $leftRu = @($entries | Where-Object { -not $_.EnId })
  $leftEn = @($en | Where-Object { -not $_.Used })
  for ($i = 0; $i -lt [Math]::Min($leftRu.Count, $leftEn.Count); $i++) {
    $leftRu[$i].EnId = $leftEn[$i].Id; $leftRu[$i].EnTitle = $leftEn[$i].Title; $leftEn[$i].Used = $true
  }
  foreach ($y in $en | Where-Object { -not $_.Used }) {
    [void]$entries.Add(@{ RuId = $null; RuTitle = $null; EnId = $y.Id; EnTitle = $y.Title; Pos = $y.Pos })
  }
  , @($entries | Sort-Object { $_.Pos })
}

function Get-Sections([string]$html) {
  $body = [regex]::Match($html, '(?i)<body\b').Index
  $hr = [regex]::Match($html.Substring($body), '(?i)<hr\b')
  if (-not $hr.Success) { return , @() }
  $rest = $html.Substring($body + $hr.Index)
  $footer = [regex]::Match($rest, '(?is)<table[^>]*cols\s*=\s*"?3|<!--\s*BEGIN WEBSIDESTORY|</body')
  if ($footer.Success) { $rest = $rest.Substring(0, $footer.Index) }
  $out = @()
  foreach ($sec in [regex]::Split($rest, '(?i)<hr\b[^>]*>')) {
    if ((Plain $sec).Length -lt 40) { continue }
    $heads = [regex]::Matches($sec, '(?is)<h3\b[^>]*>(.*?)</h3>')
    if ($heads.Count -ge 3) {
      for ($i = 0; $i -lt $heads.Count; $i++) {
        $from = $heads[$i].Index + $heads[$i].Length
        $to = if ($i + 1 -lt $heads.Count) { $heads[$i + 1].Index } else { $sec.Length }
        $t = Plain $heads[$i].Groups[1].Value
        $out += , @{ Html = $sec.Substring($from, $to - $from); Other = $null; Title = $t }
      }
      continue
    }
    $cross = [regex]::Match($sec, '(?is)<a\s[^>]*href\s*=\s*["'']?[^"''>]*(?:Poets|ePoets)/[^"''>]*["'']?[^>]*>(.*?)</a>')
    $other = if ($cross.Success) { Plain ([regex]::Split($cross.Groups[1].Value, '(?i)<br\b[^>]*>')[0]) } else { $null }
    $out += , @{ Html = $sec; Other = $other; Title = $null }
  }
  , $out
}

function Get-SectionEntries([string]$ruHtml, [string]$enHtml) {
  $ru = Get-Sections $ruHtml
  $en = Get-Sections $enHtml
  $titled = @($ru | Where-Object { $_.Title }).Count -ge 3
  if ($titled) {
    $entries = @()
    $i = 0
    foreach ($r in $ru | Where-Object { $_.Title }) {
      $i++
      $num = $r.Title -match '^\d+$'
      $match = $en | Where-Object { $_.Title -eq $r.Title } | Select-Object -First 1
      $entries += , @{
        RuId = "s$i"; EnId = "s$i"; Pos = $i
        RuTitle = $(if ($num) { "№ $($r.Title)" } else { $r.Title })
        EnTitle = $(if ($match) { if ($num) { "No. $($r.Title)" } else { $match.Title } })
        RuChunk = $r.Html; EnChunk = $(if ($match) { $match.Html })
      }
    }
    return , $entries
  }
  $entries = @()
  for ($i = 0; $i -lt [Math]::Max($ru.Count, $en.Count); $i++) {
    $e = @{ RuId = $null; EnId = $null; RuTitle = $null; EnTitle = $null; Pos = $i; RuChunk = $null; EnChunk = $null }
    if ($i -lt $ru.Count) {
      $st = Get-Stanzas $ru[$i].Html
      if ($st.Count -gt 0) { $e.RuTitle = $st[0][0].Text; $e.RuChunk = $ru[$i].Html }
      $e.EnTitle = $ru[$i].Other
    }
    if ($i -lt $en.Count) {
      $st = Get-Stanzas $en[$i].Html
      if ($st.Count -gt 0) { $e.EnChunk = $en[$i].Html; if (-not $e.EnTitle) { $e.EnTitle = $st[0][0].Text } }
      if (-not $e.RuTitle) { $e.RuTitle = $en[$i].Other }
    }
    $e.RuId = "s$($i + 1)"; $e.EnId = "s$($i + 1)"
    $entries += , $e
  }
  , $entries
}

$script:serviceIds = '(?i)^(bio|top|other|links?)$|site'
$script:nonPersons = @('balladeSc.htm', 'nurs_rhymes.htm')
$script:nameOverrides = @{
  cummings  = @{ En = 'E. E. Cummings' }
  Hughes    = @{ En = 'Ted Hughes' }
  Masefield = @{ En = 'John Masefield' }
  Pound     = @{ En = 'Ezra Pound' }
  Bacon     = @{ Ru = 'Фрэнсис Бэкон' }
  Rossetti2 = @{ Ru = 'Кристина Росетти. Песни-песенки' }
}

$poetFiles = @{}
Get-ChildItem (Join-Path $Root 'Poets') -Filter *.htm -File | ForEach-Object { $poetFiles[$_.Name.ToLowerInvariant()] = $_.BaseName }

function Map-Href([string]$h) {
  if ($h -match '^(?:\.\./Poets/)?([^/#:]+\.htm)$') {
    $k = $Matches[1].ToLowerInvariant()
    if ($poetFiles.ContainsKey($k)) { return "$($poetFiles[$k]).html" }
  }
  $null
}

function Clean-Rich([string]$s) {
  $s = [regex]::Replace($s, '(?s)<!--.*?-->', '')
  $s = [regex]::Replace($s, '(?is)<(script|style)\b.*?</\1>', '')
  $s = [regex]::Replace($s, '(?is)<img\b[^>]*>', '')
  $s = [regex]::Replace($s, '(?is)<a\s[^>]*\bname\s*=[^>]*>(.*?)</a>', '$1')
  $s = [regex]::Replace($s, '(?is)<a\s[^>]*href\s*=\s*["'']?([^"''>\s]*)["'']?[^>]*>(.*?)</a>', {
      param($m)
      $nh = Map-Href $m.Groups[1].Value
      if ($nh) { "<a href=""$nh"">$($m.Groups[2].Value)</a>" } else { $m.Groups[2].Value }
    })
  $s = [regex]::Replace($s, '(?is)<(/?)([a-z][a-z0-9]*)\b[^>]*>', {
      param($m)
      $n = $m.Groups[2].Value.ToLowerInvariant()
      if ($n -eq 'a') { return $m.Value }
      if ($n -eq 'br') { return '<br>' }
      if (@('p', 'i', 'em', 'b', 'strong', 'ul', 'ol', 'li', 'h3', 'h4') -contains $n) { return "<$($m.Groups[1].Value)$n>" }
      ' '
    })
  $s = $s -replace '&nbsp;', ' '
  $s = [regex]::Replace($s, '(?is)(<i>\s*)?Дополнительная информация.*?(?=<br>|</p>|$)', '')
  $s = [regex]::Replace($s, '[\r\n\t \u00A0]+', ' ')
  if ($s -notmatch '<(ul|ol|li)>') { $s = [regex]::Replace($s, '\s*(<br>\s*)+', '</p><p>') }
  $s = [regex]::Replace($s, '(\s*<br>\s*)+(?=</p>|$)', '')
  $s = $s.Trim()
  if ($s -and $s -notmatch '^<(p|ul|ol|h3|h4)>') { $s = "<p>$s" }
  if ($s -and $s -notmatch '</(p|ul|ol|h3|h4)>$') { $s = "$s</p>" }
  for ($k = 0; $k -lt 3; $k++) { $s = [regex]::Replace($s, '<(p|i|b|em|strong|li|h3|h4)>\s*</\1>', '') }
  $s = [regex]::Replace($s, '<p>\s*<p>', '<p>') -replace '</p>\s*</p>', '</p>'
  $s -replace '</p>\s*', "</p>`n      " -replace '<p>\s+', '<p>'
}

function Get-HeadHtml([string]$html) {
  $body = [regex]::Match($html, '(?i)<body\b').Index
  $rest = $html.Substring($body)
  $hr = [regex]::Match($rest, '(?i)<hr\b')
  if ($hr.Success) { $rest.Substring(0, $hr.Index) } else { $rest.Substring(0, [Math]::Min($rest.Length, 3000)) }
}

function Get-NameText([string]$html) {
  $body = [regex]::Match($html, '(?i)<body\b').Index
  $rest = $html.Substring($body)
  $end = [Math]::Min($rest.Length, 3000)
  foreach ($pat in '(?i)<hr\b', '(?i)PortSmall/', '(?i)<table\b') {
    $x = [regex]::Match($rest, $pat)
    if ($x.Success -and $x.Index -lt $end) { $end = $rest.LastIndexOf('<', $x.Index) }
  }
  $t = Plain ([regex]::Replace($rest.Substring(0, $end), '(?is)<a\s[^>]*>.*?</a>', ' '))
  ($t -replace '[<>]', ' ' -replace '\s+', ' ').Trim()
}

function Get-Header([string]$ruHtml, [string]$enHtml, [string]$file) {
  $h = @{ Ru = $null; En = $null; Years = $null; Born = 0; Died = 0; Portrait = $null; BioShort = $null; BioLong = $null }
  $fontRx = '(?is)<font[^>]*size\s*=\s*["'']?\+?4["'']?[^>]*>(.*?)</font>'
  $f = [regex]::Match((Get-HeadHtml $ruHtml), $fontRx)
  if ($f.Success) { $h.Ru = (Plain $f.Groups[1].Value).Trim(' ', ',', '.') }
  if ($h.Ru -and $h.Ru -notmatch '\p{IsCyrillic}') { $h.Ru = $null }
  $fe = [regex]::Match((Get-HeadHtml $enHtml), $fontRx)
  if ($fe.Success) { $h.En = ((Plain $fe.Groups[1].Value) -replace '\(.*$', '' -replace '[\d\s\-–—,.?]+$', '').Trim() }
  if ($h.En -and ($h.En -match '\p{IsCyrillic}' -or $h.En.Length -lt 3)) { $h.En = $null }

  $portrait = [regex]::Match($ruHtml, '(?i)PortSmall/([^"''\s>]+)')
  $headEnd = 0
  if ($portrait.Success) {
    $name = $portrait.Groups[1].Value
    $big = Join-Path $Root "PortPoet\$name"
    $h.Portrait = if (Test-Path -LiteralPath $big) { "../PortPoet/$name" } else { "../PortSmall/$name" }
    $p = [regex]::Match($ruHtml.Substring($portrait.Index), '(?i)</p>|</center>|</div>')
    $headEnd = if ($p.Success) { $portrait.Index + $p.Index + $p.Length } else { $portrait.Index }
  }
  $bodyIdx = [regex]::Match($ruHtml, '(?i)<body\b').Index
  $headText = Plain $ruHtml.Substring($bodyIdx, [Math]::Max(0, [Math]::Min($ruHtml.Length - $bodyIdx, [Math]::Max($headEnd - $bodyIdx, 1500))))
  $y = [regex]::Match($headText, '(\d{3,4})\s*(?:-|–|—)\s*(\d{2,4})')
  if ($y.Success) {
    $b = [int]$y.Groups[1].Value; $d = [int]$y.Groups[2].Value
    if ($d -lt 100) { $d = [int]([Math]::Floor($b / 100) * 100) + $d }
    $h.Born = $b; $h.Died = $d; $h.Years = "$b — $d"
  } else {
    $y1 = [regex]::Match($headText, '\b(1[5-9]\d\d)\b')
    if ($y1.Success) { $h.Born = [int]$y1.Groups[1].Value; $h.Years = "род. $($h.Born)" }
  }
  $firstHr = [regex]::Match($ruHtml.Substring($bodyIdx), '(?i)<hr\b')
  $nameText = Get-NameText $ruHtml
  if (-not $h.Ru) {
    $lead = ($nameText -split '\(')[0].Trim(' ', ',', '.')
    if ($lead -match '\p{IsCyrillic}') { $h.Ru = $lead }
  }
  if (-not $h.En) {
    $par = [regex]::Match($nameText, '\(([^()]*?)\s*,?\s*\d')
    if ($par.Success -and $par.Groups[1].Value -notmatch '\p{IsCyrillic}') { $h.En = $par.Groups[1].Value.Trim(' ', ',') }
  }
  if (-not $h.En) {
    $lead = ((Get-NameText $enHtml) -split '\(')[0] -replace '[\d\-–—]+', ''
    $lead = $lead.Trim(' ', ',', '.')
    if ($lead -and $lead -notmatch '\p{IsCyrillic}') { $h.En = $lead }
  }
  foreach ($k in 'Ru', 'En') {
    if ($h[$k] -and $h[$k] -cmatch '^[^\p{Ll}]+$') { $h[$k] = (Get-Culture).TextInfo.ToTitleCase($h[$k].ToLowerInvariant()) }
  }
  if ($script:nonPersons -contains $file) {
    foreach ($k in 'Ru', 'En') { if ($h[$k]) { $h[$k] = $h[$k].Substring(0, 1) + $h[$k].Substring(1).ToLower() } }
  }
  $base = [IO.Path]::GetFileNameWithoutExtension($file)
  if ($script:nameOverrides.ContainsKey($base)) {
    foreach ($kv in $script:nameOverrides[$base].GetEnumerator()) { $h[$kv.Key] = $kv.Value }
  }
  if ($headEnd -gt 0) {
    $rest = $ruHtml.Substring($headEnd)
    $end = $rest.Length
    foreach ($pat in '(?i)<hr\b', '(?i)<table\b', '(?i)<a\s[^>]*\bname\s*=') {
      $x = [regex]::Match($rest, $pat)
      if ($x.Success -and $x.Index -lt $end) { $end = $x.Index }
    }
    $short = Clean-Rich $rest.Substring(0, $end)
    if ((Plain $short).Length -ge 40) { $h.BioShort = $short }
  }
  $bio = Get-Chunk $ruHtml 'bio' @()
  if ($bio -and (Plain $bio).Length -ge 80) { $h.BioLong = Clean-Rich $bio }
  $h
}

function Render-Verse($poem, [string]$indent) {
  $sb = New-Object System.Text.StringBuilder
  if ($poem.Subtitle) { [void]$sb.AppendLine("<p class=""subtitle"">$($poem.Subtitle)</p>") }
  foreach ($st in $poem.Stanzas) {
    $lines = @($st | ForEach-Object { $_.Html })
    $mid = if ($st.Count -eq 1) { Get-Credit $st[0].Text }
    if ($mid) { [void]$sb.AppendLine("<p class=""credit mid"">$($mid.Display)</p>"); continue }
    [void]$sb.AppendLine('<p class="stanza">' + ($lines -join "`n") + '</p>')
  }
  $sb.ToString().TrimEnd()
}

function Render-Page($poet, $entries, [string]$file) {
  $base = [IO.Path]::GetFileNameWithoutExtension($file)
  $ruName = if ($poet.Ru) { $poet.Ru } else { $base }
  $enName = $poet.En
  $count = @($entries).Count
  $translators = @($entries | ForEach-Object { $_.Credits } | ForEach-Object { $_.Name } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | ForEach-Object { $_.Name })
  $century = if ($poet.Born -gt 0) { Roman ([int][Math]::Floor((($poet.Born + [Math]::Max($poet.Died, $poet.Born + 40)) / 2) / 100) + 1) } else { $null }

  $facts = @()
  if ($poet.Years) { $facts += $poet.Years }
  $facts += "$count $(Plural $count 'стихотворение' 'стихотворения' 'стихотворений')"
  if ($translators.Count -gt 0) { $facts += "Переводы: $(($translators | Select-Object -First 3) -join ', ')" }

  $bioSection = $poet.BioLong
  $lede = $null
  if ($poet.BioShort) {
    if ((Plain $poet.BioShort).Length -le 700 -and -not $bioSection) { $lede = $poet.BioShort }
    elseif (-not $bioSection) { $bioSection = $poet.BioShort }
    else { $bioSection = $poet.BioShort + "`n      " + $bioSection }
  }

  $sb = New-Object System.Text.StringBuilder
  $title = Esc $ruName
  $desc = Esc ("$ruName" + $(if ($poet.Years) { " ($($poet.Years -replace ' — ', '–'))" }) + ': стихи в оригинале и в переводах. Жемчужины английской поэзии.')
  [void]$sb.Append(@"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title — Жемчужины английской поэзии</title>
<meta name="description" content="$desc">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500&family=Inter:wght@400;500;600&family=Literata:opsz,wght@7..72,400;7..72,500&display=swap">
<link rel="stylesheet" href="pearls.css?v=4">
</head>
<body>

<header class="site-header">
  <div class="wrap">
    <a class="brand" href="index.html"><span class="pearl" aria-hidden="true"></span><span>Жемчужины<small>английской поэзии</small></span></a>
    <nav class="nav" aria-label="Разделы">
      <a href="index.html">Поэты</a>
      <a href="../RusCatalog.htm">Каталог</a>
      <a href="../Gallery/frsGallery.htm">Галерея</a>
      <a href="../ePoets/$file">English</a>
    </nav>
    <div class="tools">
      <button class="chip" id="theme" type="button" title="Светлая / тёмная тема">◐</button>
      <a class="chip" href="../Poets/$file">Старая версия</a>
    </div>
  </div>
</header>

<section class="hero">
  <div class="wrap$(if (-not $poet.Portrait) { ' no-portrait' })">

"@)
  if ($poet.Portrait) {
    [void]$sb.Append(@"
    <figure class="portrait poet">
      <img src="$($poet.Portrait)" alt="$title">
    </figure>

"@)
  }
  [void]$sb.Append(@"
    <div>
      <p class="eyebrow">Английская поэзия$(if ($century) { " · $century век" })</p>
      <h1>$title</h1>

"@)
  if ($enName) { [void]$sb.AppendLine("      <p class=""alt"">$(Esc $enName)</p>") }
  if ($lede) { [void]$sb.AppendLine("      <div class=""lede"">$lede</div>") }
  [void]$sb.AppendLine('      <ul class="facts">')
  foreach ($f in $facts) { [void]$sb.AppendLine("        <li>$(Esc $f)</li>") }
  [void]$sb.AppendLine('      </ul>')
  [void]$sb.AppendLine('      <div class="actions">')
  [void]$sb.AppendLine('        <a class="btn primary" href="#poems">Читать стихи</a>')
  if ($bioSection) { [void]$sb.AppendLine('        <a class="btn ghost" href="#bio">Биография</a>') }
  [void]$sb.Append(@"
      </div>
    </div>
  </div>
</section>

<section class="section" id="contents">
  <div class="wrap">
    <div class="section-head">
      <h2>Содержание</h2>
      <p>Перевод · оригинал</p>
    </div>
    <ol class="toc">

"@)
  foreach ($e in $entries) {
    $ruT = if ($e.RuTitle) { Esc $e.RuTitle } else { '' }
    $enT = if ($e.EnTitle) { Esc $e.EnTitle } else { '' }
    $label = if ($ruT) { $ruT } else { $enT }
    [void]$sb.AppendLine("      <li><a class=""ru"" href=""#$($e.Slug)"">$label</a><span class=""en"">$(if ($ruT) { $enT })</span></li>")
  }
  [void]$sb.Append(@"
    </ol>
  </div>
</section>

<div class="reader-bar" id="poems">
  <div class="wrap">
    <span>Как читать</span>
    <div class="segmented" role="group" aria-label="Режим чтения">
      <button type="button" data-mode="both" aria-pressed="true">Рядом</button>
      <button type="button" data-mode="ru" aria-pressed="false">Русский</button>
      <button type="button" data-mode="en" aria-pressed="false">English</button>
    </div>
  </div>
</div>

<main data-mode="both">

"@)
  foreach ($e in $entries) {
    $h2 = if ($e.RuTitle) { Esc $e.RuTitle } else { Esc $e.EnTitle }
    $single = if (-not $e.En -or -not $e.Ru) { ' single' } else { '' }
    [void]$sb.Append(@"
  <article class="poem" id="$($e.Slug)">
    <div class="wrap">
      <header class="poem-head">
        <h2>$h2</h2>

"@)
    if ($e.RuTitle -and $e.EnTitle) { [void]$sb.AppendLine("        <p class=""en-title"">$(Esc $e.EnTitle)</p>") }
    [void]$sb.AppendLine('      </header>')
    [void]$sb.AppendLine("      <div class=""parallel$single"">")
    if ($e.En) {
      [void]$sb.AppendLine('        <div class="col col-en" lang="en">')
      [void]$sb.AppendLine('          <p class="label">Оригинал</p>')
      [void]$sb.AppendLine('          <div class="verse">')
      [void]$sb.AppendLine((Render-Verse $e.En))
      [void]$sb.AppendLine('          </div>')
      [void]$sb.AppendLine('        </div>')
    }
    if ($e.Ru) {
      [void]$sb.AppendLine('        <div class="col col-ru">')
      [void]$sb.AppendLine('          <p class="label">Перевод</p>')
      [void]$sb.AppendLine('          <div class="verse">')
      [void]$sb.AppendLine((Render-Verse $e.Ru))
      [void]$sb.AppendLine('          </div>')
      foreach ($c in $e.Ru.Credits) { [void]$sb.AppendLine("          <p class=""credit"">$($c.Display)</p>") }
      [void]$sb.AppendLine('        </div>')
    }
    [void]$sb.Append(@"
      </div>
    </div>
  </article>


"@)
  }
  [void]$sb.AppendLine('</main>')
  if ($bioSection) {
    [void]$sb.Append(@"

<section class="section" id="bio">
  <div class="wrap">
    <div class="bio-text">
      <div class="section-head"><h2>Биография</h2></div>
      $bioSection
    </div>
  </div>
</section>

"@)
  }
  [void]$sb.Append(@"

<footer class="site-footer">
  <div class="wrap">
    <span>© 1998–2026 Елена и Яков Фельдман · Жемчужины английской поэзии</span>
    <span><a href="index.html">Поэты</a> · <a href="../RusCatalog.htm">Каталог</a> · <a href="../Gallery/frsGallery.htm">Галерея</a></span>
  </div>
</footer>

<a class="to-top" href="#" aria-label="Наверх">↑</a>

<script src="pearls.js"></script>
</body>
</html>

"@)
  $sb.ToString()
}

$report = New-Object System.Collections.ArrayList
$index = New-Object System.Collections.ArrayList

foreach ($ruFile in Get-ChildItem (Join-Path $Root 'Poets') -Filter *.htm -File | Sort-Object Name) {
  $file = $ruFile.Name
  $base = $ruFile.BaseName
  $enPath = Join-Path $Root "ePoets\$file"
  if (-not (Test-Path -LiteralPath $enPath)) { continue }
  if ($Only.Count -gt 0 -and $Only -notcontains $base) { continue }

  $ruHtml = [IO.File]::ReadAllText($ruFile.FullName, $utf8)
  $enHtml = [IO.File]::ReadAllText($enPath, $utf8)
  $poet = Get-Header $ruHtml $enHtml $file
  $entries = Get-TocEntries $ruHtml $file
  if ($entries.Count -eq 0) { $entries = Get-SectionEntries $ruHtml $enHtml }

  if ($Skip -contains $base) {
    [void]$index.Add(@{ Base = $base; Ru = $poet.Ru; En = $poet.En; Years = $poet.Years; Count = $entries.Count })
    continue
  }

  $fromSections = ($entries.Count -gt 0 -and $entries[0].ContainsKey('RuChunk'))
  foreach ($attempt in 1, 2) {
  if ($attempt -eq 2) {
    if ($fromSections) { break }
    $entries = Get-SectionEntries $ruHtml $enHtml
    $fromSections = $true
  }
  $ruStops = @($entries | Where-Object { $_.RuId } | ForEach-Object { $_.RuId }) + @('bio', 'othersites')
  $enStops = @($entries | Where-Object { $_.EnId } | ForEach-Object { $_.EnId }) + @('bio', 'othersites')
  $enSources = @($enHtml)
  $extra = [regex]::Matches($ruHtml + $enHtml, '(?i)(rPoets|eEPoets)/([^"''#/\s>]+\.htm)') | ForEach-Object { "$($_.Groups[1].Value)\$($_.Groups[2].Value)" } | Sort-Object -Unique
  foreach ($x in $extra) {
    $xp = Join-Path $Root $x
    if (Test-Path -LiteralPath $xp) { $enSources += [IO.File]::ReadAllText($xp, $utf8) }
  }
  if (-not $fromSections) {
    $enRegion = Get-Region $enHtml
    $tocEnd = $enHtml.IndexOf($enRegion) + $enRegion.Length
    if ($tocEnd -lt $enRegion.Length) { $tocEnd = 0 }
    $ownRx = [regex]::Escape($file)
    $usedEn = @($entries | Where-Object { $_.EnId } | ForEach-Object { $_.EnId })
    foreach ($e in $entries) {
      if (-not $e.RuId) { continue }
      $bls = [regex]::Matches($enHtml, "(?i)<a\b[^>]*href\s*=\s*[`"']?\.\./Poets/$ownRx#$([regex]::Escape($e.RuId))[`"'\s>]")
      if ($bls.Count -eq 0) { continue }
      $bl = $bls[$bls.Count - 1]
      $p = $bl.Index
      if ($p -lt $tocEnd -and $bls.Count -lt 2) { continue }
      $after = $enHtml.Substring($p + $bl.Length)
      $hrAt = [regex]::Match($after, '(?i)<hr\b')
      if ($hrAt.Success) { $after = $after.Substring(0, $hrAt.Index) }
      if ([regex]::Matches($after, '(?i)<a\s[^>]*href').Count -ge 3) { continue }
      $useIt = -not $e.EnId
      if ($useIt) {
        $w0 = [Math]::Max(0, $p - 300)
        $win = $enHtml.Substring($w0, [Math]::Min($enHtml.Length - $w0, $p - $w0 + $bl.Length + 300))
        foreach ($nm in [regex]::Matches($win, '(?i)\bname\s*=\s*["'']?([^"''\s>]+)')) {
          if ($usedEn -contains $nm.Groups[1].Value) { $useIt = $false; break }
        }
      }
      if ($e.EnId) {
        $am = [regex]::Match($enHtml, (Get-AnchorRegex $e.EnId))
        if ($am.Success -and $am.Index -gt $p -and ($am.Index - $p) -lt 6000) {
          $between = $enHtml.Substring($p + $bl.Length, $am.Index - $p - $bl.Length)
          $useIt = $between -notmatch '(?i)<hr\b|\bname\s*='
          $tail = $between -replace '(?is)^.*?</a\s*>', ''
          if ((Plain $tail) -match '[\p{IsCyrillic}]') { $useIt = $false }
        }
      }
      if (-not $useIt) { continue }
      $syn = "bl-$($e.RuId)"
      $enHtml = $enHtml.Insert($p, "<a name=""$syn""></a>")
      $enSources[0] = $enHtml
      if ($e.EnId) { $enStops = @($enStops | Where-Object { $_ -ne $e.EnId }) }
      $enStops += $syn
      $e.EnId = $syn
    }
  }
  $slugs = @{}
  $issues = @()
  foreach ($e in $entries) {
    $slug = if ($e.RuId) { $e.RuId } else { $e.EnId }
    $slug = [regex]::Replace($slug, '[^A-Za-z0-9_-]', '')
    if (-not $slug -or $slug -match '^\d') { $slug = "p$slug" }
    while ($slugs.ContainsKey($slug)) { $slug += 'x' }
    $slugs[$slug] = $true
    $e.Slug = $slug
    $titles = @($e.RuTitle, $e.EnTitle)
    $e.Ru = $null; $e.En = $null; $e.Credits = @()
    if ($e.ContainsKey('RuChunk')) {
      foreach ($side in 'Ru', 'En') {
        $c = $e["${side}Chunk"]
        if (-not $c) { continue }
        $own = if ($side -eq 'Ru') { $e.RuTitle } else { $e.EnTitle }
        $p = Clean-Poem (Get-Stanzas $c) $titles $own
        if ($p.Stanzas.Count -gt 0) { $e[$side] = $p; if ($side -eq 'Ru') { $e.Credits = $p.Credits } }
      }
      continue
    }
    if ($e.RuId) {
      $chunk = Get-Chunk $ruHtml $e.RuId $ruStops
      if ($chunk) {
        $p = Clean-Poem (Get-Stanzas $chunk) $titles $e.RuTitle
        if ($p.Stanzas.Count -gt 0) { $e.Ru = $p; $e.Credits = $p.Credits } else { $issues += "ru-empty:$($e.RuId)" }
      } else { $issues += "ru-missing:$($e.RuId)" }
    }
    if ($e.EnId) {
      $chunk = $null
      foreach ($src in $enSources) { $chunk = Get-Chunk $src $e.EnId $enStops; if ($chunk) { break } }
      if ($chunk) {
        $p = Clean-Poem (Get-Stanzas $chunk) $titles $e.EnTitle
        if ($p.Stanzas.Count -gt 0) { $e.En = $p } else { $issues += "en-empty:$($e.EnId)" }
      } else { $issues += "en-missing:$($e.EnId)" }
    }
  }
  $entries = @($entries | Where-Object { $_.Ru -or $_.En })
  if ($entries.Count -gt 0) { break }
  }
  if ($entries.Count -eq 0) {
    [void]$report.Add([pscustomobject]@{ Poet = $base; Poems = 0; Issues = 'no poems'; Ru = $poet.Ru; En = $poet.En })
    continue
  }
  $page = Render-Page $poet $entries $file
  [IO.File]::WriteAllText((Join-Path $outDir "$base.html"), $page, $utf8)
  [void]$index.Add(@{ Base = $base; Ru = $poet.Ru; En = $poet.En; Years = $poet.Years; Count = $entries.Count })
  [void]$report.Add([pscustomobject]@{ Poet = $base; Poems = $entries.Count; Issues = ($issues -join ' '); Ru = $poet.Ru; En = $poet.En })
}

if ($Only.Count -eq 0) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append(@"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Поэты — Жемчужины английской поэзии</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500&family=Inter:wght@400;500;600&family=Literata:opsz,wght@7..72,400;7..72,500&display=swap">
<link rel="stylesheet" href="pearls.css?v=4">
</head>
<body>

<header class="site-header">
  <div class="wrap">
    <a class="brand" href="index.html"><span class="pearl" aria-hidden="true"></span><span>Жемчужины<small>английской поэзии</small></span></a>
    <nav class="nav" aria-label="Разделы">
      <a href="index.html">Поэты</a>
      <a href="../RusCatalog.htm">Каталог</a>
      <a href="../Gallery/frsGallery.htm">Галерея</a>
      <a href="../e_index.htm">English</a>
    </nav>
    <div class="tools">
      <button class="chip" id="theme" type="button" title="Светлая / тёмная тема">◐</button>
      <a class="chip" href="../index.htm">Старая версия</a>
    </div>
  </div>
</header>

<section class="section first">
  <div class="wrap">
    <div class="section-head">
      <h2>Поэты</h2>
      <p>$($index.Count) $(Plural $index.Count 'страница' 'страницы' 'страниц') · новый дизайн, черновик</p>
    </div>
    <ul class="poets">

"@)
  $surname = {
    $n = if ($_.Ru) { $_.Ru } else { $_.Base }
    $tokens = @((($n -split ',')[0] -split '[\s.]+') | Where-Object { $_ })
    $k = $tokens.Count - 1
    while ($k -gt 0 -and $tokens[$k] -cmatch '^[IVX]+$') { $k-- }
    if ($script:nonPersons -contains "$($_.Base).htm") { $n } else { $tokens[$k] + ' ' + $n }
  }
  foreach ($p in $index | Sort-Object $surname) {
    $ru = if ($p.Ru) { Esc $p.Ru } else { Esc $p.Base }
    $meta = @()
    if ($p.Years) { $meta += $p.Years }
    $meta += "$($p.Count) $(Plural $p.Count 'стихотворение' 'стихотворения' 'стихотворений')"
    [void]$sb.AppendLine("      <li><a href=""$($p.Base).html""><b>$ru</b><span class=""en"">$(Esc $p.En)</span><span class=""meta"">$(Esc ($meta -join ' · '))</span></a></li>")
  }
  [void]$sb.Append(@"
    </ul>
  </div>
</section>

<footer class="site-footer">
  <div class="wrap">
    <span>© 1998–2026 Елена и Яков Фельдман · Жемчужины английской поэзии</span>
  </div>
</footer>

<script src="pearls.js"></script>
</body>
</html>

"@)
  [IO.File]::WriteAllText((Join-Path $outDir 'index.html'), $sb.ToString(), $utf8)
}

$report | Export-Csv -Path (Join-Path $env:TEMP 'design_build.csv') -NoTypeInformation -Encoding UTF8
"pages: $($report.Count); with issues: $(@($report | Where-Object { $_.Issues }).Count); poems: $(($report | Measure-Object Poems -Sum).Sum)"
