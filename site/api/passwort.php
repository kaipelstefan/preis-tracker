<?php
// Legt die .htpasswd fuer den Seitenschutz an (nur mit API-Token, Aufruf ueber passwort-setzen.ps1).
//   GET  passwort.php            -> { pfad, vorhanden }
//   POST passwort.php  benutzer, passwort  -> schreibt .htpasswd (bcrypt), liefert den absoluten Pfad
declare(strict_types=1);
require __DIR__ . '/db.php';
pruefeToken();

$datei = dirname(__DIR__) . '/.htpasswd';
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    // ?rechte=1: Leserechte fuer den Webserver setzen (0644; die Datei bleibt per .htaccess fuer Besucher gesperrt)
    if (isset($_GET['rechte']) && is_file($datei)) @chmod($datei, 0644);
    clearstatcache();
    $info = ['pfad' => $datei, 'vorhanden' => is_file($datei)];
    if (is_file($datei)) {
        $info['rechte'] = substr(sprintf('%o', fileperms($datei)), -4);
        $info['zeilen'] = count(file($datei, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES));
        $info['format'] = preg_match('/^[^:]+:\$2y\$/', (string)file_get_contents($datei)) ? 'bcrypt' : 'anderes';
    }
    $info['php_user'] = function_exists('posix_geteuid') ? (posix_getpwuid(posix_geteuid())['name'] ?? '?') : get_current_user();
    $info['document_root'] = $_SERVER['DOCUMENT_ROOT'] ?? '';
    antwort($info);
}

$b = trim((string)($_POST['benutzer'] ?? ''));
$p = (string)($_POST['passwort'] ?? '');
if (!preg_match('/^[A-Za-z0-9._-]{3,40}$/', $b)) fehler('Benutzername: 3-40 Zeichen, nur Buchstaben, Ziffern, Punkt, Strich, Unterstrich');
if (strlen($p) < 10) fehler('Passwort: mindestens 10 Zeichen');
$hash = password_hash($p, PASSWORD_BCRYPT);
if (file_put_contents($datei, $b . ':' . $hash . "\n", LOCK_EX) === false) fehler('Konnte .htpasswd nicht schreiben', 500);
@chmod($datei, 0644);   // Webserver muss lesen koennen; Zugriff von aussen sperrt die .htaccess (.ht*)
antwort(['ok' => true, 'pfad' => realpath($datei) ?: $datei]);
