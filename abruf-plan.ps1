<#
  Erzeugt aus konfig.json ("abruf") die Job-Liste fuer den parallelen Abruf auf GitHub.
  Ausgabe (fuer $GITHUB_OUTPUT):
    schnell=["billa","penny",...]                     je Markt ein Job
    langsam=[{"markt":"spar","teil":0,"teile":16},...]  aufgeteilte Maerkte, je Teil ein Job
    schnelleliste=billa,penny,...                      fuer den Vorab-Lauf
#>
$Utf8 = New-Object Text.UTF8Encoding $false
$k = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'konfig.json'), $Utf8) | ConvertFrom-Json
$schnell = @(); $langsam = @()
$nurLokal = @($k.abruf.nur_lokal)
foreach ($m in $k.abruf.maerkte) {
    if ($nurLokal -contains $m) { continue }   # z. B. Spar: sperrt GitHub-Server (HTTP 403)
    $n = if ($k.abruf.teile.$m) { [int]$k.abruf.teile.$m } else { 0 }
    if ($n -gt 0) { for ($i = 0; $i -lt $n; $i++) { $langsam += [ordered]@{ markt = $m; teil = $i; teile = $n } } }
    else { $schnell += [string]$m }
}
"schnell=" + (ConvertTo-Json -InputObject @($schnell) -Compress)
"langsam=" + (ConvertTo-Json -InputObject @($langsam) -Compress)
"schnelleliste=" + ($schnell -join ',')
