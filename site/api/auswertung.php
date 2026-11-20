<?php
// Schnittstelle fuer das Auswerten in Claude Code (rechnungen.ps1). Zusaetzlich zum Seitenpasswort per Token geschuetzt.
//   GET  auswertung.php?neu=1            -> Liste der noch nicht ausgewerteten Rechnungen
//   GET  auswertung.php?datei=<id>       -> Datei einer Rechnung herunterladen
//   POST auswertung.php  (JSON)          -> Ergebnis speichern:
//        { "id": 12, "markt": "billa", "filiale": "...", "datum": "2026-11-20", "summe": 54.37, "rabatt_bon": 6.20,
//          "notiz": "...", "positionen": [ { "name_bon": "...", "artikel_id": "billa:00-123"|null, "menge": 2, "einheit": "stk",
//          "einzelpreis": 1.99, "gesamt": 3.98, "rabatt": 0.80, "aktion": 1, "normalpreis": 2.39 }, ... ] }
//        Ersparnis der Rechnung = Summe aus rabatt der Positionen (bzw. rabatt_bon, falls hoeher)
declare(strict_types=1);
require __DIR__ . '/db.php';
pruefeAnmeldung();
pruefeToken();
$pdo = db();

if (isset($_GET['neu'])) {
    $l = $pdo->query("SELECT id, datei, original, mime, hochgeladen, notiz FROM pt_rechnung WHERE status <> 'ausgewertet' ORDER BY id")->fetchAll();
    antwort(['neu' => $l]);
}
if (isset($_GET['datei'])) {
    $st = $pdo->prepare('SELECT datei, mime FROM pt_rechnung WHERE id = ?'); $st->execute([(int)$_GET['datei']]);
    $r = $st->fetch(); if (!$r) fehler('Unbekannte Rechnung', 404);
    $pfad = ablage() . '/' . basename($r['datei']);
    header('Content-Type: ' . $r['mime']); header('Content-Length: ' . filesize($pfad));
    readfile($pfad); exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') fehler('GET ?neu=1 | GET ?datei=<id> | POST JSON', 405);

$in = json_decode(file_get_contents('php://input') ?: '', true);
if (!is_array($in) || empty($in['id'])) fehler('JSON mit "id" erwartet');
$id = (int)$in['id'];
$pos = $in['positionen'] ?? [];
$rabattSumme = 0.0;
foreach ($pos as $p) $rabattSumme += (float)($p['rabatt'] ?? 0);
$ersparnis = max($rabattSumme, (float)($in['rabatt_bon'] ?? 0));

$pdo->beginTransaction();
$pdo->prepare('DELETE FROM pt_position WHERE rechnung_id = ?')->execute([$id]);
$st = $pdo->prepare('INSERT INTO pt_position (rechnung_id, zeile, name_bon, artikel_id, menge, einheit, einzelpreis, gesamt, rabatt, aktion, normalpreis)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
foreach ($pos as $i => $p) {
    $st->execute([$id, $i + 1, mb_substr((string)($p['name_bon'] ?? '?'), 0, 255), $p['artikel_id'] ?? null, (float)($p['menge'] ?? 1),
        $p['einheit'] ?? null, isset($p['einzelpreis']) ? (float)$p['einzelpreis'] : null, (float)($p['gesamt'] ?? 0),
        (float)($p['rabatt'] ?? 0), !empty($p['aktion']) ? 1 : 0, isset($p['normalpreis']) ? (float)$p['normalpreis'] : null]);
}
$pdo->prepare("UPDATE pt_rechnung SET status = 'ausgewertet', markt = ?, filiale = ?, datum = ?, summe = ?, rabatt_bon = ?, ersparnis = ?, notiz = COALESCE(?, notiz), ausgewertet = NOW() WHERE id = ?")
    ->execute([$in['markt'] ?? null, $in['filiale'] ?? null, $in['datum'] ?? null, isset($in['summe']) ? (float)$in['summe'] : null,
        isset($in['rabatt_bon']) ? (float)$in['rabatt_bon'] : null, round($ersparnis, 2), $in['notiz'] ?? null, $id]);
$pdo->commit();
antwort(['ok' => true, 'id' => $id, 'positionen' => count($pos), 'ersparnis' => round($ersparnis, 2)]);
