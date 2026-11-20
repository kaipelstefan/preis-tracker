<#
  Richtet den Passwortschutz fuer preise.kaipel.at ein (einmalig, bei Bedarf wiederholbar zum Passwortwechsel).
  - fragt Benutzername und Passwort ab (Passwort verdeckt)
  - legt auf dem Server die .htpasswd an (Passwort nur verschluesselt gespeichert)
  - hinterlegt den Pfad als GitHub-Secret HTPASSWD_PFAD und startet den Deploy (schreibt die .htaccess)
  - traegt Benutzer/Passwort in rechnungen\zugang.json ein (fuer die Rechnungsauswertung, nicht im Repo)

  Aufruf:  powershell -ExecutionPolicy Bypass -File passwort-setzen.ps1
#>
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Ordner = Split-Path -Parent $MyInvocation.MyCommand.Path
$Utf8 = New-Object Text.UTF8Encoding $false
$zDatei = Join-Path $Ordner 'rechnungen\zugang.json'
$z = [IO.File]::ReadAllText($zDatei, $Utf8) | ConvertFrom-Json
$basis = ([string]$z.basis).TrimEnd('/') + '/'

$benutzer = Read-Host 'Benutzername fuer die Seite (z. B. stefan)'
$p1 = Read-Host 'Passwort (mind. 10 Zeichen)' -AsSecureString
$p2 = Read-Host 'Passwort wiederholen' -AsSecureString
function Klartext($s) { [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)) }
$pw = Klartext $p1
if ($pw -ne (Klartext $p2)) { throw 'Die Passwoerter stimmen nicht ueberein.' }

Write-Host 'Lege .htpasswd auf dem Server an ...'
$antwort = Invoke-RestMethod -Uri ($basis + 'api/passwort.php') -Method Post -Headers @{ 'X-PT-Token' = [string]$z.token } -Body @{ benutzer = $benutzer; passwort = $pw }
if (-not $antwort.ok) { throw "Server: $($antwort.fehler)" }
Write-Host "  .htpasswd: $($antwort.pfad)"

Write-Host 'Hinterlege den Pfad in GitHub und starte den Deploy ...'
$antwort.pfad | gh secret set HTPASSWD_PFAD -R kaipelstefan/preis-tracker
gh workflow run deploy.yml -R kaipelstefan/preis-tracker --ref main

$z.benutzer = $benutzer; $z.passwort = $pw
[IO.File]::WriteAllText($zDatei, (ConvertTo-Json $z), $Utf8)
Write-Host ''
Write-Host 'Fertig. In etwa einer Minute fragt preise.kaipel.at nach Benutzer und Passwort.'
