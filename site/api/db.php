<?php
// Gemeinsame Basis der API: Konfiguration, Datenbank (PDO/MySQL), Hilfsfunktionen.
// Die Zugangsdaten stehen in config.php (nicht im Repo; Vorlage: config.beispiel.php).
declare(strict_types=1);

$cfgDatei = __DIR__ . '/config.php';
if (!is_file($cfgDatei)) {
    http_response_code(500);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['fehler' => 'config.php fehlt (siehe config.beispiel.php)']);
    exit;
}
$CFG = require $cfgDatei;

function antwort($daten, int $code = 200): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($daten, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function fehler(string $text, int $code = 400): void { antwort(['fehler' => $text], $code); }

function db(): PDO {
    static $pdo = null;
    global $CFG;
    if ($pdo) return $pdo;
    $dsn = 'mysql:host=' . $CFG['db_host'] . ';dbname=' . $CFG['db_name'] . ';charset=utf8mb4';
    $pdo = new PDO($dsn, $CFG['db_user'], $CFG['db_pass'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    schema($pdo);
    return $pdo;
}

// Tabellen bei Bedarf anlegen (idempotent)
function schema(PDO $pdo): void {
    $pdo->exec("CREATE TABLE IF NOT EXISTS pt_rechnung (
        id INT AUTO_INCREMENT PRIMARY KEY,
        datei VARCHAR(255) NOT NULL,
        original VARCHAR(255) NULL,
        mime VARCHAR(100) NULL,
        hochgeladen DATETIME NOT NULL,
        status ENUM('neu','ausgewertet','fehler') NOT NULL DEFAULT 'neu',
        markt VARCHAR(20) NULL,
        filiale VARCHAR(255) NULL,
        datum DATE NULL,
        summe DECIMAL(10,2) NULL,
        rabatt_bon DECIMAL(10,2) NULL,
        ersparnis DECIMAL(10,2) NULL,
        notiz TEXT NULL,
        ausgewertet DATETIME NULL,
        INDEX (datum), INDEX (status)
    ) DEFAULT CHARSET=utf8mb4");
    $pdo->exec("CREATE TABLE IF NOT EXISTS pt_position (
        id INT AUTO_INCREMENT PRIMARY KEY,
        rechnung_id INT NOT NULL,
        zeile INT NOT NULL,
        name_bon VARCHAR(255) NOT NULL,
        artikel_id VARCHAR(80) NULL,
        menge DECIMAL(10,3) NOT NULL DEFAULT 1,
        einheit VARCHAR(10) NULL,
        einzelpreis DECIMAL(10,2) NULL,
        gesamt DECIMAL(10,2) NOT NULL,
        rabatt DECIMAL(10,2) NOT NULL DEFAULT 0,
        aktion TINYINT(1) NOT NULL DEFAULT 0,
        normalpreis DECIMAL(10,2) NULL,
        INDEX (artikel_id), INDEX (rechnung_id),
        CONSTRAINT fk_pt_rechnung FOREIGN KEY (rechnung_id) REFERENCES pt_rechnung(id) ON DELETE CASCADE
    ) DEFAULT CHARSET=utf8mb4");
    // Strichcode-Scanner: eigene Zuordnung EAN -> Artikel (eine EAN kann in mehreren Maerkten vorkommen)
    $pdo->exec("CREATE TABLE IF NOT EXISTS pt_ean (
        ean VARCHAR(14) NOT NULL,
        artikel_id VARCHAR(80) NOT NULL,
        erstellt DATETIME NOT NULL,
        PRIMARY KEY (ean, artikel_id)
    ) DEFAULT CHARSET=utf8mb4");
    // Zwischenspeicher fuer Open-Food-Facts-Antworten (Name, Marke, Menge)
    $pdo->exec("CREATE TABLE IF NOT EXISTS pt_ean_info (
        ean VARCHAR(14) NOT NULL PRIMARY KEY,
        gefunden TINYINT(1) NOT NULL,
        name VARCHAR(255) NULL,
        marke VARCHAR(255) NULL,
        menge VARCHAR(100) NULL,
        geholt DATETIME NOT NULL
    ) DEFAULT CHARSET=utf8mb4");
}

// Ablage der Rechnungs-Dateien (per .htaccess gesperrt, Auslieferung nur ueber datei.php)
function ablage(): string {
    global $CFG;
    $d = $CFG['ablage'] ?? (__DIR__ . '/../rechnungen');
    if (!is_dir($d)) mkdir($d, 0750, true);
    if (!is_file($d . '/.htaccess')) file_put_contents($d . '/.htaccess', "Require all denied\nDeny from all\n");
    return rtrim($d, '/');
}

// Zweite Sperre: private Daten nur, wenn der Webserver eine Anmeldung (Verzeichnisschutz) gemeldet hat.
// Fehlt der Passwortschutz versehentlich, bleiben Rechnungen und Einkaeufe trotzdem zu.
function pruefeAnmeldung(): void {
    global $CFG;
    if (($CFG['anmeldung_pruefen'] ?? true) === false) return;
    foreach (['REMOTE_USER', 'REDIRECT_REMOTE_USER', 'PHP_AUTH_USER', 'AUTH_USER'] as $k) {
        if (!empty($_SERVER[$k])) return;
    }
    // Manche Hoster reichen nur den Authorization-Header durch
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? ($_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '');
    if (stripos((string)$h, 'Basic ') === 0) return;
    fehler('Kein Passwortschutz aktiv – Zugriff gesperrt. Bitte den Verzeichnisschutz für die Seite einrichten.', 403);
}

// Schutz fuer Schreibzugriffe aus Claude Code: Token zusaetzlich zum Seitenpasswort
function pruefeToken(): void {
    global $CFG;
    $t = $_SERVER['HTTP_X_PT_TOKEN'] ?? ($_GET['token'] ?? '');
    if (trim((string)($CFG['api_token'] ?? '')) === '' || !hash_equals(trim((string)$CFG['api_token']), trim((string)$t))) fehler('Token fehlt oder falsch', 403);
}

function rechnungZeile(array $r): array {
    foreach (['summe', 'rabatt_bon', 'ersparnis'] as $f) if ($r[$f] !== null) $r[$f] = (float)$r[$f];
    $r['id'] = (int)$r['id'];
    return $r;
}

function positionZeile(array $p): array {
    foreach (['menge', 'einzelpreis', 'gesamt', 'rabatt', 'normalpreis'] as $f) if ($p[$f] !== null) $p[$f] = (float)$p[$f];
    $p['id'] = (int)$p['id']; $p['rechnung_id'] = (int)$p['rechnung_id']; $p['zeile'] = (int)$p['zeile']; $p['aktion'] = (int)$p['aktion'];
    return $p;
}
