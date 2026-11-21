<?php
// Haendische Kategorie-Korrekturen
//   GET  zuordnung.php                                   -> {"zuordnung": {"<id>": {"k":..,"uk":..,"von":..}}}
//   POST zuordnung.php {"id","k","uk","von","name"}      -> Korrektur speichern
//   POST zuordnung.php {"id","loeschen":1}               -> Korrektur entfernen (wieder automatisch)
// Nach jeder Aenderung wird eigene/zuordnung.json geschrieben (per .htaccess gesperrt). Diese Datei holt der
// taegliche Abruf per FTP und wendet die Korrekturen dauerhaft an (Repo: daten/zuordnung.json).
declare(strict_types=1);
require __DIR__ . '/db.php';
pruefeAnmeldung();
$pdo = db();

function alleZuordnungen(PDO $pdo): array {
    $z = [];
    foreach ($pdo->query('SELECT artikel_id, k, uk, von, name, geaendert FROM pt_zuordnung ORDER BY artikel_id') as $r) {
        $z[$r['artikel_id']] = ['k' => $r['k'], 'uk' => $r['uk'], 'von' => $r['von'], 'name' => $r['name'], 'geaendert' => $r['geaendert']];
    }
    return $z;
}

function schreibeDatei(array $z): void {
    $d = __DIR__ . '/../eigene';
    if (!is_dir($d)) mkdir($d, 0750, true);
    if (!is_file($d . '/.htaccess')) file_put_contents($d . '/.htaccess', "Require all denied\nDeny from all\n");
    file_put_contents($d . '/zuordnung.json', json_encode((object)$z, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT) . "\n", LOCK_EX);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $in = json_decode((string)file_get_contents('php://input'), true);
    if (!is_array($in)) fehler('JSON erwartet');
    $id = (string)($in['id'] ?? '');
    if (!preg_match('/^[a-z]+:[A-Za-z0-9._-]{1,70}$/', $id)) fehler('Ungültige Artikel-id');
    if (!empty($in['loeschen'])) {
        $pdo->prepare('DELETE FROM pt_zuordnung WHERE artikel_id = ?')->execute([$id]);
    } else {
        $k = (string)($in['k'] ?? ''); $uk = (string)($in['uk'] ?? ''); $von = isset($in['von']) ? (string)$in['von'] : null;
        foreach ([$k, $uk] as $w) if (!preg_match('/^[a-z0-9-]{1,40}$/', $w)) fehler('Ungültige Kategorie');
        if ($von !== null && !preg_match('/^[a-z0-9-]{1,40}$/', $von)) $von = null;
        $name = mb_substr((string)($in['name'] ?? ''), 0, 255) ?: null;
        // "von" (Kategorie-Datei, in der der Artikel liegt) bei einer erneuten Korrektur nicht ueberschreiben
        $pdo->prepare('INSERT INTO pt_zuordnung (artikel_id, k, uk, von, name, geaendert) VALUES (?, ?, ?, ?, ?, NOW())
                       ON DUPLICATE KEY UPDATE k = VALUES(k), uk = VALUES(uk), von = COALESCE(von, VALUES(von)), name = VALUES(name), geaendert = NOW()')
            ->execute([$id, $k, $uk, $von, $name]);
    }
    $z = alleZuordnungen($pdo);
    schreibeDatei($z);
    antwort(['ok' => true, 'anzahl' => count($z)]);
}

antwort(['zuordnung' => (object)alleZuordnungen($pdo)]);
