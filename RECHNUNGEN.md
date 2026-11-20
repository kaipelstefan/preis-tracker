# Rechnungen auswerten (Anleitung für Claude Code)

Rechnungen lädt Stefan auf preise.kaipel.at im Reiter **Einkäufe** hoch (Foto oder PDF). Die Auswertung macht Claude Code auf Zuruf, z. B. „werte die neuen Rechnungen aus“. Dabei entstehen keine API-Kosten.

## Ablauf

1. **Abholen:** `powershell -ExecutionPolicy Bypass -File rechnungen.ps1 -Holen`
   Lädt alle noch nicht ausgewerteten Rechnungen nach `rechnungen\eingang\` (`<id>.jpg|pdf` plus `<id>.json`).
2. **Lesen:** Jede Datei mit dem Read-Werkzeug ansehen (Bilder und PDFs gehen direkt). Erfassen:
   - **Markt:** `billa`, `penny`, `hofer`, `lidl`, `spar` oder `tchibo`. Billa Plus zählt als `billa`, Interspar und Eurospar als `spar`.
   - **Filiale:** Adresse oder Ort, falls auf dem Bon.
   - **Datum:** `yyyy-MM-dd`.
   - **Summe:** Endbetrag, den Stefan bezahlt hat.
   - **rabatt_bon:** gesamte Ersparnis laut Bon, falls ausgewiesen (z. B. „Sie haben … gespart“, jö-Bonus, Lidl-Plus-Rabatte).
   - **Positionen:** Name wie auf dem Bon, Menge (Stück bzw. kg), Einzelpreis, Gesamtpreis, Rabatt der Zeile (Aktion, „-25 %“, Mengenrabatt, Pickerl) und ob es eine Aktion war.
3. **Zuordnen:** Für jede Position die Artikel-ID suchen:
   `powershell -ExecutionPolicy Bypass -File rechnungen.ps1 -Suche "clever milch" -Markt billa`
   - Bon-Namen sind abgekürzt, deshalb mit Stichworten suchen (Marke plus Produkt) und Packungsgröße und Preis vergleichen.
   - Findet sich nichts Eindeutiges, `artikel_id: null` lassen. Lieber keine als eine falsche Zuordnung.
   - **Normalpreis am Kaufdatum:** `rechnungen.ps1 -Preis "billa:00-123456" -Datum 2026-11-20`. Er wird bei Aktionen als `normalpreis` mitgeschickt.
4. **Ergebnis** als `rechnungen\auswertung\<id>.json` schreiben (Format unten) und senden:
   `powershell -ExecutionPolicy Bypass -File rechnungen.ps1 -Senden rechnungen\auswertung\<id>.json`
5. **Stefan kurz berichten:** Markt, Datum, Summe, Ersparnis, Anzahl Positionen und welche Positionen nicht zugeordnet wurden.

## Format der Auswertung

```json
{
  "id": 12,
  "markt": "billa",
  "filiale": "Wien 14., Hütteldorfer Straße 130",
  "datum": "2026-11-20",
  "summe": 54.37,
  "rabatt_bon": 6.20,
  "notiz": "jö-Bonus 2,00 € eingelöst",
  "positionen": [
    { "name_bon": "CLEVER H-MILCH 3,5%", "artikel_id": "billa:00-123456", "menge": 2, "einheit": "stk",
      "einzelpreis": 1.19, "gesamt": 2.38, "rabatt": 0, "aktion": 0, "normalpreis": 1.19 },
    { "name_bon": "TCHIBO FEINE MILDE 500G", "artikel_id": "billa:00-284795", "menge": 1, "einheit": "stk",
      "einzelpreis": 5.99, "gesamt": 5.99, "rabatt": 2.00, "aktion": 1, "normalpreis": 7.99 },
    { "name_bon": "BANANEN", "artikel_id": null, "menge": 1.234, "einheit": "kg",
      "einzelpreis": 1.79, "gesamt": 2.21, "rabatt": 0, "aktion": 0 }
  ]
}
```

- **`einzelpreis`:** tatsächlich bezahlter Preis je Stück bzw. kg, nach Rabatt (= `gesamt` / `menge`). Der Normalpreis steht getrennt in `normalpreis`.
- **`gesamt`:** tatsächlich bezahlt für die Zeile, nach Abzug des Rabatts.
- **`rabatt`:** Ersparnis dieser Zeile. Steht der Rabatt am Bon als eigene Zeile (z. B. „Aktion −2,00“), gehört er zur Position darüber.
- **Ersparnis des Einkaufs:** Der Server nimmt die Summe der `rabatt`-Werte oder `rabatt_bon`, je nachdem, was größer ist.
- **Pfand** (z. B. „Pfand 0,25“) als eigene Position mit `artikel_id: null` und Name „Pfand“.
- **Fehlt ein Rabatt am Bon**, ist aber `normalpreis` laut Historie höher als der bezahlte Einzelpreis: `rabatt` = Differenz × Menge und `aktion: 1`.

## Was die Seite daraus macht

- **Einkäufe:** Liste aller Rechnungen mit Scan, Positionen, Summe und Ersparnis, dazu die Ersparnis gesamt und im laufenden Monat.
- **„Zum Normalpreis gekauft“:** Artikel ohne Aktion, mit Hinweis, wenn sie gerade irgendwo in Aktion sind.
- **Artikel-Detail:** „Deine Käufe“ mit Datum, Markt, Preis je Stück und Vergleich zum heutigen Preis.
