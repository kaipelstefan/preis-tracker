<?php
// Einmal-Test: Darf der Webspace die Spar-Schnittstelle abrufen? (GitHub wird von Spar gesperrt.)
// Eine einzige Anfrage (nur Angebote, 1 Treffer). Nur mit Seitenpasswort UND Token aufrufbar.
declare(strict_types=1);
require __DIR__ . '/db.php';
pruefeAnmeldung();
pruefeToken();

$url = 'https://api-scp.spar-ics.com/ecom/pw/v1/search/v1/navigation?query=*&sort=Relevancy:asc&page=1&hitsPerPage=1&marketId=8999&showPermutedSearchParams=false&filter=inAngebot%3Atrue';
$ctx = stream_context_create(['http' => ['timeout' => 20, 'ignore_errors' => true, 'header' =>
    "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36\r\n" .
    "Accept: application/json\r\nOrigin: https://www.spar.at\r\nReferer: https://www.spar.at/\r\n"]]);
$start = microtime(true);
$roh = @file_get_contents($url, false, $ctx);
$status = isset($http_response_header[0]) ? $http_response_header[0] : 'keine Antwort';
$j = $roh ? json_decode($roh, true) : null;
antwort([
    'status' => $status,
    'dauer_ms' => (int)round((microtime(true) - $start) * 1000),
    'json' => is_array($j),
    'angebote' => is_array($j) ? ($j['paging']['totalHits'] ?? ($j['totalHits'] ?? null)) : null,
    'beispiel' => is_array($j) && !empty($j['hits'][0]['masterValues']) ? trim(($j['hits'][0]['masterValues']['name1'] ?? '') . ' ' . ($j['hits'][0]['masterValues']['name2'] ?? '')) : null,
    'anfang' => $roh && !is_array($j) ? mb_substr(strip_tags($roh), 0, 200) : null,
]);
