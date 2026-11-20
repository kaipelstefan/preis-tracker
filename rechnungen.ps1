<#
  Rechnungen auswerten (Hilfsskript fuer Claude Code, siehe RECHNUNGEN.md).

  powershell -ExecutionPolicy Bypass -File rechnungen.ps1 -Holen
      Laedt alle noch nicht ausgewerteten Rechnungen nach rechnungen\eingang\ (Datei + <id>.json).
  powershell -ExecutionPolicy Bypass -File rechnungen.ps1 -Suche "clever milch" [-Markt billa]
      Sucht passende Artikel-IDs in der lokalen Historie (Name, Markt, aktueller Preis).
  powershell -ExecutionPolicy Bypass -File rechnungen.ps1 -Preis "billa:00-123456" -Datum 2026-11-20
      Normal- und Aktionspreis eines Artikels an einem Tag laut Historie.
  powershell -ExecutionPolicy Bypass -File rechnungen.ps1 -Senden rechnungen\auswertung\12.json
      Schickt eine Auswertung an den Server (speichert Positionen, Summe, Ersparnis).

  Zugangsdaten: rechnungen\zugang.json  { "basis": "https://preise.kaipel.at/", "benutzer": "...", "passwort": "...", "token": "..." }
  (nicht im Repo). Skript enthaelt bewusst keine Umlaute (PowerShell 5.1).
#>
param(
    [switch]$Holen,
    [string]$Suche,
    [string]$Markt,
    [string]$Preis,
    [string]$Datum,
    [string]$Senden
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Ordner = Split-Path -Parent $MyInvocation.MyCommand.Path
$Utf8 = New-Object Text.UTF8Encoding $false
$RO = Join-Path $Ordner 'rechnungen'

function Zugang {
    $z = Join-Path $RO 'zugang.json'
    if (-not (Test-Path $z)) { throw "rechnungen\zugang.json fehlt (basis, benutzer, passwort, token)" }
    $c = [IO.File]::ReadAllText($z, $Utf8) | ConvertFrom-Json
    $auth = [Convert]::ToBase64String($Utf8.GetBytes("$($c.benutzer):$($c.passwort)"))
    return @{ basis = ([string]$c.basis).TrimEnd('/') + '/'; kopf = @{ Authorization = "Basic $auth"; 'X-PT-Token' = [string]$c.token } }
}

function Lade-Historie {
    $d = Join-Path (Join-Path $Ordner 'daten') 'historie.json'
    return ([IO.File]::ReadAllText($d, $Utf8) | ConvertFrom-Json)
}

if ($Holen) {
    $z = Zugang
    $r = Invoke-WebRequest -Uri ($z.basis + 'api/auswertung.php?neu=1') -Headers $z.kopf -UseBasicParsing
    $l = ($Utf8.GetString($r.RawContentStream.ToArray()) | ConvertFrom-Json).neu
    $ein = Join-Path $RO 'eingang'
    [void](New-Item -ItemType Directory -Force $ein)
    foreach ($x in @($l)) {
        if (-not $x) { continue }
        $ext = [IO.Path]::GetExtension([string]$x.datei)
        $ziel = Join-Path $ein ("{0}{1}" -f $x.id, $ext)
        Invoke-WebRequest -Uri ($z.basis + "api/auswertung.php?datei=$($x.id)") -Headers $z.kopf -UseBasicParsing -OutFile $ziel
        [IO.File]::WriteAllText((Join-Path $ein ("{0}.json" -f $x.id)), (ConvertTo-Json $x -Depth 3), $Utf8)
        Write-Host ("Rechnung {0}: {1} (hochgeladen {2})" -f $x.id, $ziel, $x.hochgeladen)
    }
    if (-not @($l | Where-Object { $_ }).Count) { Write-Host 'Keine neuen Rechnungen.' }
    return
}

if ($Suche) {
    # Kompakter Suchindex der Seite: [id, Name, Markt, Kat, Unterkat, Preis, Aktionspreis, Menge, Einheit]
    $js = [IO.File]::ReadAllText((Join-Path $Ordner 'site\daten\suche.js'), $Utf8)
    $json = $js.Substring($js.IndexOf(',') + 1).TrimEnd().TrimEnd(';').TrimEnd(')')
    $index = $json | ConvertFrom-Json
    $worte = @($Suche.ToLower() -split '\s+' | Where-Object { $_ })
    $treffer = foreach ($z in $index) {
        if ($Markt -and $z[2] -ne $Markt) { continue }
        $n = ([string]$z[1]).ToLower()
        $ok = $true; foreach ($w in $worte) { if (-not $n.Contains($w)) { $ok = $false; break } }
        if (-not $ok) { continue }
        [pscustomobject]@{ id = $z[0]; name = $z[1]; markt = $z[2]; menge = "$($z[7]) $($z[8])"; normal = $z[5]; aktion = $z[6] }
    }
    $treffer | Select-Object -First 30 | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
    return
}

if ($Preis) {
    $h = Lade-Historie
    $v = $h.$Preis
    if (-not $v) { throw "Unbekannte Artikel-ID: $Preis" }
    $tag = if ($Datum) { $Datum } else { (Get-Date).ToString('yyyy-MM-dd') }
    $gilt = $null
    foreach ($pt in @($v.p)) { if ($pt[0] -le $tag) { $gilt = $pt } }
    if (-not $gilt) { $gilt = @($v.p)[0]; Write-Host "(Vor Beginn der Aufzeichnung; erster bekannter Preis)" }
    Write-Host ("{0} | {1} | am {2}: normal {3}, Aktion {4}, Menge {5} {6}" -f $Preis, $v.n, $tag, $gilt[1], $gilt[2], $gilt[3], $v.e)
    return
}

if ($Senden) {
    $z = Zugang
    $json = [IO.File]::ReadAllText((Resolve-Path $Senden), $Utf8)
    $null = $json | ConvertFrom-Json   # Syntax pruefen
    $r = Invoke-WebRequest -Uri ($z.basis + 'api/auswertung.php') -Method Post -Headers $z.kopf -ContentType 'application/json; charset=utf-8' -Body $Utf8.GetBytes($json) -UseBasicParsing
    Write-Host $Utf8.GetString($r.RawContentStream.ToArray())
    return
}

Get-Help $MyInvocation.MyCommand.Path
