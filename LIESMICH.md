# Preis-Tracker

Verfolgt die Preise des **Gesamtsortiments** österreichischer Supermärkte (Billa, Penny, Hofer, Lidl, Spar, dazu Kaffee von Tchibo) je Artikel und Packungsgröße. Aktionen werden gegen den echten Preisverlauf geprüft statt gegen den „Statt“-Preis. So fallen Lockvogel-Angebote auf.

Dazu kommen **eigene Einkäufe**: Rechnungen hochladen, auswerten lassen und die Ersparnis je Einkauf und gesamt sehen.

Geplante Adresse: https://preise.kaipel.at (passwortgeschützt, noch nicht eingerichtet).

## Lokal

- **Start.bat** (Doppelklick): holt alle Preise und öffnet `site/index.html`. Ein voller Abruf dauert **gut eine Stunde**, fast nur wegen der Drosselung bei Spar.
- **Schnell ohne Spar** (ca. 5 Minuten):
  `powershell -ExecutionPolicy Bypass -File abrufen.ps1 -Maerkte billa,penny,hofer,lidl,tchibo`
- Die Seite funktioniert lokal direkt von der Festplatte. Nur der Reiter **Einkäufe** braucht den Server (PHP und MySQL).

## Was die Seite zeigt

- **Angebote:** alles, was gerade in Aktion ist, mit Bewertung gegen den Median der letzten 90 Tage:
  - **Echtes Angebot:** mindestens 10 % unter dem Median.
  - **Mäßig:** 3 bis 10 % darunter.
  - **Lockvogel:** weniger als 3 % darunter.
  - **Noch kein Verlauf:** unter 21 Tagen Aufzeichnung. Bis dahin steht nur der Rabatt laut Markt da.
- **Warnhinweise:**
  - Normalpreis vor der Aktion erhöht
  - „Statt“-Preis über dem üblichen Normalpreis
  - Dauer-Aktion
  - Packung kleiner geworden
- **Aktionszeitraum** (⏱) bei jedem Angebot, soweit der Markt ihn liefert:
  - **Lidl:** „Do. 19.11. – Sa. 21.11. · noch bis morgen“, exakt laut Lidl.
  - **Penny:** Beginn der Angebotswoche laut Penny, Ende = Tag vor der nächsten Angebotswoche. „Monats-Deals“ laufen bis Monatsende.
  - **Hofer:** „seit …, solange der Vorrat reicht“.
  - **Billa und Spar:** Diese Shops nennen online kein Ende. Angezeigt wird „in Aktion seit …“ laut eigener Aufzeichnung („seit mind. …“, wenn die Aktion schon vor Beginn der Aufzeichnung lief).
  - Rot markiert, wenn die Aktion heute oder morgen endet. Sortierung „Endet bald“.
- **Demnächst:** Penny, Hofer und Lidl zeigen Angebote der nächsten Woche schon vorab („Angebot ab Do. 26.11. für 2,89 €“). Sie zählen noch nicht als laufende Aktion und stehen im Bewertungsfilter unter „Demnächst“.
- **Alle Artikel:** Ohne Auswahl erscheint eine Übersicht aller Kategorien mit Anzahl und laufenden Aktionen. Darunter gibt es Unterkategorien als Leiste und die Suche über alle Artikel (ab 2 Zeichen).
- **Favoriten (☆):**
  - Der Knopf „★ Favoriten (13 · 4 in Aktion)“ filtert auf die Favoriten.
  - Unter „Alle Artikel“ sind sie in „In Aktion“ und „Ohne aktuelles Angebot“ gruppiert.
  - Gespeichert wird je Browser.
- **Liste oder Kacheln:** Umschalter rechts in der Filterleiste.
- **Detail:** Preisverlauf als Diagramm, alle Preispunkte, Link zum Shop und **„Deine Käufe“** (Kaufdatum, Preis je Stück, Vergleich mit heute).
- **Einkäufe:** Rechnungen hochladen (Foto oder PDF, auch direkt mit der Handykamera). Dazu kommen:
  - Liste der Einkäufe mit Scan, Positionen, Summe und Ersparnis
  - Ersparnis gesamt und im laufenden Monat
  - „Zum Normalpreis gekauft“, mit Hinweis, wenn der Artikel gerade irgendwo in Aktion ist
  - Die Auswertung macht Claude Code auf Zuruf, siehe [RECHNUNGEN.md](RECHNUNGEN.md).
- **Deal-Tipps von sparhamster.at** im Reiter Angebote.

## Kategorien (`konfig.json`)

24 Hauptkategorien mit Unterkategorien. Die Anzeigereihenfolge bestimmt `pos`:

> Obst & Gemüse · Brot & Gebäck · Frühstück & Aufstriche · Milchprodukte, Käse & Eier · Fleisch · Wurst & Schinken · Fisch · Fertiggerichte · Tiefkühl · Nudeln · Vorrat & Kochen · Kaffee · Tee & Kakao · Alkoholfreie Getränke · Alkohol · Süßes & Knabbereien · Saisonales · Drogerie & Kosmetik · Haushalt & Garten · Baby & Kind · Tierbedarf · Werkzeug · Spielzeug, Mode & Non-Food · Sonstiges

**So funktioniert die Zuordnung:**

- **Gesamtsortiment:** Jeder Markt wird einmal komplett geladen. Jeder Artikel trägt die Namen (und IDs/Slugs) seiner Shop-Kategorien.
- **Reihenfolge:** Die Hauptkategorien werden in der Reihenfolge von `konfig.json` geprüft, darin die Unterkategorien. **Die erste passende Regel gewinnt.** Spezielle Kategorien stehen deshalb vorne (Alkohol, Nudeln, Kaffee, Fleisch, Alkoholfrei, Werkzeug), danach Tiefkühl, Baby, Tier, Drogerie, Haushalt usw.
- **Regeln je Markt** (`billa`, `spar`, `penny`, `lidl`, `hofer`, `tchibo`) oder für alle Märkte (`alle`):
  - `"slug-oder-id"`: Shop-Kategorie (Billa-Slug aus der URL, Spar-ID aus `spar.at/produktwelt/<id>`, Penny/Lidl-Kategoriename)
  - `{ "kat"|"pfad": "...", "muster": "...", "ohne": "..." }`: zusätzlich Regex auf den Artikelnamen
  - `{ "pfadre": "..." }`: Regex auf die Kategorienamen (für alle Märkte gleichzeitig)
  - `"und": "..."`: an Regel, Unter- oder Hauptkategorie. Der Regex muss zusätzlich irgendwo im Kategoriepfad passen, z. B. „tiefk“, damit tiefgekühltes Gemüse nicht beim frischen landet.
  - `"ohne"` direkt an der Hauptkategorie schließt Artikel nur dort aus, z. B. „alkoholfrei“ bei Alkohol.
- **Rest:** Was keine Regel trifft, kommt nach „Sonstiges“, Hofer-Wochenangebote ohne Kategorie in eine eigene Unterkategorie.
- **Weitere Felder:**
  - `ausschluss.stichworte`: wird nie gespeichert.
  - `ausgeblendet`: einzelne Artikel-IDs.
  - `auswertung`: Schwellen für die Bewertung.

## Daten

- **`daten/historie.json`:** eine Zeile je Artikel.
  - `m` Markt, `n` Name, `k`/`uk` Kategorie und Unterkategorie, `q`/`e` Menge und Einheit, `a`/`z` zuerst bzw. zuletzt gesehen
  - `av`/`ab` Aktionszeitraum laut Markt, `vp` Vorschaupreis eines kommenden Angebots
  - `p` Preispunkte `[Datum, Normal, Aktion|null, Menge, Aktionstext]`. Ein neuer Punkt kommt **nur bei einer Änderung** dazu.
- **`daten/spar-kategorien.json`:** Spar-Kategoriebaum (466 Blätter), 7 Tage zwischengespeichert.
- **`site/daten/*.js`** (erzeugt, nicht im Repo, über PHP komprimiert ausgeliefert). Die Seite lädt nur, was gerade gebraucht wird:
  - `index.js`: Übersicht
  - `angebote.js`: alle laufenden und kommenden Aktionen
  - `suche.js`: kompakter Index aller Artikel
  - `kat-<id>.js`: je Kategorie
- **MySQL** (World4You): `pt_rechnung` und `pt_position` für Einkäufe. Das Schema legt `site/api/db.php` beim ersten Aufruf selbst an.

## Online (preise.kaipel.at, noch einzurichten)

- **Repo öffentlich**, damit GitHub Actions kostenlos bleiben. Im Repo liegen nur Code, Konfiguration und Preisdaten. Rechnungen und Zugangsdaten sind nie darin, siehe `.gitignore`.
- **`.github/workflows/abruf.yml`:** täglich 04:23 UTC, so parallel wie möglich. Ein Planungs-Job liest `konfig.json` (`abruf.maerkte`, `abruf.teile`) und startet je Markt einen eigenen Job, große Märkte (Spar: 16 Teile) verteilt auf viele Jobs mit eigener IP-Adresse. Sobald die schnellen Märkte fertig sind (wenige Minuten), aktualisiert ein Vorab-Job die Seite. Zum Schluss führt ein Job alles zusammen, lädt hoch und committet die Historie. Fällt ein Job aus, fehlt nur dieser Teil für einen Tag. **Neuer Shop:** Abruf-Modul in `abrufen.ps1` (`Hole-Alles` plus Satz-Funktion) schreiben und in `konfig.json` unter `abruf.maerkte` eintragen, bei großen Shops zusätzlich unter `abruf.teile`.
- **`.github/workflows/deploy.yml`:** lädt `site/` mit PHP-API bei jeder Änderung hoch und erzeugt dabei `api/config.php` aus den Secrets. Den Passwortschutz (`.htpasswd` und `.htaccess`) schreibt der Server selbst über `passwort-setzen.ps1`. Bei World4You führte eine per FTP hochgeladene `.htaccess` zu HTTP 500.
- **Secrets:**
  - `FTP_SERVER`, `FTP_USERNAME`, `FTP_PASSWORD`
  - `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASS`
  - `PT_TOKEN`: zufällig, für die Auswertung aus Claude Code
  - (Passwortschutz: kein Secret nötig, siehe `passwort-setzen.ps1`)
- **Variablen:** `FTP_PROTOKOLL` (Standard `ftps`), `FTP_ZIELORDNER` (Verzeichnis der Subdomain).
- **Rechnungsdateien** liegen auf dem Webspace in `rechnungen/`. Der Ordner ist per `.htaccess` gesperrt und nur über `api/datei.php` hinter dem Seitenpasswort erreichbar.

## Datenquellen (Stand 20.11.2026)

| Quelle | Status | Schnittstelle |
|---|---|---|
| **Billa** | Gesamtsortiment (~12 000) | Kategoriebaum `shop.billa.at/api/product-discovery/categories/tree`, je Hauptkategorie `…/categories/<slug>/products?pageSize=500`. Kein Aktionszeitraum online. |
| **Penny** | gesamt (~600) | `www.penny.at/api/product-discovery/products`. Online vor allem Aktionsware. Zeitraum aus „Angebote ab TT.MM.“. |
| **Spar** | Gesamtsortiment (~40 000) | Kategoriebaum über `api-scp.spar-ics.com/ecom/pw/v1/category/v1/at/breadcrumb/<id>`, Artikel je Blatt-Kategorie über `…/search/v1/navigation?filter=pwCategoryIds:<id>&marketId=8999`. Höchstens 32 je Seite, und Cloudflare sperrt bei schnellen Anfragen (HTTP 429). Deshalb 2,5 s Pause. Kein Aktionszeitraum online. |
| **Hofer** | gesamt online (~1 300) | `asl.api.hofer.at/commerce/v3/product-search` (ohne Captcha). Frischsortiment plus Wochenangebote. „Verfügbar seit/ab“ als Start. |
| **Lidl** | aktuelles Angebot (~350) | `www.lidl.at/q/api/search?q=*`. Kein Dauersortiment online. Zeitraum in der Filiale exakt. Der „Statt“-Preis ist oft nur eine frühere Aktion. |
| **Tchibo** | nur Kaffee (~490) | Nuxt-Datenblock der Kategorieseite. Bot-Schutz: bei vielen schnellen Abrufen zeitweise HTTP 403. |
| **sparhamster.at** | Tipps | WordPress-API, Kategorie „Lebensmittel & Getränke“ |
| Interspar, Billa Plus | bewusst kein eigener Markt | Online dieselben Preise wie Spar bzw. Billa (geprüft) |
| dm, Bipa, marktguru, wogibtswas, aktionsfinder | offen | siehe frühere Prüfung: dm-API antwortet, marktguru braucht den öffentlichen Web-Schlüssel, wogibtswas nur als HTML |
| MPreis | bewusst weggelassen | |

## Hinweise

- **Normalpreis** = Preis ohne Aktion (Billa/Penny `price.standard`, Spar `stattPrice`). **Aktionspreis** = tatsächlich bezahlter Preis. Bei Mengenaktionen ist das der Stückpreis ab Mindestmenge.
- **Spar-Preise** gelten für den Online-Standardmarkt 8999. Regionale Filialaktionen fehlen.
- **Ausfälle:** Ändert ein Shop seine Schnittstelle, fehlt nur dieser Markt bzw. diese Kategorie („nicht geladen: …“ oben auf der Seite). Die anderen laufen weiter.
