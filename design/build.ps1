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
  $first = $null
  foreach ($m in [regex]::Matches($html, (Get-AnchorRegex $id))) {
    $c = Get-ChunkAt $html ($m.Index + $m.Length) $stops
    if ($null -eq $first) { $first = $c }
    $vis = [regex]::Replace($c, '(?is)<a\s[^>]*href\s*=\s*["'']?[^"''>]*\.htm#[^>]*>.*?</a>', '')
    if (([regex]::Matches((Plain $vis), '\p{L}')).Count -ge 20) { return $c }
  }
  $first
}

function Get-ChunkAt([string]$html, [int]$start, [string[]]$stops) {
  $rest = $html.Substring($start)
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
  $s = [regex]::Replace($s, '(?is)<a\s[^>]*href\s*=\s*["'']?[^"''>]*Lectures/[^>]*>(.*?)</a>', '$1')
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

function Remove-CyrillicLead($poem) {
  if ($poem.Subtitle -and (Plain $poem.Subtitle) -match '\p{IsCyrillic}' -and (Plain $poem.Subtitle) -notmatch '[A-Za-z]') { $poem.Subtitle = $null }
  while ($poem.Stanzas.Count -gt 1) {
    $st = $poem.Stanzas[0]
    $cyr = $true
    foreach ($ln in $st) { if ($ln.Text -match '[A-Za-z]' -or $ln.Text -notmatch '\p{IsCyrillic}') { $cyr = $false; break } }
    if ($cyr -and $st.Count -le 3) { $poem.Stanzas.RemoveAt(0) } else { break }
  }
}

function Remove-LatinLead($poem) {
  while ($poem.Stanzas.Count -gt 1) {
    $st = $poem.Stanzas[0]
    if ($st.Count -gt 3) { break }
    $lat = $true
    foreach ($ln in $st) { if ($ln.Text -notmatch '[A-Za-z]{2}') { $lat = $false; break } }
    $words = ($st | ForEach-Object { $_.Text }) -join ' '
    if ($lat -and ($words -notmatch '\p{IsCyrillic}' -or ($st.Count -le 2 -and ($words -split '\s+').Count -le 8))) { $poem.Stanzas.RemoveAt(0) } else { break }
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
  if ($stanzas.Count -gt 0 -and $stanzas[0].Count -gt 2 -and $stanzas[0][0].Text -match '^\d{1,3}\.?$') { $stanzas[0].RemoveAt(0) }
  $guard = 0
  while ($stanzas.Count -gt 0 -and $guard -lt 3) {
    $guard++
    $t0 = $stanzas[0][0].Text
    $isHead = ($t0 -notmatch '[\p{L}\p{N}]') -or ($t0 -match '^\(\d{1,3}[a-zа-я]?\)\s*\S' -and $t0.Length -le 60 -and $t0 -notmatch '[,;]$')
    if (-not $isHead -or ($stanzas.Count -eq 1 -and $stanzas[0].Count -le 1)) { break }
    $stanzas[0].RemoveAt(0)
    if ($stanzas[0].Count -eq 0) { $stanzas.RemoveAt(0) }
  }

  # leading titles
  $guard = 0
  while ($stanzas.Count -gt 0 -and $guard -lt 4) {
    $guard++
    $first = $stanzas[0]
    $ln = Norm ($first[0].Text -replace '^\(\d{1,3}[a-zа-я]?\)\s*', '')
    $isTitle = $false
    foreach ($t in $tn) {
      if ($ln -eq $t) { $isTitle = $true; break }
      if ($first.Count -eq 1 -and $ln.Length -ge 4 -and $t.Length -ge 4 -and ($ln.StartsWith($t) -or $t.StartsWith($ln))) { $isTitle = $true; break }
    }
    if ($isTitle) {
      if ($first.Count -eq 1) { $stanzas.RemoveAt(0); continue }
      $allTitles = $true
      foreach ($fl in $first) { if ($fl.Text -match '\p{L}' -and $tn -notcontains (Norm $fl.Text)) { $allTitles = $false; break } }
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
  $last = $null
  for ($r = 0; $r -lt $rows.Count; $r++) {
    foreach ($m in [regex]::Matches($rows[$r], '(?is)<a\s[^>]*href\s*=\s*["'']?([^"''>\s]*)["'']?[^>]*>(.*?)</a>')) {
      $href = $m.Groups[1].Value
      $text = Plain $m.Groups[2].Value
      if (-not ($text -match '\p{L}')) { continue }
      $pos++
      if ($href -match "(?i)^(?:(?:\.\./Poets/)?$own)?#(.+)$" -or ($text -match '[\p{IsCyrillic}]' -and $href -match "(?i)ePoets/$own#(.+)$")) {
        $last = @{ Id = $Matches[1]; Title = $text; Row = $r; Pos = $pos; Used = $false; Other = $null }
        [void]$ru.Add($last)
      } elseif ($text -match '[\p{IsCyrillic}]' -and $href -match '(?i)(rPoets/[^/#"]+\.htm(?:#.*)?)$') {
        if ($last -and $last.Row -eq $r -and -not $last.Other) { $last.Other = '../' + $Matches[1] }
      } elseif ($text -notmatch '[\p{IsCyrillic}]' -and $href -match "(?i)(?:ePoets/$own|rPoets/[^/#]+\.htm|eEPoets/[^/#]+\.htm)#(.+)$") {
        $last = @{ Id = $Matches[1]; Title = $text; Row = $r; Pos = $pos; Used = $false; Other = $null }
        [void]$en.Add($last)
      } elseif ($text -notmatch '[\p{IsCyrillic}]' -and $href -match "(?i)ePoets/$own$" -and -not $bare.ContainsKey($r)) {
        $bare[$r] = $text
      }
    }
  }
  $entries = New-Object System.Collections.ArrayList
  $seen = @{}
  foreach ($x in $ru) {
    if ($seen.ContainsKey($x.Id)) {
      $prev = $seen[$x.Id]
      if ($prev -is [hashtable] -and $x.Title -match '\p{IsCyrillic}' -and $prev.RuTitle -notmatch '\p{IsCyrillic}') {
        if (-not $prev.EnTitle) { $prev.EnTitle = $prev.RuTitle }
        $prev.RuTitle = $x.Title
      }
      $x.Used = $true; continue
    }
    if ($x.Id -match $script:serviceIds) { $x.Used = $true; continue }
    $seen[$x.Id] = $true
    $match = $en | Where-Object { -not $_.Used -and $_.Id -eq $x.Id } | Select-Object -First 1
    if (-not $match) { $match = $en | Where-Object { -not $_.Used -and $_.Row -eq $x.Row } | Select-Object -First 1 }
    if ($match) { $match.Used = $true }
    $x.Used = $true
    $enTitle = if ($match) { $match.Title } elseif ($bare.ContainsKey($x.Row)) { $bare[$x.Row] }
    if (-not $match -and $bare.ContainsKey($x.Row)) { $bare.Remove($x.Row) }
    $oth = if ($x.Other) { $x.Other } elseif ($match) { $match.Other }
    $entry = @{ RuId = $x.Id; RuTitle = $x.Title; EnId = $(if ($match) { $match.Id }); EnTitle = $enTitle; Pos = $x.Pos; Other = $oth }
    $seen[$x.Id] = $entry
    [void]$entries.Add($entry)
  }
  $leftRu = @($entries | Where-Object { -not $_.EnId })
  $leftEn = @($en | Where-Object { -not $_.Used -and -not $seen.ContainsKey($_.Id) -and -not [regex]::IsMatch($ruHtml, (Get-AnchorRegex $_.Id)) })
  for ($i = 0; $i -lt [Math]::Min($leftRu.Count, $leftEn.Count); $i++) {
    $leftRu[$i].EnId = $leftEn[$i].Id; $leftRu[$i].EnTitle = $leftEn[$i].Title; $leftEn[$i].Used = $true
  }
  foreach ($y in $en | Where-Object { -not $_.Used }) {
    [void]$entries.Add(@{ RuId = $null; RuTitle = $null; EnId = $y.Id; EnTitle = $y.Title; Pos = $y.Pos; Other = $y.Other })
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

function Get-NumberedHeadings([string]$html) {
  $map = @{}
  $anchors = @([regex]::Matches($html, '(?i)<a\s[^>]*\bname\s*=\s*["'']?([^"''\s>]+)'))
  $heads = @()
  foreach ($m in [regex]::Matches($html, '\((\d{1,2})\)')) {
    $after = $html.Substring($m.Index + $m.Length, [Math]::Min(12, $html.Length - $m.Index - $m.Length))
    if ($after -notmatch '^\s*(<|$)') { continue }
    $w0 = [Math]::Max(0, $m.Index - 200)
    $before = $html.Substring($w0, $m.Index - $w0)
    $bm = [regex]::Matches($before, '(?i)<br\b|<p\b|</p>|<h\d|</h\d>|<div\b|</div>')
    $cut = if ($bm.Count) { $bm[$bm.Count - 1].Index } else { 0 }
    $lineText = Plain $before.Substring($cut)
    if ($lineText -notmatch '\p{Lu}' -or $lineText.Length -gt 60) { continue }
    $start = $w0 + $cut
    $prefix = ''
    foreach ($a in $anchors) {
      if ($a.Index -gt $m.Index) { break }
      $prefix = $a.Groups[1].Value
    }
    $prefix = if ($prefix -match '^exp') { 'x' } else { ($prefix -replace '\d+$', '') }
    $heads += , @{ Key = "$prefix$($m.Groups[1].Value)"; Start = $start; BodyAt = $m.Index + $m.Length }
  }
  for ($i = 0; $i -lt $heads.Count; $i++) {
    $end = if ($i + 1 -lt $heads.Count) { $heads[$i + 1].Start } else { $html.Length }
    $body = $html.Substring($heads[$i].BodyAt, [Math]::Max(0, $end - $heads[$i].BodyAt))
    $hr = [regex]::Match($body, '(?i)<hr\b|<!--\s*BEGIN WEBSIDESTORY|<table[^>]*\bcols\s*=')
    if ($hr.Success) { $body = $body.Substring(0, $hr.Index) }
    if (-not $map.ContainsKey($heads[$i].Key)) { $map[$heads[$i].Key] = $body }
  }
  $map
}

function Get-AltTranslation($e, [string]$ruHtml) {
  $cands = @()
  if ($e.Other) { $cands += $e.Other }
  foreach ($m in [regex]::Matches($ruHtml, '(?i)rPoets/([^"''#/\s>]+\.htm)')) { $cands += "../rPoets/$($m.Groups[1].Value)" }
  $tried = @{}
  foreach ($href in $cands) {
    $fileRel = ($href -replace '^\.\./', '') -replace '#.*$', ''
    $anchor = if ($href -match '#(.+)$') { $Matches[1] } else { $null }
    if ($tried.ContainsKey($href)) { continue }
    $tried[$href] = $true
    $path = Join-Path $Root ($fileRel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $html = [IO.File]::ReadAllText($path, $utf8)
    $vis = [regex]::Replace($html, '(?s)<[^>]+>', '')
    if (([regex]::Matches($vis, '\p{IsCyrillic}')).Count -le ([regex]::Matches($vis, '[A-Za-z]')).Count) { continue }
    $chunk = $null
    if ($anchor) { $chunk = Get-Chunk $html $anchor @() }
    if (-not $chunk) {
      $nums = Get-NumberedHeadings $html
      foreach ($k in @($e.EnId, $e.RuId)) { if ($k -and $nums.ContainsKey($k)) { $chunk = $nums[$k]; break } }
    }
    if (-not $chunk -and $href -eq $e.Other) {
      $ids = @([regex]::Matches($html, '(?i)<a\s[^>]*\bname\s*=\s*["'']?([^"''\s>]+)') | ForEach-Object { $_.Groups[1].Value })
      $stops = $ids
      foreach ($id in $ids) { $c = Get-Chunk $html $id $stops; if ($c -and ([regex]::Matches((Plain $c), '\p{IsCyrillic}')).Count -ge 80) { $chunk = $c; break } }
    }
    if (-not $chunk) { continue }
    $st = Get-Stanzas $chunk
    $credit = $null
    if ($st.Count -gt 1 -and $st[0].Count -le 2 -and $st[0][0].Text -cmatch '^(?:[А-ЯЁ]\.\s*){1,2}[А-ЯЁ][а-яё]+(?:-[А-ЯЁ][а-яё]+)?$') {
      $nm = $st[0][0].Text
      $credit = @{ Display = "Перевод: <b>$(Esc $nm)</b>"; Name = $nm }
      $st.RemoveAt(0)
    }
    $p = Clean-Poem $st @($e.RuTitle, $e.EnTitle) $e.RuTitle
    Remove-LatinLead $p
    if ($p.Stanzas.Count -eq 0) { continue }
    if ($credit) { $p.Credits = @($credit) + @($p.Credits) }
    if (@($p.Credits).Count -eq 0) {
      $fc = [regex]::Match((Plain ([regex]::Match($html, '(?is)<body.*?<a\s[^>]*\bname\s*=').Value)), 'Перевод\s+([А-ЯЁ][а-яё]+\s+[А-ЯЁ][а-яё]+)')
      if ($fc.Success) { $p.Credits = @(@{ Display = "Перевод <b>$(Esc $fc.Groups[1].Value)</b>"; Name = $fc.Groups[1].Value }) }
    }
    return @{ Poem = $p; Href = $(if ($anchor) { $href } else { "../$fileRel" }) }
  }
  $null
}

function Get-NumberedBlocks([string]$html) {
  $map = @{}
  if (-not $html) { return $map }
  $pieces = [regex]::Split($html, '_{8,}')
  if ($pieces.Count -lt 3) { return $map }
  foreach ($pc in $pieces) {
    $m = [regex]::Match($pc, '(?:^|>)\s*(\d{1,3})\s*<br[^>]*>')
    if (-not $m.Success) { continue }
    $body = $pc.Substring($m.Index + $m.Length)
    $hr = [regex]::Match($body, '(?i)<hr\b')
    if ($hr.Success) { $body = $body.Substring(0, $hr.Index) }
    if (-not $map.ContainsKey($m.Groups[1].Value)) { $map[$m.Groups[1].Value] = $body }
  }
  $map
}

function Get-SectionEntries([string]$ruHtml, [string]$enHtml) {
  $ru = Get-Sections $ruHtml
  $en = Get-Sections $enHtml
  $titled = @($ru | Where-Object { $_.Title }).Count -ge 3
  if ($titled) {
    $numbered = Get-NumberedBlocks $enHtml
    $entries = @()
    $i = 0
    foreach ($r in $ru | Where-Object { $_.Title }) {
      $i++
      $num = $r.Title -match '^\d+$'
      $match = $en | Where-Object { $_.Title -eq $r.Title } | Select-Object -First 1
      if (-not $match -and $num -and $numbered.ContainsKey($r.Title)) { $match = @{ Title = $r.Title; Html = $numbered[$r.Title] } }
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

$script:serviceIds = '(?i)^(bio|top|other|links?)$|site|(?-i)Other$|^other[A-Z]'
$script:skipEntries = @{ Joyce = @('artist', 'Ulysses') }
$script:enIdOverrides = @{ 'Chapman#moon' = 'muses'; 'Yeats#golosFaray' = 'golos' }
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
  $translators = @($entries | ForEach-Object { $_.Credits } | ForEach-Object { ($_.Name -split ',')[0].Trim() } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | ForEach-Object { $_.Name })
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
<link rel="stylesheet" href="pearls.css?v=8">
</head>
<body>

<header class="site-header">
  <div class="wrap">
    <a class="brand" href="index.html"><span class="pearl" aria-hidden="true"></span><span>Жемчужины<small>английской поэзии</small></span></a>
    <nav class="nav" aria-label="Разделы">
      <a href="index.html">Поэты</a>
      <a href="catalog.html">Каталог</a>
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
      if ($e.Other) { [void]$sb.AppendLine("          <p class=""credit other""><a href=""$(Esc $e.Other)"">Другие переводы →</a></p>") }
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
    <span><a href="index.html">Поэты</a> · <a href="catalog.html">Каталог</a> · <a href="../Gallery/frsGallery.htm">Галерея</a></span>
  </div>
</footer>

<a class="to-top" href="#" aria-label="Наверх">↑</a>

<script src="pearls.js?v=6"></script>
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
  if ($script:skipEntries.ContainsKey($base)) { $entries = @($entries | Where-Object { $script:skipEntries[$base] -notcontains $_.RuId }) }
  if ($entries.Count -eq 0) { $entries = Get-SectionEntries $ruHtml $enHtml }

  if ($Skip -contains $base) {
    [void]$index.Add(@{ Base = $base; Ru = $poet.Ru; En = $poet.En; Years = $poet.Years; Born = $poet.Born; Died = $poet.Died; Count = $entries.Count })
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
    if (Test-Path -LiteralPath $xp) {
      $xt = [IO.File]::ReadAllText($xp, $utf8)
      $xv = [regex]::Replace($xt, '(?s)<[^>]+>', '')
      if (([regex]::Matches($xv, '[A-Za-z]')).Count -gt ([regex]::Matches($xv, '\p{IsCyrillic}')).Count) { $enSources += $xt }
    }
  }
  $enStopsBase = $enStops
  if (-not $fromSections) {
    $usedRu = @($entries | Where-Object { $_.RuId } | ForEach-Object { $_.RuId })
    foreach ($e in $entries) {
      if ($e.RuId -or -not $e.EnId -or $usedRu -contains $e.EnId) { continue }
      if ([regex]::IsMatch($ruHtml, (Get-AnchorRegex $e.EnId))) {
        $e.RuId = $e.EnId; $usedRu += $e.EnId
        if ($ruStops -notcontains $e.EnId) { $ruStops += $e.EnId }
      }
    }
    foreach ($e in $entries) {
      $ov = $script:enIdOverrides["$base#$($e.RuId)"]
      if ($ov) { $e.EnId = $ov; if ($enStops -notcontains $ov) { $enStops += $ov }; continue }
      if (-not $e.RuId -or $e.EnId) { continue }
      if ([regex]::IsMatch($enHtml, (Get-AnchorRegex $e.RuId))) { $e.EnId = $e.RuId; if ($enStops -notcontains $e.RuId) { $enStops += $e.RuId } }
    }
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
      $before = $enHtml.Substring(0, $p)
      $inCell = $before.LastIndexOf('<td', [StringComparison]::OrdinalIgnoreCase) -gt $before.LastIndexOf('</td', [StringComparison]::OrdinalIgnoreCase)
      if ($inCell -and $bls.Count -lt 2) { continue }
      $after = $enHtml.Substring($p + $bl.Length)
      $hrAt = [regex]::Match($after, '(?i)<hr\b')
      if ($hrAt.Success) { $after = $after.Substring(0, $hrAt.Index) }
      if ([regex]::Matches($after, '(?i)<a\s[^>]*href').Count -ge 3) { continue }
      if ($e.EnId) {
        $exists = $false
        foreach ($src in $enSources) { if ([regex]::IsMatch($src, (Get-AnchorRegex $e.EnId))) { $exists = $true; break } }
        if (-not $exists) { $e.EnId = $null }
      }
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
  $usedEnIds = @($entries | Where-Object { $_.EnId } | ForEach-Object { $_.EnId })
  foreach ($e in $entries) {
    if (-not $e.EnId -or -not $e.EnTitle -or $e.EnId -like 'bl-*' -or $e.ContainsKey('RuChunk')) { continue }
    $want = Norm $e.EnTitle
    if ($want.Length -lt 8) { continue }
    $ok = $null; $alt = $null
    foreach ($src in $enSources) {
      $anc = @([regex]::Matches($src, '(?i)<a\s[^>]*\bname\s*=\s*["'']?([^"''\s>]+)["'']?[^>]*>'))
      for ($i = 0; $i -lt $anc.Count; $i++) {
        $from = $anc[$i].Index + $anc[$i].Length
        $to = if ($i + 1 -lt $anc.Count) { [Math]::Min($anc[$i + 1].Index, $from + 400) } else { [Math]::Min($src.Length, $from + 400) }
        $hit = (Norm (Plain $src.Substring($from, $to - $from))).Contains($want)
        $nm = $anc[$i].Groups[1].Value
        if ($nm -eq $e.EnId) { if ($hit) { $ok = $true } elseif ($null -eq $ok) { $ok = $false } }
        elseif ($hit -and -not $alt -and $usedEnIds -notcontains $nm) { $alt = $nm }
      }
    }
    if ($ok -eq $false -and $alt) {
      $e.EnId = $alt; $usedEnIds += $alt
      if ($enStops -notcontains $alt) { $enStops += $alt }
    }
  }
  $ruAnchors = @([regex]::Matches($ruHtml, '(?i)<a\s[^>]*\bname\s*=\s*["'']?([^"''\s>]+)["'']?[^>]*>'))
  foreach ($e in $entries) {
    if (-not $e.RuId -or -not $e.EnTitle -or $e.ContainsKey('RuChunk')) { continue }
    $cnt = @($ruAnchors | Where-Object { $_.Groups[1].Value -eq $e.RuId }).Count
    if ($cnt -eq 1) { continue }
    $want = Norm $e.EnTitle
    if ($want.Length -lt 4) { continue }
    for ($i = 0; $i -lt $ruAnchors.Count; $i++) {
      $a = $ruAnchors[$i]
      $from = $a.Index + $a.Length
      $to = if ($i + 1 -lt $ruAnchors.Count) { [Math]::Min($ruAnchors[$i + 1].Index, $from + 600) } else { [Math]::Min($ruHtml.Length, $from + 600) }
      if ((Norm (Plain $ruHtml.Substring($from, $to - $from))).Contains($want)) {
        $e.RuAt = $from
        if ($ruStops -notcontains $a.Groups[1].Value) { $ruStops += $a.Groups[1].Value }
        break
      }
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
        if ($side -eq 'Ru') { Remove-LatinLead $p } else { Remove-CyrillicLead $p }
        if ($p.Stanzas.Count -gt 0) { $e[$side] = $p; if ($side -eq 'Ru') { $e.Credits = $p.Credits } }
      }
      continue
    }
    if ($e.RuId) {
      $chunk = if ($e.RuAt) { Get-ChunkAt $ruHtml $e.RuAt $ruStops } else { Get-Chunk $ruHtml $e.RuId $ruStops }
      if ($chunk -and -not $e.EnTitle) {
        $lk = [regex]::Match($chunk, "(?is)<a\s[^>]*href\s*=\s*[`"']?[^`"'>]*ePoets/$([regex]::Escape($file))#[^>]*>(.*?)</a>")
        if ($lk.Success) {
          $lt = Plain ([regex]::Split($lk.Groups[1].Value, '(?i)<br\b[^>]*>')[0])
          if ($lt -and $lt -notmatch '[\p{IsCyrillic}]') { $e.EnTitle = $lt; $titles = @($e.RuTitle, $e.EnTitle) }
        }
      }
      if ($chunk -and -not $e.RuTitle) {
        $st0 = Get-Stanzas $chunk
        $cand = @($st0 | Select-Object -First 2 | Where-Object { $_.Count -le 2 } | ForEach-Object { $_ } | Where-Object { $_.Text -match '\p{IsCyrillic}' -and $_.Text -notmatch '[A-Za-z]' -and $_.Text -notmatch '[,;]$' } | Select-Object -First 1)
        if ($cand.Count -gt 0) { $e.RuTitle = $cand[0].Text -replace '^\(\d{1,3}[a-zа-я]?\)\s*', ''; $titles = @($e.RuTitle, $e.EnTitle) }
      }
      if ($chunk) {
        $p = Clean-Poem (Get-Stanzas $chunk) $titles $e.RuTitle
        if (@($p.Credits).Count -gt 0 -and -not (@($p.Credits) | Where-Object { $_.Display -match 'Фельдман' })) {
          $endAt = $ruHtml.IndexOf($chunk) + $chunk.Length
          $hr = [regex]::Match($ruHtml.Substring($endAt), '^\s*<hr\b[^>]*>')
          if ($endAt -ge $chunk.Length -and $hr.Success) {
            $next = Get-ChunkAt $ruHtml ($endAt + $hr.Length) $ruStops
            if ($next -notmatch '(?i)<a\s[^>]*\bname\s*=' -and ([regex]::Matches((Plain $next), '\p{IsCyrillic}')).Count -ge 80) {
              $p2 = Clean-Poem (Get-Stanzas $next) $titles $e.RuTitle
              if ($p2.Stanzas.Count -gt 0 -and @($p2.Credits).Count -eq 0) { $p = $p2 }
            }
          }
        }
        Remove-LatinLead $p
        if ($p.Stanzas.Count -gt 0) { $e.Ru = $p; $e.Credits = $p.Credits } else { $issues += "ru-empty:$($e.RuId)" }
      } else { $issues += "ru-missing:$($e.RuId)" }
    }
    if ($e.EnId) {
      $chunk = $null
      foreach ($src in $enSources) { $chunk = Get-Chunk $src $e.EnId $enStops; if ($chunk) { break } }
      if ($chunk) {
        $p = Clean-Poem (Get-Stanzas $chunk) $titles $e.EnTitle
        if ($p.Stanzas.Count -eq 0) {
          foreach ($src in $enSources) { $c2 = Get-Chunk $src $e.EnId $enStopsBase; if ($c2) { $p = Clean-Poem (Get-Stanzas $c2) $titles $e.EnTitle; break } }
        }
        Remove-CyrillicLead $p
        $all = ($p.Stanzas | ForEach-Object { $_ | ForEach-Object { $_.Text } }) -join ' '
        if (([regex]::Matches($all, '\p{IsCyrillic}')).Count -gt ([regex]::Matches($all, '[A-Za-z]')).Count) { $p.Stanzas.Clear() }
        if ($p.Stanzas.Count -gt 0) { $e.En = $p } else { $issues += "en-empty:$($e.EnId)" }
      } else { $issues += "en-missing:$($e.EnId)" }
    }
  }
  foreach ($e in $entries) {
    if (-not $e.En -or $e.Ru) { continue }
    $alt = Get-AltTranslation $e $ruHtml
    if ($alt) {
      $e.Ru = $alt.Poem; $e.Credits = $alt.Poem.Credits; $e.Other = $alt.Href
      if (-not $e.RuTitle) {
        $h = [regex]::Match($alt.Poem.Subtitle + '', '\p{IsCyrillic}')
        if ($alt.Poem.Subtitle -and $h.Success) { $e.RuTitle = Plain $alt.Poem.Subtitle; $alt.Poem.Subtitle = $null }
      }
    }
  }
  if (-not $fromSections -and $entries.Count -eq 1 -and $entries[0].En -and -not $entries[0].Ru -and -not [regex]::IsMatch($ruHtml, '(?i)<a\s[^>]*\bname\s*=')) {
    $best = $null; $bestLen = 0
    foreach ($sec in Get-Sections $ruHtml) {
      $len = ([regex]::Matches((Plain $sec.Html), '\p{IsCyrillic}')).Count
      if ($len -gt $bestLen) { $best = $sec; $bestLen = $len }
    }
    if ($best -and $bestLen -ge 80) {
      $e = $entries[0]
      $st0 = Get-Stanzas $best.Html
      $cand = @($st0 | Select-Object -First 2 | Where-Object { $_.Count -le 2 } | ForEach-Object { $_ } | Where-Object { $_.Text -match '\p{IsCyrillic}' -and $_.Text -notmatch '[A-Za-z]' -and $_.Text -notmatch '[,;]$' } | Select-Object -First 1)
      if ($cand.Count -gt 0) { $e.RuTitle = $cand[0].Text }
      $p = Clean-Poem $st0 @($e.RuTitle, $e.EnTitle) $e.RuTitle
      Remove-LatinLead $p
      if ($p.Stanzas.Count -gt 0) { $e.Ru = $p; $e.Credits = $p.Credits }
    }
  }
  $entries = @($entries | Where-Object { $_.Ru -or $_.En })
  $enText = @{}
  foreach ($e in $entries) { if ($e.En -and $e.Ru) { $enText[$e.Slug] = (($e.En.Stanzas | ForEach-Object { $_ | ForEach-Object { $_.Text } }) -join "`n") } }
  $entries = @($entries | Where-Object {
    if ($_.Ru -or -not $_.En) { return $true }
    $probe = @($_.En.Stanzas | ForEach-Object { $_ | ForEach-Object { $_.Text } } | Where-Object { $_.Length -gt 15 } | Select-Object -First 3)
    if ($probe.Count -eq 0) { return $true }
    foreach ($t in $enText.Values) { $hit = $true; foreach ($l in $probe) { if (-not $t.Contains($l)) { $hit = $false; break } }; if ($hit) { return $false } }
    $true
  })
  if ($entries.Count -gt 0) { break }
  }
  if ($entries.Count -eq 0) {
    [void]$report.Add([pscustomobject]@{ Poet = $base; Poems = 0; Issues = 'no poems'; Ru = $poet.Ru; En = $poet.En })
    continue
  }
  $page = Render-Page $poet $entries $file
  [IO.File]::WriteAllText((Join-Path $outDir "$base.html"), $page, $utf8)
  [void]$index.Add(@{ Base = $base; Ru = $poet.Ru; En = $poet.En; Years = $poet.Years; Born = $poet.Born; Died = $poet.Died; Count = $entries.Count })
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
<link rel="stylesheet" href="pearls.css?v=8">
</head>
<body>

<header class="site-header">
  <div class="wrap">
    <a class="brand" href="index.html"><span class="pearl" aria-hidden="true"></span><span>Жемчужины<small>английской поэзии</small></span></a>
    <nav class="nav" aria-label="Разделы">
      <a href="index.html">Поэты</a>
      <a href="catalog.html">Каталог</a>
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

<script src="pearls.js?v=6"></script>
</body>
</html>

"@)
  [IO.File]::WriteAllText((Join-Path $outDir 'index.html'), $sb.ToString(), $utf8)
  $json = @($index | ForEach-Object { [pscustomobject]@{ Base = $_.Base; Ru = $_.Ru; En = $_.En; Years = $_.Years; Born = [int]$_.Born; Died = [int]$_.Died; Count = $_.Count } }) | ConvertTo-Json -Depth 3
  [IO.File]::WriteAllText((Join-Path $outDir 'poets.json'), $json, $utf8)
  & (Join-Path $PSScriptRoot 'build-catalog.ps1') -Root $Root
}

$report | Export-Csv -Path (Join-Path $env:TEMP 'design_build.csv') -NoTypeInformation -Encoding UTF8
"pages: $($report.Count); with issues: $(@($report | Where-Object { $_.Issues }).Count); poems: $(($report | Measure-Object Poems -Sum).Sum)"
