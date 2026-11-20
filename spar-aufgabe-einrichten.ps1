<#
  Richtet die Windows-Aufgabe "Preis-Tracker Spar" ein: taeglich um 03:00 Uhr spar-taeglich.ps1.
  - Ist der PC um 03:00 aus, startet die Aufgabe beim naechsten Einschalten (StartWhenAvailable).
  - Laeuft nur, wenn du angemeldet bist (fuer Git- und GitHub-Zugang deines Benutzers).
  Aufruf (einmalig):  powershell -ExecutionPolicy Bypass -File spar-aufgabe-einrichten.ps1
  Entfernen:          Unregister-ScheduledTask -TaskName 'Preis-Tracker Spar' -Confirm:$false
#>
param([string]$Uhrzeit = '03:00')
$ErrorActionPreference = 'Stop'
$skript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'spar-taeglich.ps1'
$aktion = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$skript`"" -WorkingDirectory (Split-Path $skript)
$ausloeser = New-ScheduledTaskTrigger -Daily -At $Uhrzeit
$einst = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 3) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'Preis-Tracker Spar' -Action $aktion -Trigger $ausloeser -Settings $einst -Description 'Taeglicher Spar-Abruf fuer preise.kaipel.at (Spar sperrt GitHub-Server)' -Force | Out-Null
Write-Host "Aufgabe 'Preis-Tracker Spar' eingerichtet: taeglich um $Uhrzeit (bzw. beim naechsten Einschalten)."
Write-Host 'Protokolle: protokoll\spar-<datum>.log im Projektordner.'
