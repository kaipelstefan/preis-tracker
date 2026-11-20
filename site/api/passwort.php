<?php
// Passwortschutz der Seite einrichten (nur mit API-Token, Aufruf ueber passwort-setzen.ps1).
//   GET  passwort.php                       -> { pfad, vorhanden, schutz_aktiv }
//   POST passwort.php  benutzer, passwort   -> schreibt .htpasswd (bcrypt) UND die .htaccess der Seite
// Hinweis: Bei World4You funktioniert die .htaccess nur, wenn der Server sie selbst schreibt
// (per FTP hochgeladen fuehrte sie zu HTTP 500). Der Deploy fasst sie deshalb nicht an.
declare(strict_types=1);
require __DIR__ . '/db.php';
pruefeToken();

$wurzel = dirname(__DIR__);
$pwDatei = $wurzel . '/.htpasswd';
$htDatei = $wurzel . '/.htaccess';

// Reste der einmaligen Fehlersuche entfernen
if (is_dir($wurzel . '/authtest')) {
    foreach (glob($wurzel . '/authtest/{,.}*', GLOB_BRACE) ?: [] as $f) if (is_file($f)) @unlink($f);
    @rmdir($wurzel . '/authtest');
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    antwort(['pfad' => $pwDatei, 'vorhanden' => is_file($pwDatei), 'schutz_aktiv' => is_file($htDatei) && str_contains((string)file_get_contents($htDatei), 'AuthUserFile')]);
}

$b = trim((string)($_POST['benutzer'] ?? ''));
$p = (string)($_POST['passwort'] ?? '');
if (!preg_match('/^[A-Za-z0-9._-]{3,40}$/', $b)) fehler('Benutzername: 3-40 Zeichen, nur Buchstaben, Ziffern, Punkt, Strich, Unterstrich');
if (strlen($p) < 10) fehler('Passwort: mindestens 10 Zeichen');

if (file_put_contents($pwDatei, $b . ':' . password_hash($p, PASSWORD_BCRYPT) . "\n", LOCK_EX) === false) fehler('Konnte .htpasswd nicht schreiben', 500);
@chmod($pwDatei, 0644);   // Webserver muss lesen koennen; Apache liefert .ht*-Dateien nie aus

$ht = <<<HT
# Passwortschutz fuer die ganze Seite. Geschrieben von api/passwort.php (passwort-setzen.ps1), nicht vom Deploy.
AuthType Basic
AuthName "Preis-Tracker"
AuthUserFile $pwDatei
Require valid-user

# Daten nicht cachen, damit der taegliche Stand sofort sichtbar ist
<IfModule mod_headers.c>
<FilesMatch "\.(js|html)$">
Header set Cache-Control "no-cache"
</FilesMatch>
</IfModule>

# Komprimierung (grosse Daten-Dateien)
<IfModule mod_deflate.c>
AddOutputFilterByType DEFLATE text/html application/javascript text/javascript application/json text/css
</IfModule>

HT;
if (file_put_contents($htDatei, $ht, LOCK_EX) === false) fehler('Konnte .htaccess nicht schreiben', 500);
@chmod($htDatei, 0644);
antwort(['ok' => true, 'pfad' => $pwDatei, 'schutz_aktiv' => true]);
