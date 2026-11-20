<?php
// VORUEBERGEHEND: Diagnose fuer den Passwortschutz (nur mit API-Token). Schreibt .htaccess/.htpasswd
// ausschliesslich in den Testordner /authtest, damit die eigentliche Seite unberuehrt bleibt.
//   POST htaccess=<Inhalt>            -> authtest/.htaccess
//   POST htpasswd=<Inhalt>            -> authtest/.htpasswd-test
//   POST kopie=1                      -> kopiert die echte .htpasswd nach authtest/.htpasswd-kopie
//   POST hash=<passwort>&art=apr1|sha|bcrypt -> liefert nur den Hash (Passwort wird nicht gespeichert)
//   GET                               -> Pfade, Server-Infos, aktuelle Testdateien
declare(strict_types=1);
require __DIR__ . '/db.php';
pruefeToken();

$ordner = dirname(__DIR__) . '/authtest';
if (!is_dir($ordner)) mkdir($ordner, 0755, true);
if (!is_file($ordner . '/index.html')) file_put_contents($ordner . '/index.html', "<p>authtest ok</p>\n");

function apr1(string $pw): string {
    $salz = substr(strtr(base64_encode(random_bytes(6)), '+', '.'), 0, 8);
    $itoa = './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    $len = strlen($pw);
    $text = $pw . '$apr1$' . $salz;
    $bin = md5($pw . $salz . $pw, true);
    for ($i = $len; $i > 0; $i -= 16) $text .= substr($bin, 0, min(16, $i));
    for ($i = $len; $i > 0; $i >>= 1) $text .= ($i & 1) ? chr(0) : $pw[0];
    $bin = md5($text, true);
    for ($i = 0; $i < 1000; $i++) {
        $neu = ($i & 1) ? $pw : $bin;
        if ($i % 3) $neu .= $salz;
        if ($i % 7) $neu .= $pw;
        $neu .= ($i & 1) ? $bin : $pw;
        $bin = md5($neu, true);
    }
    $tmp = '';
    foreach ([[0, 6, 12], [1, 7, 13], [2, 8, 14], [3, 9, 15], [4, 10, 5]] as $t) {
        $v = (ord($bin[$t[0]]) << 16) | (ord($bin[$t[1]]) << 8) | ord($bin[$t[2]]);
        for ($j = 0; $j < 4; $j++) { $tmp .= $itoa[$v & 0x3f]; $v >>= 6; }
    }
    $v = ord($bin[11]);
    for ($j = 0; $j < 2; $j++) { $tmp .= $itoa[$v & 0x3f]; $v >>= 6; }
    return '$apr1$' . $salz . '$' . $tmp;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['htaccess'])) file_put_contents($ordner . '/.htaccess', (string)$_POST['htaccess']);
    if (isset($_POST['htpasswd'])) file_put_contents($ordner . '/.htpasswd-test', (string)$_POST['htpasswd']);
    if (isset($_POST['kopie'])) copy(dirname(__DIR__) . '/.htpasswd', $ordner . '/.htpasswd-kopie');
    if (isset($_POST['loeschen'])) { @unlink($ordner . '/.htaccess'); }
    if (isset($_POST['root'])) file_put_contents(dirname(__DIR__) . '/.htaccess', (string)$_POST['root']);
    if (isset($_POST['rootloeschen'])) @unlink(dirname(__DIR__) . '/.htaccess');
    if (isset($_POST['hash'])) {
        $pw = (string)$_POST['hash'];
        $art = (string)($_POST['art'] ?? 'apr1');
        $h = $art === 'sha' ? '{SHA}' . base64_encode(sha1($pw, true)) : ($art === 'bcrypt' ? password_hash($pw, PASSWORD_BCRYPT) : apr1($pw));
        antwort(['hash' => $h]);
    }
}
clearstatcache();
antwort([
    'ordner' => $ordner,
    'echte_htpasswd' => dirname(__DIR__) . '/.htpasswd',
    'htaccess' => is_file($ordner . '/.htaccess') ? file_get_contents($ordner . '/.htaccess') : null,
    'server' => $_SERVER['SERVER_SOFTWARE'] ?? '',
    'sapi' => PHP_SAPI,
    'php' => PHP_VERSION,
    'document_root' => $_SERVER['DOCUMENT_ROOT'] ?? '',
    'script' => $_SERVER['SCRIPT_FILENAME'] ?? '',
    'apache_module' => function_exists('apache_get_modules') ? apache_get_modules() : 'unbekannt',
]);
