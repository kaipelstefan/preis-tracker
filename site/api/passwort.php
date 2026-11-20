<?php
// Legt die .htpasswd fuer den Seitenschutz an (nur mit API-Token, Aufruf ueber passwort-setzen.ps1).
//   GET  passwort.php            -> { pfad, vorhanden }
//   POST passwort.php  benutzer, passwort  -> schreibt .htpasswd (bcrypt), liefert den absoluten Pfad
declare(strict_types=1);
require __DIR__ . '/db.php';
pruefeToken();

$datei = dirname(__DIR__) . '/.htpasswd';
if ($_SERVER['REQUEST_METHOD'] !== 'POST') antwort(['pfad' => $datei, 'vorhanden' => is_file($datei)]);

$b = trim((string)($_POST['benutzer'] ?? ''));
$p = (string)($_POST['passwort'] ?? '');
if (!preg_match('/^[A-Za-z0-9._-]{3,40}$/', $b)) fehler('Benutzername: 3-40 Zeichen, nur Buchstaben, Ziffern, Punkt, Strich, Unterstrich');
if (strlen($p) < 10) fehler('Passwort: mindestens 10 Zeichen');
$hash = password_hash($p, PASSWORD_BCRYPT);
if (file_put_contents($datei, $b . ':' . $hash . "\n", LOCK_EX) === false) fehler('Konnte .htpasswd nicht schreiben', 500);
@chmod($datei, 0640);
antwort(['ok' => true, 'pfad' => realpath($datei) ?: $datei]);
