<?php
// Strichcode-Scanner
//   GET  ean.php?ean=<code>              -> eigene Zuordnung (Artikel-ids) + Produktangaben von Open Food Facts
//   POST ean.php  {"ean": "...", "id": "billa:..."}           -> Zuordnung merken
//   POST ean.php  {"ean": "...", "id": "...", "loeschen": 1}  -> Zuordnung entfernen
// Open Food Facts (freie Produktdatenbank) wird nur mit der EAN abgefragt und 30 Tage zwischengespeichert.
declare(strict_types=1);
require __DIR__ . '/db.php';
pruefeAnmeldung();
$pdo = db();

function eanPruefen(string $e): string {
    $e = preg_replace('/\D/', '', $e);
    if (!preg_match('/^\d{8}$|^\d{12,14}$/', $e)) fehler('Ungültige EAN');
    return $e;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $in = json_decode((string)file_get_contents('php://input'), true);
    if (!is_array($in)) fehler('JSON erwartet');
    $ean = eanPruefen((string)($in['ean'] ?? ''));
    $id = (string)($in['id'] ?? '');
    if (!preg_match('/^[a-z]+:[A-Za-z0-9._-]{1,70}$/', $id)) fehler('Ungültige Artikel-id');
    if (!empty($in['loeschen'])) {
        $pdo->prepare('DELETE FROM pt_ean WHERE ean = ? AND artikel_id = ?')->execute([$ean, $id]);
    } else {
        $pdo->prepare('INSERT IGNORE INTO pt_ean (ean, artikel_id, erstellt) VALUES (?, ?, NOW())')->execute([$ean, $id]);
    }
    antwort(['ok' => true]);
}

$ean = eanPruefen((string)($_GET['ean'] ?? ''));
$st = $pdo->prepare('SELECT artikel_id FROM pt_ean WHERE ean = ? ORDER BY erstellt');
$st->execute([$ean]);
$ids = array_column($st->fetchAll(), 'artikel_id');

$st = $pdo->prepare('SELECT * FROM pt_ean_info WHERE ean = ? AND geholt > NOW() - INTERVAL 30 DAY');
$st->execute([$ean]);
$info = $st->fetch();
if (!$info) {
    $info = ['gefunden' => 0, 'name' => null, 'marke' => null, 'menge' => null];
    $ctx = stream_context_create(['http' => ['timeout' => 8, 'ignore_errors' => true,
        'header' => "User-Agent: PreisTracker/1.0 (privates Preisvergleichs-Werkzeug)\r\n"]]);
    $roh = @file_get_contents('https://world.openfoodfacts.org/api/v2/product/' . $ean . '.json?fields=product_name,product_name_de,brands,quantity', false, $ctx);
    $j = $roh ? json_decode($roh, true) : null;
    if (is_array($j)) {
        if (($j['status'] ?? 0) == 1 && isset($j['product'])) {
            $p = $j['product'];
            $info = ['gefunden' => 1,
                'name' => mb_substr(trim((string)(($p['product_name_de'] ?? '') ?: ($p['product_name'] ?? ''))), 0, 255) ?: null,
                'marke' => mb_substr(trim((string)($p['brands'] ?? '')), 0, 255) ?: null,
                'menge' => mb_substr(trim((string)($p['quantity'] ?? '')), 0, 100) ?: null];
        }
        // nur echte Antworten merken (auch "nicht gefunden"), Netzwerkfehler nicht
        $pdo->prepare('REPLACE INTO pt_ean_info (ean, gefunden, name, marke, menge, geholt) VALUES (?, ?, ?, ?, ?, NOW())')
            ->execute([$ean, $info['gefunden'], $info['name'], $info['marke'], $info['menge']]);
    } else {
        $info['fehler'] = 'Open Food Facts nicht erreichbar';
    }
}
antwort(['ean' => $ean, 'ids' => $ids, 'produkt' => [
    'gefunden' => (int)$info['gefunden'] === 1, 'name' => $info['name'], 'marke' => $info['marke'], 'menge' => $info['menge'],
    'fehler' => $info['fehler'] ?? null]]);
