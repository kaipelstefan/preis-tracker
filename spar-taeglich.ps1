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
param([switch]$NurEinspielen)   # -NurEinspielen: vorhandene Rohdaten (roh-lokal) einspielen, ohne Spar neu abzurufen
$ErrorActionPreference = 'Stop'
$Ordner = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Ordner
$protokollOrdner = Join-Path $Ordner 'protokoll'
[void](New-Item -ItemType Directory -Force $protokollOrdner)
$log = Join-Path $protokollOrdner ("spar-{0:yyyy-MM-dd}.log" -f (Get-Date))
function Notiz([string]$t) { $z = "{0:HH:mm:ss} {1}" -f (Get-Date), $t; Write-Host $z; Add-Content -Path $log -Value $z -Encoding UTF8 }
# git.exe ausdruecklich: eine Funktion "Git" wuerde sich sonst selbst aufrufen (PowerShell: Gross-/Kleinschreibung egal).
# Meldungen von git auf stderr sind kein Fehler - massgeblich ist nur der Exitcode.
function Git-Aufruf([string[]]$a) {
    $alt = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = & git.exe @a 2>&1 | Out-String; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $alt }
    if ($code -ne 0) { throw "git $($a -join ' ') fehlgeschlagen: $o" }
    return $o
}
# Kategorie-Korrekturen von der Seite holen (api/zuordnung.php, Zugang aus rechnungen/zugang.json)
function Hole-Korrekturen {
    try {
        $z = Get-Content -Raw -Encoding UTF8 (Join-Path $Ordner 'rechnungen/zugang.json') | ConvertFrom-Json
        $auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($z.benutzer):$($z.passwort)"))
        $r = Invoke-WebRequest -UseBasicParsing -Uri (([string]$z.basis).TrimEnd('/') + '/api/zuordnung.php') -Headers @{ Authorization = "Basic $auth" } -TimeoutSec 60
        $j = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()) | ConvertFrom-Json
        $daten = @{}; foreach ($e in $j.zuordnung.PSObject.Properties) { $daten[$e.Name] = [ordered]@{ k = $e.Value.k; uk = $e.Value.uk } }
        [IO.File]::WriteAllText((Join-Path $Ordner 'daten/zuordnung.json'), ((ConvertTo-Json -InputObject $daten -Depth 4) + "`n"), (New-Object Text.UTF8Encoding $false))
        Notiz ("Kategorie-Korrekturen geholt: {0}" -f $daten.Count)
    } catch { Notiz "Kategorie-Korrekturen nicht geholt (Stand aus dem Repo gilt): $($_.Exception.Message)" }
}

try {
    Notiz 'Start Spar-Abruf'
    $roh = Join-Path $Ordner 'roh-lokal'
    if ($NurEinspielen) { Notiz 'Nur Einspielen: vorhandene Spar-Rohdaten werden verwendet' }
    else {
        if (Test-Path $roh) { Remove-Item $roh -Recurse -Force }
        # 1. Abrufen (nur Rohdaten)
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Ordner 'abrufen.ps1') -Maerkte spar -RohSchreiben $roh *>> $log
        if ($LASTEXITCODE -ne 0) { throw "Spar-Abruf fehlgeschlagen (Exitcode $LASTEXITCODE)" }
    }
    $datei = Join-Path $roh 'roh-spar.json'
    if (-not (Test-Path $datei) -or (Get-Item $datei).Length -lt 1MB) { throw 'Spar-Rohdaten fehlen oder sind zu klein' }
    Notiz ("Spar abgerufen: {0:N1} MB Rohdaten" -f ((Get-Item $datei).Length / 1MB))

    # 2. Neuesten Stand holen (lokale, erzeugte Historie verwerfen - massgeblich ist GitHub)
    Git-Aufruf @('checkout', '--', 'daten/historie.json', 'daten/spar-kategorien.json', 'daten/zuordnung.json') | Out-Null
    Git-Aufruf @('pull', '--ff-only', '-q') | Out-Null
    Notiz 'Neuester Stand von GitHub geholt'
    Hole-Korrekturen

    # 3. Spar einspielen, committen, pushen
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Ordner 'abrufen.ps1') -Maerkte spar -RohLesen $roh *>> $log
    if ($LASTEXITCODE -ne 0) { throw "Einspielen fehlgeschlagen (Exitcode $LASTEXITCODE)" }
    Git-Aufruf @('add', 'daten/historie.json', 'daten/spar-kategorien.json', 'daten/zuordnung.json') | Out-Null
    & git.exe diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        Git-Aufruf @('commit', '-q', '-m', 'Spar-Preise aktualisiert (Abruf vom PC)') | Out-Null
        try { Git-Aufruf @('push', '-q') | Out-Null }
        catch {
            # Falls GitHub inzwischen selbst gespeichert hat: neu holen, Spar nochmals einspielen, erneut pushen
            Notiz 'Push abgelehnt - hole neuen Stand und spiele Spar erneut ein'
            # nur den eigenen Spar-Commit zuruecknehmen; andere Dateien im Ordner bleiben unberuehrt
            Git-Aufruf @('reset', '-q', 'HEAD~1') | Out-Null
            Git-Aufruf @('checkout', '--', 'daten/historie.json', 'daten/spar-kategorien.json', 'daten/zuordnung.json') | Out-Null
            Git-Aufruf @('pull', '--ff-only', '-q') | Out-Null
            Hole-Korrekturen
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Ordner 'abrufen.ps1') -Maerkte spar -RohLesen $roh *>> $log
            Git-Aufruf @('add', 'daten/historie.json', 'daten/spar-kategorien.json', 'daten/zuordnung.json') | Out-Null
            Git-Aufruf @('commit', '-q', '-m', 'Spar-Preise aktualisiert (Abruf vom PC)') | Out-Null
            Git-Aufruf @('push', '-q') | Out-Null
        }
        Notiz 'Historie mit Spar gepusht'
    } else { Notiz 'Keine Aenderung an der Historie' }

    # 4. Seite aktualisieren lassen
    $ErrorActionPreference = 'Continue'
    & gh.exe workflow run abruf.yml -R kaipelstefan/preis-tracker --ref main *>> $log
    $ok = ($LASTEXITCODE -eq 0); $ErrorActionPreference = 'Stop'
    if (-not $ok) { throw 'GitHub-Lauf konnte nicht gestartet werden (gh angemeldet?)' }
    Notiz 'GitHub-Lauf gestartet - die Seite zeigt die neuen Spar-Daten in etwa 10 Minuten'
    Remove-Item $roh -Recurse -Force -ErrorAction SilentlyContinue
    Notiz 'Fertig'
} catch {
    Notiz "FEHLER: $($_.Exception.Message)"
    exit 1
}
