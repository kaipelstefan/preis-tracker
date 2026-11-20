<?php
// Lesezugriff fuer die Seite:
//   einkaeufe.php                 -> alle Rechnungen mit Positionen + Summen (Ersparnis gesamt, je Monat)
//   einkaeufe.php?artikel=<id>    -> eigene Kaeufe eines Artikels (fuer das Artikel-Detail)
//   einkaeufe.php?loeschen=<id>   -> Rechnung samt Datei loeschen (POST)
declare(strict_types=1);
require __DIR__ . '/db.php';
pruefeAnmeldung();
$pdo = db();

if (isset($_GET['artikel'])) {
    $st = $pdo->prepare('SELECT p.*, r.datum, r.markt, r.filiale FROM pt_position p JOIN pt_rechnung r ON r.id = p.rechnung_id
                         WHERE p.artikel_id = ? ORDER BY r.datum DESC, p.id DESC');
    $st->execute([(string)$_GET['artikel']]);
    antwort(['kaeufe' => array_map('positionZeile', $st->fetchAll())]);
}

if (isset($_GET['loeschen'])) {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') fehler('Nur POST', 405);
    $id = (int)$_GET['loeschen'];
    $st = $pdo->prepare('SELECT datei FROM pt_rechnung WHERE id = ?'); $st->execute([$id]);
    $r = $st->fetch(); if (!$r) fehler('Unbekannte Rechnung', 404);
    $pdo->prepare('DELETE FROM pt_rechnung WHERE id = ?')->execute([$id]);
    @unlink(ablage() . '/' . basename($r['datei']));
    antwort(['ok' => true]);
}

$rech = array_map('rechnungZeile', $pdo->query('SELECT * FROM pt_rechnung ORDER BY COALESCE(datum, DATE(hochgeladen)) DESC, id DESC')->fetchAll());
$pos = [];
foreach ($pdo->query('SELECT * FROM pt_position ORDER BY rechnung_id, zeile') as $p) $pos[(int)$p['rechnung_id']][] = positionZeile($p);
$summe = 0.0; $ersparnis = 0.0; $monate = [];
foreach ($rech as &$r) {
    $r['positionen'] = $pos[$r['id']] ?? [];
    if ($r['status'] !== 'ausgewertet') continue;
    $summe += (float)$r['summe']; $ersparnis += (float)$r['ersparnis'];
    $m = substr((string)$r['datum'], 0, 7);
    if (!isset($monate[$m])) $monate[$m] = ['monat' => $m, 'summe' => 0.0, 'ersparnis' => 0.0, 'einkaeufe' => 0];
    $monate[$m]['summe'] += (float)$r['summe']; $monate[$m]['ersparnis'] += (float)$r['ersparnis']; $monate[$m]['einkaeufe']++;
}
unset($r);
krsort($monate);
antwort(['rechnungen' => $rech, 'gesamt' => ['summe' => round($summe, 2), 'ersparnis' => round($ersparnis, 2), 'einkaeufe' => count(array_filter($rech, fn($r) => $r['status'] === 'ausgewertet'))], 'monate' => array_values($monate)]);
