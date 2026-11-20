<?php
// Vorlage. Auf dem Webspace als config.php ablegen (wird beim Deploy aus GitHub-Secrets erzeugt)
// und NIE ins Repo committen.
return [
    'db_host'   => 'localhost',          // World4You: Datenbank-Host laut Kundenbereich
    'db_name'   => 'DATENBANKNAME',
    'db_user'   => 'BENUTZER',
    'db_pass'   => 'PASSWORT',
    'api_token' => 'LANGES-ZUFAELLIGES-TOKEN',   // fuer das Auswerten aus Claude Code (rechnungen.ps1)
    // 'ablage' => '/pfad/ausserhalb/des/webroots/rechnungen',   // optional; Standard: site/rechnungen (gesperrt)
];
