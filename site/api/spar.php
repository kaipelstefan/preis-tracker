<?php
// Vermittler fuer den Spar-Abruf: Spar sperrt die Server von GitHub, den Webspace aber nicht.
// Der GitHub-Abruf ruft  spar.php?url=<Spar-Adresse>  auf; das Skript holt genau diese Adresse und gibt die
// Antwort unveraendert zurueck (inkl. Statuscode und Retry-After bei Drosselung).
// Erlaubt sind NUR Lese-Adressen der Spar-Produktschnittstelle - kein allgemeiner Proxy.
// Zugriff nur mit Seitenpasswort UND Token (GitHub-Secrets PT_SEITE und PT_TOKEN).
declare(strict_types=1);
require __DIR__ . '/db.php';
pruefeAnmeldung();
pruefeToken();

$url = (string)($_GET['url'] ?? '');
$erlaubt = '#^https://api-scp\.spar-ics\.com/ecom/pw/v1/(search/v1/navigation\?[A-Za-z0-9=&%:._*,+-]+|category/v1/at/breadcrumb/[A-Za-z0-9._-]+)$#';
if (!preg_match($erlaubt, $url)) fehler('Adresse nicht erlaubt', 400);

$ctx = stream_context_create(['http' => ['timeout' => 40, 'ignore_errors' => true, 'header' =>
    "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36\r\n" .
    "Accept: application/json\r\nAccept-Language: de-AT,de;q=0.9\r\nOrigin: https://www.spar.at\r\nReferer: https://www.spar.at/\r\n"]]);
$roh = @file_get_contents($url, false, $ctx);
$kopf = $http_response_header ?? [];
$code = 502;
if (isset($kopf[0]) && preg_match('#^HTTP/\S+\s+(\d{3})#', $kopf[0], $m)) $code = (int)$m[1];
foreach ($kopf as $z) if (stripos($z, 'Retry-After:') === 0) header($z);
http_response_code($roh === false ? 502 : $code);
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
echo $roh === false ? json_encode(['fehler' => 'Spar nicht erreichbar']) : $roh;
