param([string]$Dir = (Join-Path $PSScriptRoot 'portraits'))
$ErrorActionPreference = 'Stop'
$dash = [string][char]0x2013
$files = [ordered]@{
  Barnes = 'William_Barnes_poet.jpg'; Beddoes = 'Thomas_Lovell_Beddoes_1.jpg'; Benson = 'Stella_Benson.jpg'; Bowles = 'William_Lisle_Bowles.jpg'
  Bradford = 'GamalielBradfordc.1930.jpg'; Brown = 'T._E._Brown_(young).jpg'; BrowneW = 'Portrait_of_Sir_William_Browne_Wellcome_L0007077.jpg'
  Butler = 'Samuel_Butler_by_Charles_Gogin.jpg'; Clough = 'Arthur_Hugh_Clough_1860.jpg'; Collins = 'WilliamCollinsPoet.jpg'; Colum = 'PadraicColum.jpeg'
  Cory = 'William_Johnson_Cory.jpg'; Davies = 'William_Henry_Davies.jpg'; Finch = 'Anne-Finch.jpeg'
  Guiterman = 'Arthur_Guiterman.jpg'; Herrick = 'Robert_Herrick_(poet)_(cropped).jpg'; Hope = 'A._D._Hope_bust,_Garema_Place.jpg'; King = 'Dr_Henry_King,_Bp_of_Chichester.jpg'
  Levy = 'Amy_Levy_1.jpg'; Lockhart = "Francis_Grant_(1803-1878)_-_John_Gibson_Lockhart_(1794$($dash)1854),_Son-in-Law_and_Biographer_of_Scott_-_PG_1588_-_National_Galleries_of_Scotland.jpg"
  Meredith = 'Robert_Bulwer-Lytton_by_Nadar.jpg'; Milne = 'Milne-Shadowland-1922.jpg'; Morley = 'Christopher_Darlington_Morley_cph.3b14371.jpg'
  Patmore = 'Portrait_of_Coventry_Patmore.jpg'; Sorley = 'Charles_Hamilton_Sorley_(For_Remembrance)_cropped_and_retouched.jpg'; Stoddard = 'Portrait_of_Richard_Henry_Stoddard.jpg'
  ThompsonF = 'Francis_Thompson_at_19.jpg'; ThomsonVB = 'James_Thomson_(B._V.),_photo_portrait,_1860.jpg'; Wolfe = 'Charles_Wolfe.jpg'; Wotton = 'SirHenryWotton.jpg'
}
$ua = @{ 'User-Agent' = 'PoetryPearlsPortraitBot/1.0 (jfeldman777@gmail.com)' }
New-Item -ItemType Directory -Force $Dir | Out-Null
$credits = [ordered]@{}
foreach ($k in $files.Keys) {
  $f = $files[$k]
  $iu = 'https://commons.wikimedia.org/w/api.php?action=query&format=json&prop=imageinfo&iiprop=url|extmetadata&iiurlwidth=500&titles=' + [uri]::EscapeDataString("File:$f")
  $ir = Invoke-RestMethod -Uri $iu -Headers $ua
  $ip = $ir.query.pages.PSObject.Properties | Select-Object -First 1 | ForEach-Object { $_.Value }
  $ii = $ip.imageinfo[0]
  $md = $ii.extmetadata
  $ext = [IO.Path]::GetExtension($f).ToLower(); if ($ext -eq '.jpeg') { $ext = '.jpg' }
  $src = if ($ii.thumburl) { $ii.thumburl } else { $ii.url }
  $out = Join-Path $Dir "$k$ext"
  Invoke-WebRequest -Uri $src -Headers $ua -OutFile $out -UseBasicParsing
  $credits[$k] = [ordered]@{
    File = "portraits/$k$ext"
    Source = $ii.descriptionurl
    License = [string]$md.LicenseShortName.value
    Artist = ([regex]::Replace([string]$md.Artist.value, '<[^>]+>', '') -replace '\s+', ' ').Trim()
  }
  "$k $ext $((Get-Item $out).Length) $($credits[$k].License)"
  Start-Sleep -Milliseconds 200
}
$credits | ConvertTo-Json -Depth 4 | Out-File -Encoding utf8 (Join-Path $Dir 'credits.json')
