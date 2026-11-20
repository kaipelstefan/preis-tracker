<?php
// Gescannte Rechnung ausliefern: datei.php?id=123  (Seite ist per Passwort geschuetzt)
declare(strict_types=1);
require __DIR__ . '/db.php';
pruefeAnmeldung();

$id = (int)($_GET['id'] ?? 0);
$st = db()->prepare('SELECT datei, mime, original FROM pt_rechnung WHERE id = ?');
$st->execute([$id]);
$r = $st->fetch();
if (!$r) fehler('Unbekannte Rechnung', 404);
$pfad = ablage() . '/' . basename($r['datei']);
if (!is_file($pfad)) fehler('Datei fehlt', 404);
header('Content-Type: ' . ($r['mime'] ?: 'application/octet-stream'));
header('Content-Length: ' . filesize($pfad));
header('Content-Disposition: inline; filename="' . rawurlencode($r['original'] ?: $r['datei']) . '"');
header('Cache-Control: private, max-age=86400');
readfile($pfad);
