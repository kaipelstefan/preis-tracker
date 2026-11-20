<#
  Taeglicher Spar-Abruf vom eigenen PC (Spar sperrt die Server von GitHub mit HTTP 403).
  Ablauf:
    1. Spar komplett abrufen und nur Rohdaten schreiben (ca. 1 Stunde, Historie bleibt unberuehrt)
    2. neuesten Stand von GitHub holen (die Historie aendert sich dort taeglich)
    3. Spar in diese frische Historie einspielen, committen und sofort pushen
    4. GitHub-Lauf "Preise abrufen" starten -> Seite wird mit den neuen Spar-Daten aktualisiert
  Protokoll: rechnungen\..\protokoll\spar-<datum>.log (nicht im Repo)

  Aufruf (meist ueber die Windows-Aufgabenplanung, siehe spar-aufgabe-einrichten.ps1):
    powershell -ExecutionPolicy Bypass -File spar-taeglich.ps1
#>
$ErrorActionPreference = 'Stop'
$Ordner = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Ordner
$protokollOrdner = Join-Path $Ordner 'protokoll'
[void](New-Item -ItemType Directory -Force $protokollOrdner)
$log = Join-Path $protokollOrdner ("spar-{0:yyyy-MM-dd}.log" -f (Get-Date))
function Notiz([string]$t) { $z = "{0:HH:mm:ss} {1}" -f (Get-Date), $t; Write-Host $z; Add-Content -Path $log -Value $z -Encoding UTF8 }
function Git([string[]]$a) { $o = & git @a 2>&1; if ($LASTEXITCODE -ne 0) { throw "git $($a -join ' ') fehlgeschlagen: $o" }; return $o }

try {
    Notiz 'Start Spar-Abruf'
    $roh = Join-Path $Ordner 'roh-lokal'
    if (Test-Path $roh) { Remove-Item $roh -Recurse -Force }

    # 1. Abrufen (nur Rohdaten)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Ordner 'abrufen.ps1') -Maerkte spar -RohSchreiben $roh *>> $log
    if ($LASTEXITCODE -ne 0) { throw "Spar-Abruf fehlgeschlagen (Exitcode $LASTEXITCODE)" }
    $datei = Join-Path $roh 'roh-spar.json'
    if (-not (Test-Path $datei) -or (Get-Item $datei).Length -lt 1MB) { throw 'Spar-Rohdaten fehlen oder sind zu klein' }
    Notiz ("Spar abgerufen: {0:N1} MB Rohdaten" -f ((Get-Item $datei).Length / 1MB))

    # 2. Neuesten Stand holen (lokale, erzeugte Historie verwerfen - massgeblich ist GitHub)
    Git @('checkout', '--', 'daten/historie.json', 'daten/spar-kategorien.json') | Out-Null
    Git @('pull', '--ff-only', '-q') | Out-Null
    Notiz 'Neuester Stand von GitHub geholt'

    # 3. Spar einspielen, committen, pushen
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Ordner 'abrufen.ps1') -Maerkte spar -RohLesen $roh *>> $log
    if ($LASTEXITCODE -ne 0) { throw "Einspielen fehlgeschlagen (Exitcode $LASTEXITCODE)" }
    Git @('add', 'daten/historie.json', 'daten/spar-kategorien.json') | Out-Null
    & git diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        Git @('commit', '-q', '-m', 'Spar-Preise aktualisiert (Abruf vom PC)') | Out-Null
        try { Git @('push', '-q') | Out-Null }
        catch {
            # Falls GitHub inzwischen selbst gespeichert hat: neu holen, Spar nochmals einspielen, erneut pushen
            Notiz 'Push abgelehnt - hole neuen Stand und spiele Spar erneut ein'
            # nur den eigenen Spar-Commit zuruecknehmen; andere Dateien im Ordner bleiben unberuehrt
            Git @('reset', '-q', 'HEAD~1') | Out-Null
            Git @('checkout', '--', 'daten/historie.json', 'daten/spar-kategorien.json') | Out-Null
            Git @('pull', '--ff-only', '-q') | Out-Null
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Ordner 'abrufen.ps1') -Maerkte spar -RohLesen $roh *>> $log
            Git @('add', 'daten/historie.json', 'daten/spar-kategorien.json') | Out-Null
            Git @('commit', '-q', '-m', 'Spar-Preise aktualisiert (Abruf vom PC)') | Out-Null
            Git @('push', '-q') | Out-Null
        }
        Notiz 'Historie mit Spar gepusht'
    } else { Notiz 'Keine Aenderung an der Historie' }

    # 4. Seite aktualisieren lassen
    & gh workflow run abruf.yml -R kaipelstefan/preis-tracker --ref main *>> $log
    Notiz 'GitHub-Lauf gestartet - die Seite zeigt die neuen Spar-Daten in etwa 10 Minuten'
    Remove-Item $roh -Recurse -Force -ErrorAction SilentlyContinue
    Notiz 'Fertig'
} catch {
    Notiz "FEHLER: $($_.Exception.Message)"
    exit 1
}
