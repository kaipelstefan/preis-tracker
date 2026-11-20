<#
  Richtet den Passwortschutz fuer preise.kaipel.at ein oder aendert das Passwort.
  - fragt Benutzername und Passwort ab (Passwort verdeckt)
  - der Server schreibt .htpasswd (Passwort nur verschluesselt) und die .htaccess der Seite
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

$kopf = @{ 'X-PT-Token' = [string]$z.token }
# Ist der Schutz schon aktiv (Passwortwechsel), mit den bisherigen Zugangsdaten anmelden
if ($z.benutzer -and $z.passwort -and ([string]$z.benutzer) -notlike 'HIER-*') {
    $kopf['Authorization'] = 'Basic ' + [Convert]::ToBase64String($Utf8.GetBytes("$($z.benutzer):$($z.passwort)"))
}

Write-Host 'Richte den Passwortschutz auf dem Server ein ...'
$antwort = Invoke-RestMethod -Uri ($basis + 'api/passwort.php') -Method Post -Headers $kopf -Body @{ benutzer = $benutzer; passwort = $pw }
if (-not $antwort.ok) { throw "Server: $($antwort.fehler)" }

$z.benutzer = $benutzer; $z.passwort = $pw
[IO.File]::WriteAllText($zDatei, (ConvertTo-Json $z), $Utf8)
Write-Host ''
Write-Host 'Fertig. preise.kaipel.at fragt ab sofort nach Benutzer und Passwort.'
