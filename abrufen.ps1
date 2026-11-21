<#
  Preis-Tracker: holt Preise von Billa, Penny, Hofer, Lidl, Spar (und Kaffee von Tchibo) fuer die Kategorien aus konfig.json,
  schreibt die Historie (daten/historie.json, nur bei Preisaenderung ein neuer Punkt)
  und erzeugt site/daten.js fuer die Webseite.

  Aufruf:  powershell -ExecutionPolicy Bypass -File abrufen.ps1 [-Maerkte billa,spar]
  Aufgeteilter Abruf (GitHub Actions, parallel):
    abrufen.ps1 -Maerkte billa,penny -RohSchreiben roh              nur laden, Rohdaten nach roh\ schreiben
    abrufen.ps1 -Maerkte spar -Teil 0 -Teile 16 -RohSchreiben roh   nur jede 16. Spar-Kategorie ab 0
    abrufen.ps1 -RohLesen roh                                      Rohdaten zusammenfuehren, Historie + Seite
    Maerkte und Teilung stehen in konfig.json unter "abruf" (steuert auch die parallelen GitHub-Jobs).
  Laeuft unter Windows PowerShell 5.1 und PowerShell 7. Das Skript enthaelt bewusst keine
  Umlaute (5.1 liest Skripte als ANSI); Umlaute kommen nur aus den UTF-8-Dateien.
#>
param(
    [string[]]$Maerkte = @('billa', 'penny', 'hofer', 'lidl', 'tchibo', 'spar'),
    [int]$TageAnzeigen = 7,      # Artikel, die so lange nicht mehr gesehen wurden, fehlen auf der Seite
    [int]$TageBehalten = 400,    # ... und fliegen nach so vielen Tagen aus der Historie
    [string]$RohSchreiben = '',  # Ordner: nur abrufen und Rohdaten je Markt dorthin schreiben, dann Ende
    [string]$RohLesen = '',      # Ordner: statt abzurufen die Rohdaten von dort lesen
    [Alias("SparTeil")][int]$Teil = -1,     # nur diesen Teil eines grossen Marktes abrufen (0 .. Teile-1), derzeit Spar
    [Alias("SparTeile")][int]$Teile = 1     # in wie viele Teile der Markt aufgeteilt ist
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Ordner      = Split-Path -Parent $MyInvocation.MyCommand.Path
$KonfigDatei = Join-Path $Ordner 'konfig.json'
$HistDatei   = Join-Path (Join-Path $Ordner 'daten') 'historie.json'
$AusOrdnerHinweis = 'site/daten'   # Ausgabe siehe Ende des Skripts
$Utf8        = New-Object Text.UTF8Encoding $false
$UA          = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
$Inv         = [Globalization.CultureInfo]::InvariantCulture
$Heute       = [DateTime]::UtcNow.AddHours(1).ToString('yyyy-MM-dd')   # Wiener Datum (Winterzeit reicht fuer einen Tageswert)

function Lies-Json([string]$Pfad) { [IO.File]::ReadAllText($Pfad, $Utf8) | ConvertFrom-Json }

function Hole-Json([string]$Url, [hashtable]$Kopf = @{}, [int]$PauseMs = 250) {
    for ($versuch = 1; ; $versuch++) {
        try {
            $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -UserAgent $UA -Headers $Kopf -TimeoutSec 60
            $text = $Utf8.GetString($r.RawContentStream.ToArray())
            Start-Sleep -Milliseconds $PauseMs  # hoeflich bleiben
            return ($text | ConvertFrom-Json)
        } catch {
            $code = 0; $retry = 0
            $antwort = $_.Exception.Response
            if ($antwort) {
                $code = [int]$antwort.StatusCode
                try {   # Retry-After: PowerShell 5.1 (WebResponse) bzw. 7 (HttpResponseMessage)
                    if ($antwort.Headers.RetryAfter) { $retry = [int]$antwort.Headers.RetryAfter.Delta.TotalSeconds }
                    elseif ($antwort.Headers['Retry-After']) { $retry = [int]$antwort.Headers['Retry-After'] }
                } catch { }
            }
            if ($versuch -ge 8) { throw "Abruf fehlgeschlagen: $Url ($($_.Exception.Message))" }
            # 429 = zu viele Anfragen (Cloudflare): Retry-After abwarten, mindestens 30 s
            $warte = if ($code -eq 429) { [math]::Max(30, $retry + 5) * [math]::Min($versuch, 3) } else { 3 * $versuch }
            Write-Host "    HTTP $code, warte $warte s ..."
            Start-Sleep -Seconds $warte
        }
    }
}

function Runde($x) { if ($null -eq $x) { return $null }; return [math]::Round([double]$x, 3) }

# Packungsgroesse in Basiseinheit (kg, l, stk) umrechnen.
function Menge([double]$Zahl, [string]$Einheit) {
    switch -regex ($Einheit.Trim().ToLower()) {
        '^(g|gr|gramm)$'      { return @{ q = $Zahl / 1000; e = 'kg' } }
        '^(kg|kilogramm)$'    { return @{ q = $Zahl; e = 'kg' } }
        '^(ml|milliliter)$'   { return @{ q = $Zahl / 1000; e = 'l' } }
        '^(cl)$'              { return @{ q = $Zahl / 100; e = 'l' } }
        '^(l|lt|liter)$'      { return @{ q = $Zahl; e = 'l' } }
        default               { return @{ q = $Zahl; e = 'stk' } }
    }
}

$Konfig = Lies-Json $KonfigDatei
# Regex fuer Shop-Kategorien, die gar nicht abgerufen werden (Billa: Hauptkategorie, Spar: Kategoriepfad)
$Auslassen = if ($Konfig.abruf -and $Konfig.abruf.auslassen) { [string]$Konfig.abruf.auslassen } else { '' }
$AusStichworte = @($Konfig.ausschluss.stichworte | ForEach-Object { [regex]::Escape($_.ToLower()) })
$AusRegex      = if ($AusStichworte.Count) { [regex]('(' + ($AusStichworte -join '|') + ')') } else { $null }
$AusKategorien = @{}; foreach ($k in $Konfig.ausschluss.kategorien) { $AusKategorien[$k.ToLower()] = $true }
$Ausgeblendet  = @{}; foreach ($k in $Konfig.ausgeblendet) { $Ausgeblendet[[string]$k] = $true }

function Ist-Ausgeschlossen($Satz, [string[]]$Pfadnamen) {
    if ($Ausgeblendet.ContainsKey($Satz.key)) { return $true }
    if ($AusRegex -and $AusRegex.IsMatch($Satz.n.ToLower())) { return $true }
    foreach ($p in $Pfadnamen) { if ($AusKategorien.ContainsKey(([string]$p).ToLower())) { return $true } }
    return $false
}

# ---------------------------------------------------------------- Billa / Penny (gleiche REWE-Schnittstelle)
function Rewe-Satz($Markt, $UrlBasis, $p, $Kat) {
    if (-not $p.price -or -not $p.price.regular -or -not $p.price.regular.value) { return $null }
    $regulaer = $p.price.regular.value / 100
    $normal   = if ($p.price.standard -and $p.price.standard.value) { $p.price.standard.value / 100 } else { $regulaer }
    $aktion   = if ($regulaer -lt $normal) { $regulaer } else { $null }
    $atext    = if ($aktion) { if ($p.price.regular.promotionText) { $p.price.regular.promotionText } else { 'Aktion' } } else { $null }

    if ($p.weightArticle) {
        $m = @{ q = 1.0; e = 'kg' }; $g = 'per kg'
    } else {
        $zahl = 0.0
        [void][double]::TryParse(([string]$p.amount).Replace(',', '.'), [Globalization.NumberStyles]::Float, $Inv, [ref]$zahl)
        if ($zahl -le 0) { $zahl = 1 }
        $m = Menge $zahl ([string]$p.volumeLabelShort)
        $g = ("$($p.amount) $($p.volumeLabelShort)").Trim()
        if ($m.e -eq 'stk' -and -not $p.volumeLabelShort) { $g = "$($p.amount) Stk" }
    }
    return [ordered]@{
        key = "$Markt`:$($p.sku)"; m = $Markt; n = [string]$p.name; k = $Kat
        g = $g; q = (Runde $m.q); e = $m.e
        normal = $normal; aktion = $aktion; at = $atext
        u = "$UrlBasis/produkte/$($p.slug)"
        b = $(if ($p.images) { @($p.images)[0] } else { $null })
        hs = $(if ($p.brand -and $p.brand.name) { [string]$p.brand.name } else { $null })
    }
}

$script:Teilfehler = @()
function Melde-Teilfehler([string]$Was, $Fehler) {
    Write-Warning "$Was fehlgeschlagen: $($Fehler.Exception.Message)"
    $script:Teilfehler += $Was
}

function Pfadnamen($p) { $n = @(); foreach ($pfad in @($p.parentCategories)) { foreach ($c in @($pfad)) { $n += $c.name } }; return $n }

# ---------------------------------------------------------------- Spar
function Spar-Menge([string]$Text, $geo) {
    # name3 z. B. "500 G", "1 KG", "0,75 L", "10 STK", "6 X 0,5 L"
    $m = [regex]::Match($Text.Trim(), '^(?:(\d+)\s*[xX]\s*)?([\d.,]+)\s*([A-Za-z]+)')
    if ($m.Success) {
        $zahl = [double]::Parse($m.Groups[2].Value.Replace(',', '.'), $Inv)
        if ($m.Groups[1].Success) { $zahl *= [int]$m.Groups[1].Value }
        return (Menge $zahl $m.Groups[3].Value)
    }
    if ($geo.comparisonPrice_price -and $geo.comparisonPrice_unit -match '^(kg|l)$') {
        return @{ q = [double]$geo.calculatedPrice / [double]$geo.comparisonPrice_price; e = $geo.comparisonPrice_unit }
    }
    return @{ q = 1.0; e = 'stk' }
}

function Spar-Satz($h) {
    $mv = $h.masterValues
    $geo = @($mv.geoInformation)[0].geoValues
    if (-not $geo -or -not $geo.basePrice) { return $null }
    $normal  = if ($geo.stattPrice) { [double]$geo.stattPrice } else { [double]$geo.basePrice }
    $bezahlt = if ($geo.calculatedPrice) { [double]$geo.calculatedPrice } else { [double]$geo.basePrice }
    $aktion  = if ($geo.inAngebot -and $bezahlt -lt $normal) { $bezahlt } else { $null }
    $atext   = if ($aktion) { if ($geo.promotionBadgeText) { [string]$geo.promotionBadgeText } else { 'Aktion' } } else { $null }
    $groesse = [string]$mv.name3
    $m = Spar-Menge $groesse $geo
    return [ordered]@{
        key = "spar:$($mv.productId)"; m = 'spar'; n = ((@($mv.name1, $mv.name2) | Where-Object { $_ }) -join ' '); k = $null
        g = $groesse; q = (Runde $m.q); e = $m.e
        normal = $normal; aktion = $aktion; at = $atext
        u = "https://www.spar.at/produktwelt/$($mv.slug)"
        b = $(if ($mv.productImage_assetUrl) { $mv.productImage_assetUrl.Replace('{size}', '500').Replace('{ext}', 'jpg') } else { $null })
        hs = $(if ($mv.name1) { [string]$mv.name1 } else { $null })
    }
}

# ---------------------------------------------------------------- Lidl (nur das aktuelle Filial-/Online-Angebot, ca. 350 Artikel)
function Lidl-Satz($i) {
    $d = $i.gridbox.data
    if (-not $d) { return $null }
    $preis = $d.price.price; $alt = $d.price.oldPrice; $text = $null
    if (-not $preis -and $d.lidlPlus) {
        # Nur mit Lidl Plus verbilligt: Preis und Statt-Preis aus der Lidl-Plus-Angabe
        $preis = @($d.lidlPlus)[0].price.price; $text = 'mit Lidl Plus'
        $reg = @($d.regionsPrices.PSObject.Properties)[0]
        if ($reg -and $reg.Value.currentLidlPlusPrice) { $alt = $reg.Value.currentLidlPlusPrice.price.oldPrice }
    }
    if (-not $preis) { return $null }
    $preis = [double]$preis
    $normal = if ($alt -and [double]$alt -gt $preis) { [double]$alt } else { $preis }
    $aktion = if ($normal -gt $preis) { $preis } else { $null }
    $badge = @($d.stockAvailability.badgeInfo.badges | ForEach-Object { $_.text }) -join ', '
    # Zeitraum in der Filiale (Unix-Sekunden, Wiener Zeit)
    $von = $null; $bis = $null
    if ($d.storeStartDate) { $von = [DateTimeOffset]::FromUnixTimeSeconds([int64]$d.storeStartDate).UtcDateTime.AddHours(1).ToString('yyyy-MM-dd') }
    if ($d.storeEndDate)   { $bis = [DateTimeOffset]::FromUnixTimeSeconds([int64]$d.storeEndDate).UtcDateTime.AddHours(1).ToString('yyyy-MM-dd') }
    $atext = $null
    if ($aktion) {
        $teile = @()
        if ($text) { $teile += $text } elseif ($d.price.discount.discountText) { $teile += [string]$d.price.discount.discountText } else { $teile += 'Aktion' }
        if ($badge) { $teile += $badge }
        $atext = $teile -join (' ' + [char]0x00B7 + ' ')
    }
    $pack = [string]$d.price.packaging.text
    $m = @{ q = 1.0; e = 'stk' }
    $mm = [regex]::Match($pack, '(?:(\d+)\s*x\s*)?(\d+(?:[.,]\d+)?)\s*-?\s*(kg|g|ml|cl|l)\b', 'IgnoreCase')
    if ($mm.Success) {
        $zahl = [double]::Parse($mm.Groups[2].Value.Replace(',', '.'), $Inv)
        if ($mm.Groups[1].Success) { $zahl *= [int]$mm.Groups[1].Value }
        $m = Menge $zahl $mm.Groups[3].Value
    }
    return [ordered]@{
        key = "lidl:$($d.productId)"; m = 'lidl'; n = [string]$d.fullTitle; k = $null
        g = ($pack -replace '^Je\s*', ''); q = (Runde $m.q); e = $m.e
        normal = $normal; aktion = $aktion; at = $atext
        u = "https://www.lidl.at$($d.canonicalUrl)"
        b = $(if ($d.image) { [string]$d.image } else { $null })
        hs = $(if ($d.brand -and $d.brand.name) { [string]$d.brand.name } else { $null })
        av = $von; ab = $bis; vs = [bool]($von -and $von -gt $Heute)
        ea = $(if ($i.gridbox.meta -and $i.gridbox.meta.ean) { [string]$i.gridbox.meta.ean } else { $null })
    }
}
function Lidl-Namen($i) {
    $d = $i.gridbox.data
    $n = @(([string]$d.keyfacts.wonCategoryPrimary) -split '/' | Where-Object { $_ })
    if ($d.brand -and $d.brand.name) { $n += "Marke:$($d.brand.name)" }
    return $n
}

# ---------------------------------------------------------------- Hofer (Frischsortiment + Wochenangebote, ca. 1300 Artikel)
function Hofer-Euro([string]$Text) {
    # "EUR 9,99" -> 9.99
    $m = [regex]::Match($Text, '(\d+(?:[.,]\d+)?)')
    if (-not $m.Success) { return $null }
    return [double]::Parse($m.Groups[1].Value.Replace('.', '').Replace(',', '.'), $Inv)
}
function Hofer-Satz($p) {
    if (-not $p.price -or -not $p.price.amount) { return $null }
    $preis = $p.price.amount / 100
    $alt = Hofer-Euro ([string]$p.price.wasPriceDisplay)
    $normal = if ($alt -and $alt -gt $preis) { $alt } else { $preis }
    $aktion = if ($normal -gt $preis) { $preis } else { $null }
    $atext = $null
    if ($aktion) { $atext = $(if ($p.onSaleDateDisplay) { [string]$p.onSaleDateDisplay } else { 'Aktion' }) }
    # Menge aus dem Grundpreis ableiten: comparisonDisplay z. B. "EUR 0,99/100 g", comparison in Cent
    $m = @{ q = 1.0; e = 'stk' }; $g = ''
    $cm = [regex]::Match([string]$p.price.comparisonDisplay, '/\s*(\d+(?:[.,]\d+)?)\s*(kg|g|ml|cl|l)\b', 'IgnoreCase')
    if ($cm.Success -and $p.price.comparison) {
        $basis = Menge ([double]::Parse($cm.Groups[1].Value.Replace(',', '.'), $Inv)) $cm.Groups[2].Value
        $m = @{ q = ($p.price.amount / $p.price.comparison) * $basis.q; e = $basis.e }
    }
    $bild = $null
    if ($p.assets) { $bild = ([string]@($p.assets)[0].url).Replace('{width}', '500').Replace('{slug}', [string]$p.urlSlugText) }
    return [ordered]@{
        key = "hofer:$($p.sku)"; m = 'hofer'; n = ((@($p.brandName, $p.name) | Where-Object { $_ }) -join ' '); k = $null
        g = $g; q = (Runde $m.q); e = $m.e
        normal = $normal; aktion = $aktion; at = $atext
        u = "https://www.hofer.at/produkt/$($p.urlSlugText)-$($p.sku)"
        b = $bild; hs = $(if ($p.brandName) { [string]$p.brandName } else { $null })
        # Hofer nennt nur den Start ("Verfuegbar seit/ab"); Ende: solange der Vorrat reicht
        av = $(if ($p.onSaleDate) { ([string]$p.onSaleDate).Substring(0, 10) } else { $null }); ab = $null
        vs = [bool]($p.onSaleDate -and ([string]$p.onSaleDate).Substring(0, 10) -gt $Heute)
    }
}
function Hofer-Namen($p) {
    # Pseudo-Pfade: Shop-Kategorien, 'Alle', 'Alkohol' (laut Alkohol-Angabe) und 'Marke:<Marke>'
    $n = @('Alle')
    foreach ($c in @($p.categories)) { if ($c.name) { $n += [string]$c.name } }
    if ($p.alcohol) { $n += 'Alkohol' }
    if ($p.brandName) { $n += "Marke:$($p.brandName)" }
    return $n
}

# ---------------------------------------------------------------- Tchibo (nur Kategorie Kaffee, ca. 500 Artikel inkl. Varianten)
# Die Seite liefert alle Produkte im Nuxt-Datenblock ("devalue": ein grosses Array, Objekte verweisen per Index).
function Lies-GrossesJson([string]$Text) {
    if ($PSVersionTable.PSVersion.Major -ge 6) { return (ConvertFrom-Json -InputObject $Text -AsHashtable -NoEnumerate) }
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
    return $ser.DeserializeObject($Text)
}
function Hole-TchiboArtikel {
    $r = Invoke-WebRequest -Uri 'https://www.tchibo.at/categories/kaffee/kaffees?page=50&sort=relevance' -UseBasicParsing -UserAgent $UA -TimeoutSec 120
    $html = $Utf8.GetString($r.RawContentStream.ToArray())
    $m = [regex]::Match($html, '<script type="application/json"[^>]*>(.*?)</script>', 'Singleline')
    if (-not $m.Success) { throw 'Tchibo: kein Datenblock gefunden (Seitenaufbau geaendert?)' }
    $a = @(Lies-GrossesJson $m.Groups[1].Value)
    $n = $a.Count
    $W = { param($i) if ($null -ne $i -and $i -is [ValueType] -and -not ($i -is [bool])) { $k = [long]$i; if ($k -ge 0 -and $k -lt $n) { return $a[$k] } }; return $null }
    $liste = New-Object Collections.ArrayList; $gesehen = @{}
    foreach ($o in $a) {
        if (-not ($o -is [Collections.IDictionary])) { continue }
        if (-not ($o.ContainsKey('title') -and $o.ContainsKey('price') -and $o.ContainsKey('productViewUrl'))) { continue }
        $url = & $W $o['productViewUrl']
        $titel = & $W $o['title']
        $p = & $W $o['price']
        if (-not $url -or -not $titel -or -not ($p -is [Collections.IDictionary])) { continue }
        $id = [regex]::Match([string]$url, 'article_id=(\d+)').Groups[1].Value
        if (-not $id) { $id = [regex]::Match([string]$url, '/products/(\d+)').Groups[1].Value }
        if (-not $id -or $gesehen.ContainsKey($id)) { continue }
        $gesehen[$id] = $true
        $cur = & $W $p['current']; $old = & $W $p['old']; $base = & $W $p['base']
        if (-not $cur) { continue }
        $preis = [double]$cur / 100
        $normal = if ($old -and [double]$old / 100 -gt $preis) { [double]$old / 100 } else { $preis }
        $aktion = if ($normal -gt $preis) { $preis } else { $null }
        # Grundpreis ist je kg angegeben (Cent) -> Menge in kg
        $q = if ($base) { [double]$cur / [double]$base } else { 1.0 }
        $e = if ($base) { 'kg' } else { 'stk' }
        $bild = & $W $o['imageUrlMediumSize']
        # Tchibo liefert nur feste Groessen (64 und 900 px); die Adresse aus den Daten unveraendert uebernehmen
        if ($bild) { $bild = 'https://www.tchibo.at' + [string]$bild }
        $s = [ordered]@{
            key = "tchibo:$id"; m = 'tchibo'; n = [string]$titel; k = $null
            g = ''; q = (Runde $q); e = $e
            normal = $normal; aktion = $aktion; at = $(if ($aktion) { 'Aktion' } else { $null })
            u = 'https://www.tchibo.at' + [string]$url
            b = $bild; hs = 'Tchibo'
        }
        [void]$liste.Add(@{ s = $s; namen = @('Alle') })
    }
    Write-Host ("  tchibo gesamt: {0}" -f $liste.Count)
    return $liste
}

# ---------------------------------------------------------------- Gesamtsortiment je Markt (einmal alles laden)
# Ergebnis je Markt: Liste von @{ s = Satz; namen = Kategorie-Namen und -IDs/Slugs des Shops + 'Alle' }
$script:Roh = @{}

function Fuege-Hinzu($Tabelle, $Liste, $s, $Namen) {
    if ($Tabelle.ContainsKey($s.key)) {
        $x = $Tabelle[$s.key]
        foreach ($nm in $Namen) { if ($nm -and -not $x.namen.Contains([string]$nm)) { [void]$x.namen.Add([string]$nm) } }
        return
    }
    $nl = New-Object Collections.ArrayList
    [void]$nl.Add('Alle')
    foreach ($nm in $Namen) { if ($nm -and -not $nl.Contains([string]$nm)) { [void]$nl.Add([string]$nm) } }
    $x = @{ s = $s; namen = $nl }
    $Tabelle[$s.key] = $x
    [void]$Liste.Add($x)
}

function Rewe-Namen($p) {
    $n = New-Object Collections.ArrayList
    foreach ($pfad in @($p.parentCategories)) { foreach ($c in @($pfad)) { if ($c.name) { [void]$n.Add([string]$c.name) }; if ($c.slug) { [void]$n.Add([string]$c.slug) } } }
    return , $n
}

function Datum-Aus-Text([string]$TagMonat) {
    # "26.11" -> yyyy-MM-dd (Jahr so waehlen, dass das Datum nahe am heutigen liegt)
    $m = [regex]::Match($TagMonat, '(\d{1,2})\.(\d{1,2})')
    if (-not $m.Success) { return $null }
    $h = [DateTime]::ParseExact($Heute, 'yyyy-MM-dd', $Inv)
    try { $d = New-Object DateTime ($h.Year, [int]$m.Groups[2].Value, [int]$m.Groups[1].Value) } catch { return $null }
    if ($d -lt $h.AddDays(-200)) { $d = $d.AddYears(1) } elseif ($d -gt $h.AddDays(200)) { $d = $d.AddYears(-1) }
    return $d.ToString('yyyy-MM-dd')
}

function Penny-Zeitraeume($Alle) {
    # Penny: Pfad "Angebote ab 26.11" -> Start; Ende = Tag vor der naechsten Angebotswoche (sonst Start + 6 Tage).
    # "Monats-Deals November" -> bis Monatsende.
    $starts = New-Object Collections.Generic.SortedSet[string]
    foreach ($x in $Alle) { foreach ($nm in $x.namen) { if ($nm -match '^Angebote ab (\d{1,2}\.\d{1,2})') { $d = Datum-Aus-Text $Matches[1]; if ($d) { [void]$starts.Add($d) } } } }
    $liste = @($starts)
    foreach ($x in $Alle) {
        $s = $x.s
        if (-not $s.aktion) { continue }
        $start = $null; $monat = $false
        foreach ($nm in $x.namen) {
            if ($nm -match '^Angebote ab (\d{1,2}\.\d{1,2})') { $d = Datum-Aus-Text $Matches[1]; if ($d -and (-not $start -or $d -gt $start)) { $start = $d } }
            if ($nm -match '^Monats-Deals') { $monat = $true }
        }
        if (-not $start) { continue }
        $sd = [DateTime]::ParseExact($start, 'yyyy-MM-dd', $Inv)
        if ($monat) { $ende = (New-Object DateTime ($sd.Year, $sd.Month, 1)).AddMonths(1).AddDays(-1) }
        else {
            $naechster = $liste | Where-Object { $_ -gt $start } | Select-Object -First 1
            $ende = if ($naechster) { [DateTime]::ParseExact($naechster, 'yyyy-MM-dd', $Inv).AddDays(-1) } else { $sd.AddDays(6) }
        }
        $s.av = $start; $s.ab = $ende.ToString('yyyy-MM-dd')
        if ($start -gt $Heute) { $s.vs = $true }
    }
}

# Spar: Kategoriebaum bis zu den Blaettern; wird 7 Tage zwischengespeichert (spart ca. 200 Anfragen)
function Spar-Blaetter {
    $cache = Join-Path (Join-Path $Ordner 'daten') 'spar-kategorien.json'
    if (Test-Path $cache) {
        $c = Lies-Json $cache
        $alter = ([DateTime]::ParseExact($Heute, 'yyyy-MM-dd', $Inv) - [DateTime]::ParseExact([string]$c.stand, 'yyyy-MM-dd', $Inv)).TotalDays
        if ($alter -lt 30 -and @($c.blaetter).Count -gt 50) { return @($c.blaetter) }
    }
    $kopf = @{ Origin = 'https://www.spar.at'; Referer = 'https://www.spar.at/' }
    $blaetter = New-Object Collections.ArrayList
    $queue = New-Object Collections.Queue
    foreach ($w in 'lebensmittel', 'getraenke', 'drogerie-beauty', 'haushalt') { $queue.Enqueue(@{ id = $w; namen = @() }) }
    while ($queue.Count) {
        $k = $queue.Dequeue()
        $b = Hole-Json "https://api-scp.spar-ics.com/ecom/pw/v1/category/v1/at/breadcrumb/$($k.id)" $kopf 1500
        $letzt = @($b)[-1]
        $namen = @($k.namen) + @([string]$letzt.title, [string]$k.id)
        $kinder = @($letzt.childCategories | Where-Object { $_ })
        if (-not $kinder.Count) { [void]$blaetter.Add([ordered]@{ id = $k.id; namen = $namen }) }
        else { foreach ($c in $kinder) { $queue.Enqueue(@{ id = $c.categoryId; namen = $namen }) } }
    }
    [IO.File]::WriteAllText($cache, (ConvertTo-Json -InputObject ([ordered]@{ stand = $Heute; blaetter = $blaetter }) -Depth 5 -Compress), $Utf8)
    Write-Host ("  spar Kategoriebaum: {0} Blaetter" -f $blaetter.Count)
    return @($blaetter)
}

function Hole-Alles([string]$Markt) {
    if ($script:Roh.ContainsKey($Markt)) { return $script:Roh[$Markt] }
    $liste = New-Object Collections.ArrayList
    $tab = @{}
    if ($RohLesen) {
        # Rohdaten aus parallelen Abrufen (roh-<markt>.json bzw. roh-<markt>-<teil>.json) zusammenfuehren
        $muster = '^roh-' + [regex]::Escape($Markt) + '(-\d+)?\.json$'
        $dateien = @(Get-ChildItem -Path $RohLesen -Filter 'roh-*.json' -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $muster })
        if (-not $dateien.Count) { throw "Keine Rohdaten fuer $Markt in $RohLesen" }
        $soll = if ($Konfig.abruf -and $Konfig.abruf.teile -and $Konfig.abruf.teile.$Markt) { [int]$Konfig.abruf.teile.$Markt } else { 1 }
        if ($dateien.Count -lt $soll) { Melde-Teilfehler "$Markt`: erst $($dateien.Count) von $soll Teilen" ([pscustomobject]@{ Exception = [pscustomobject]@{ Message = 'Teil fehlt' } }) }
        foreach ($f in $dateien) {
            $daten = Lies-Json $f.FullName   # erst zuweisen: PS 5.1 liefert ein JSON-Array sonst als ein Objekt
            foreach ($x in $daten) {
                $s = [ordered]@{}
                foreach ($p in $x.s.PSObject.Properties) { $s[$p.Name] = $p.Value }
                Fuege-Hinzu $tab $liste $s @($x.namen)
            }
        }
        Write-Host ("  {0}: {1} Artikel aus {2} Rohdatei(en)" -f $Markt, $liste.Count, $dateien.Count)
        $script:Roh[$Markt] = $liste
        return $liste
    }
    switch ($Markt) {
        'billa' {
            $baum = Hole-Json 'https://shop.billa.at/api/product-discovery/categories/tree'
            foreach ($k in @($baum)) {
                if ($k.slug -match '^(neu-im-online-shop|treuepromotion|frisch-gekocht)') { continue }
                if ($Auslassen -and ($k.slug -match $Auslassen -or $k.name -match $Auslassen)) { Write-Host "  billa $($k.name): ausgelassen"; continue }
                try {
                    for ($seite = 0; $seite -lt 60; $seite++) {
                        $d = Hole-Json "https://shop.billa.at/api/product-discovery/categories/$($k.slug)/products?pageSize=500&page=$seite"
                        $res = @($d.results)
                        foreach ($p in $res) { $s = Rewe-Satz 'billa' 'https://shop.billa.at' $p $null; if ($s) { Fuege-Hinzu $tab $liste $s (Rewe-Namen $p) } }
                        if ($res.Count -lt 500) { break }
                    }
                } catch { Melde-Teilfehler "billa:$($k.slug)" $_ }
                Write-Host ("  billa {0}: bisher {1}" -f $k.name, $liste.Count)
            }
        }
        'penny' {
            for ($seite = 0; $seite -lt 40; $seite++) {
                $d = Hole-Json "https://www.penny.at/api/product-discovery/products?pageSize=500&page=$seite"
                $res = @($d.results)
                foreach ($p in $res) { $s = Rewe-Satz 'penny' 'https://www.penny.at' $p $null; if ($s) { Fuege-Hinzu $tab $liste $s (Rewe-Namen $p) } }
                if ($res.Count -lt 500) { break }
            }
            Penny-Zeitraeume $liste
            Write-Host ("  penny gesamt: {0}" -f $liste.Count)
        }
        'tchibo' {
            foreach ($x in (Hole-TchiboArtikel)) { Fuege-Hinzu $tab $liste $x.s @('Tchibo Kaffee') }
        }
        'hofer' {
            $offset = 0; $gesamt = 1
            while ($offset -lt $gesamt -and $offset -lt 20000) {
                $d = Hole-Json "https://asl.api.hofer.at/commerce/v3/product-search?currency=EUR&serviceType=walk-in&limit=60&offset=$offset&sort=relevance&servicePoint=A613"
                $gesamt = [int]$d.meta.pagination.totalCount
                foreach ($p in @($d.data)) { $s = Hofer-Satz $p; if ($s) { Fuege-Hinzu $tab $liste $s (Hofer-Namen $p) } }
                $offset += 60
            }
            Write-Host ("  hofer gesamt: {0} von {1}" -f $liste.Count, $gesamt)
        }
        'lidl' {
            $offset = 0; $gesamt = 1
            while ($offset -lt $gesamt -and $offset -lt 10000) {
                $d = Hole-Json "https://www.lidl.at/q/api/search?q=*&offset=$offset&fetchsize=60&assortment=AT&locale=de_AT&version=v2.0.0"
                $gesamt = [int]$d.numFound
                foreach ($i in @($d.items)) { $s = Lidl-Satz $i; if ($s) { Fuege-Hinzu $tab $liste $s (Lidl-Namen $i) } }
                $offset += 60
            }
            Write-Host ("  lidl gesamt: {0} von {1}" -f $liste.Count, $gesamt)
        }
        'spar' {
            $kopf = @{ Origin = 'https://www.spar.at'; Referer = 'https://www.spar.at/' }
            $blaetter = Spar-Blaetter
            $nr = 0
            foreach ($bl in $blaetter) {
                # Shop-Kategorien, die nicht mehr gebraucht werden (konfig.json abruf.auslassen), gar nicht erst abrufen
                if ($Auslassen -and ((@($bl.namen) -join ' / ') -match $Auslassen)) { continue }
                $nr++
                # Aufgeteilter Abruf: nur jede Teile-te Kategorie ab Teil
                if ($Teil -ge 0 -and (($nr - 1) % $Teile) -ne $Teil) { continue }
                try {
                    $seiten = 1
                    for ($seite = 1; $seite -le $seiten -and $seite -le 400; $seite++) {
                        $url = "https://api-scp.spar-ics.com/ecom/pw/v1/search/v1/navigation?query=*&sort=Relevancy:asc&page=$seite&hitsPerPage=32&marketId=8999&showPermutedSearchParams=false&filter=pwCategoryIds%3A$($bl.id)"
                        $d = Hole-Json $url $kopf 2500   # Spar (Cloudflare) sperrt nach ca. 60 schnellen Anfragen
                        $seiten = [int]$d.paging.pageCount
                        foreach ($h in @($d.hits)) { $s = Spar-Satz $h; if ($s) { Fuege-Hinzu $tab $liste $s @($bl.namen) } }
                    }
                } catch { Melde-Teilfehler "spar:$($bl.id)" $_ }
                if ($nr % 25 -eq 0) { Write-Host ("  spar {0}/{1} Kategorien, bisher {2} Artikel" -f $nr, $blaetter.Count, $liste.Count) }
            }
            Write-Host ("  spar gesamt: {0}" -f $liste.Count)
        }
        default { throw "Unbekannter Markt: $Markt" }
    }
    $script:Roh[$Markt] = $liste
    return $liste
}

# Ordnet alle Artikel eines Marktes den (Unter-)Kategorien zu. Erste passende Regel gewinnt.
# Regeln: Text = Shop-Kategorie (Name/ID/Slug), { kat|pfad, muster, ohne }, { pfadre: Regex auf Kategorienamen }.
# Je Unterkategorie gelten erst die Regeln des Marktes, dann die unter "alle". Rest -> "Sonstiges".
function Ordne-Zu([string]$Markt) {
    $alle = Hole-Alles $Markt
    $idx = @{}
    foreach ($x in $alle) {
        foreach ($nm in $x.namen) {
            $l = $idx[$nm]
            if (-not $l) { $l = New-Object Collections.ArrayList; $idx[$nm] = $l }
            [void]$l.Add($x)
        }
    }
    $namenListe = @($idx.Keys)
    $reCache = @{}
    $saetze = New-Object Collections.ArrayList
    $vergeben = @{}
    foreach ($kat in $Konfig.kategorien) {
        foreach ($uk in @($kat.unter)) {
            $regeln = @(@($uk.$Markt) + @($uk.alle)) | Where-Object { $_ }
            foreach ($regel in $regeln) {
                $muster = $null; $ohne = $null
                if ($regel -is [string]) { $quellen = @($regel) }
                else {
                    $muster = $regel.muster; $ohne = $regel.ohne
                    if ($regel.pfadre) {
                        $rk = [string]$regel.pfadre
                        if (-not $reCache.ContainsKey($rk)) { $reCache[$rk] = @($namenListe | Where-Object { [regex]::IsMatch($_, $rk, 'IgnoreCase') }) }
                        $quellen = $reCache[$rk]
                    }
                    elseif ($regel.kat) { $quellen = @([string]$regel.kat) }
                    else { $quellen = @([string]$regel.pfad) }
                }
                foreach ($q in $quellen) {
                    $l = $idx[$q]; if (-not $l) { continue }
                    foreach ($x in $l) {
                        $s = $x.s
                        if ($vergeben.ContainsKey($s.key)) { continue }
                        if ($muster -and -not [regex]::IsMatch($s.n, $muster, 'IgnoreCase')) { continue }
                        if ($ohne -and [regex]::IsMatch($s.n, $ohne, 'IgnoreCase')) { continue }
                        if ($kat.ohne -and [regex]::IsMatch($s.n, [string]$kat.ohne, 'IgnoreCase')) { continue }
                        # "und": zusaetzliche Bedingung an den Kategoriepfad (z. B. nur unter "Tiefkuehl")
                        $undRe = if ($regel -isnot [string] -and $regel.und) { [string]$regel.und } elseif ($uk.und) { [string]$uk.und } elseif ($kat.und) { [string]$kat.und } else { $null }
                        if ($undRe) { $ok = $false; foreach ($nm in $x.namen) { if ([regex]::IsMatch($nm, $undRe, 'IgnoreCase')) { $ok = $true; break } }; if (-not $ok) { continue } }
                        $vergeben[$s.key] = $true
                        if (Ist-Ausgeschlossen $s $x.namen) { continue }
                        $s.k = $kat.id; $s.uk = $uk.id
                        [void]$saetze.Add($s)
                    }
                }
            }
        }
    }
    # Rest: nichts passte -> Sonstiges
    foreach ($x in $alle) {
        $s = $x.s
        if ($vergeben.ContainsKey($s.key)) { continue }
        $vergeben[$s.key] = $true
        if (Ist-Ausgeschlossen $s $x.namen) { continue }
        $s.k = 'sonstiges'; $s.uk = 'rest'
        [void]$saetze.Add($s)
    }
    return $saetze
}


# ---------------------------------------------------------------- sparhamster.at (Deal-Tipps, nur Hinweise, keine Historie)
function Hole-Tipps {
    $tipps = New-Object Collections.ArrayList
    try {
        # Kategorie 8 = "Lebensmittel & Getraenke"
        $posts = Hole-Json 'https://www.sparhamster.at/wp-json/wp/v2/posts?categories=8&per_page=100&_fields=date,link,title'
        $ab = [DateTime]::ParseExact($Heute, 'yyyy-MM-dd', $Inv).AddDays(-14).ToString('yyyy-MM-dd')
        foreach ($p in @($posts)) {
            if ($p.date.Substring(0, 10) -lt $ab) { continue }
            $titel = [Net.WebUtility]::HtmlDecode([string]$p.title.rendered)
            foreach ($kat in $Konfig.kategorien) {
                if ($kat.tipps -and [regex]::IsMatch($titel, $kat.tipps, 'IgnoreCase')) {
                    [void]$tipps.Add([ordered]@{ quelle = 'sparhamster.at'; k = $kat.id; titel = $titel; u = $p.link; datum = $p.date.Substring(0, 10) })
                    break
                }
            }
        }
        Write-Host ("sparhamster.at: {0} passende Tipps" -f $tipps.Count)
    } catch { Melde-Teilfehler 'sparhamster' $_ }
    return $tipps
}

# ---------------------------------------------------------------- Abruf
# Ohne -Maerkte gilt die Liste aus konfig.json ("abruf.maerkte"); neue Shops nur dort ergaenzen
if (-not $PSBoundParameters.ContainsKey('Maerkte') -and $Konfig.abruf -and $Konfig.abruf.maerkte) {
    $Maerkte = @($Konfig.abruf.maerkte)
    # Beim Zusammenfuehren (GitHub) fehlen "nur lokal" abgerufene Maerkte - ihr Stand bleibt aus der Historie
    if ($RohLesen -and $Konfig.abruf.nur_lokal) { $Maerkte = @($Maerkte | Where-Object { @($Konfig.abruf.nur_lokal) -notcontains $_ }) }
}
$Maerkte = @($Maerkte | ForEach-Object { $_ -split '[,; ]+' } | Where-Object { $_ })   # "-File" liefert Listen als einen String

# Nur abrufen und Rohdaten schreiben (Teil eines parallelen Abrufs); Zuordnung und Historie macht der Zusammenfuehr-Lauf
if ($RohSchreiben) {
    [void](New-Item -ItemType Directory -Force $RohSchreiben)
    $fehlgeschlagen = 0
    foreach ($markt in $Maerkte) {
        Write-Host "Lade $markt ..."
        try {
            $l = Hole-Alles $markt
            $name = if ($Teil -ge 0) { "roh-$markt-$Teil.json" } else { "roh-$markt.json" }
            $zeilen = foreach ($x in $l) { ConvertTo-Json -InputObject ([ordered]@{ s = $x.s; namen = @($x.namen) }) -Compress -Depth 5 }
            [IO.File]::WriteAllText((Join-Path $RohSchreiben $name), '[' + (@($zeilen) -join ",`n") + "]`n", $Utf8)
            Write-Host ("  {0}: {1} Artikel -> {2}" -f $markt, $l.Count, $name)
            $script:Roh.Remove($markt)
        } catch {
            Write-Warning "$markt fehlgeschlagen: $($_.Exception.Message)"
            $fehlgeschlagen++
        }
    }
    # Spar-Kategoriebaum mitgeben, damit der Zusammenfuehr-Lauf ihn im Repo aktualisieren kann
    $baum = Join-Path (Join-Path $Ordner 'daten') 'spar-kategorien.json'
    if ($Maerkte -contains "spar" -and $Teil -le 0 -and (Test-Path $baum)) { Copy-Item $baum (Join-Path $RohSchreiben 'spar-kategorien.json') -Force }
    if ($script:Teilfehler.Count) { Write-Warning ("Teilfehler: " + ($script:Teilfehler -join ', ')) }
    if ($fehlgeschlagen -eq $Maerkte.Count) { throw 'Kein Markt geladen.' }
    return
}

# Im Zusammenfuehr-Lauf den mitgelieferten Spar-Kategoriebaum uebernehmen
if ($RohLesen) {
    $baum = @(Get-ChildItem -Path $RohLesen -Filter 'spar-kategorien.json' -File -Recurse -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($baum) { Copy-Item $baum.FullName (Join-Path (Join-Path $Ordner 'daten') 'spar-kategorien.json') -Force }
}

# Kategorien mit "weglassen": true werden zwar zugeordnet (damit die Artikel nicht unter Sonstiges landen), aber nicht gespeichert
$Weglassen = @{}
foreach ($kat in @($Konfig.kategorien)) { if ($kat.weglassen) { $Weglassen[[string]$kat.id] = $true } }
$neu = @{}
$fehler = @()
foreach ($markt in $Maerkte) {
    Write-Host "Lade $markt ..."
    try {
        $saetze = Ordne-Zu $markt
        $script:Roh.Remove($markt)   # Rohdaten freigeben (Speicher)
        foreach ($s in $saetze) { if ($s.k -and $Weglassen.ContainsKey([string]$s.k)) { continue }; if (-not $neu.ContainsKey($s.key)) { $neu[$s.key] = $s } }
        Write-Host ("  {0}: {1} Artikel" -f $markt, @($saetze).Count)
    } catch {
        Write-Warning "$markt fehlgeschlagen: $($_.Exception.Message)"
        $fehler += $markt
    }
}
$tipps = @(Hole-Tipps)

# Gueltigkeitszeitraum der aktuellen Flugblaetter (wogibtswas.at liefert SaleEvent mit startDate/endDate)
$flugblaetter = New-Object Collections.ArrayList
if ($Konfig.flugblaetter) {
    foreach ($eig in $Konfig.flugblaetter.PSObject.Properties) {
        if ($eig.Name -like '_*') { continue }
        foreach ($url in @($eig.Value)) {
            try {
                $r = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $UA -TimeoutSec 60
                $html = $Utf8.GetString($r.RawContentStream.ToArray())
                foreach ($m in [regex]::Matches($html, '"@type":"SaleEvent","name":"(?<name>[^"]*)".*?"url":"(?<url>[^"]*)","startDate":"(?<von>\d{4}-\d{2}-\d{2})[^"]*","endDate":"(?<bis>\d{4}-\d{2}-\d{2})')) {
                    $von = $m.Groups['von'].Value; $bis = $m.Groups['bis'].Value
                    if ($von -gt $Heute -or $bis -lt $Heute) { continue }   # nur aktuell gueltige
                    [void]$flugblaetter.Add([ordered]@{ m = $eig.Name; name = [regex]::Unescape($m.Groups['name'].Value); von = $von; bis = $bis; u = $m.Groups['url'].Value.Replace('\/', '/') })
                }
            } catch { Melde-Teilfehler "flugblatt:$($eig.Name)" $_ }
        }
    }
    Write-Host ("Flugblaetter: {0} aktuell gueltig" -f $flugblaetter.Count)
}
$fehler += $script:Teilfehler
if ($neu.Count -eq 0) { throw 'Kein einziger Artikel geladen - Abbruch, Historie bleibt unveraendert.' }

# ---------------------------------------------------------------- Historie fortschreiben
# Eintrag: m Markt, n Name, k Kategorie, g Packung (Text), q Menge, e Einheit, u Link, b Bild, hs Hersteller/Marke, ea EAN (nur Lidl),
#          a zuerst gesehen, z zuletzt gesehen, p Preispunkte [Datum, Normalpreis, Aktionspreis|null, Menge, Aktionstext|null]
$hist = [ordered]@{}
if (Test-Path $HistDatei) {
    $alt = Lies-Json $HistDatei
    foreach ($eig in $alt.PSObject.Properties) {
        $o = $eig.Value
        $punkte = New-Object Collections.ArrayList
        foreach ($pt in @($o.p)) { [void]$punkte.Add(@($pt)) }
        $hist[$eig.Name] = [ordered]@{ m = $o.m; n = $o.n; k = $o.k; uk = $o.uk; g = $o.g; q = $o.q; e = $o.e; u = $o.u; b = $o.b; hs = $o.hs; ea = $o.ea; a = $o.a; z = $o.z; av = $o.av; ab = $o.ab; vp = $o.vp; p = $punkte }
    }
}

$neuePunkte = 0; $neueArtikel = 0
foreach ($s in $neu.Values) {
    # Angebote, die erst kuenftig gelten ("ab 26.11."), sind noch keine Aktion: nur als Vorschau (vp) merken
    $vorschau = [bool]$s.vs
    $aktionHeute = if ($vorschau) { $null } else { $s.aktion }
    $punkt = @($Heute, (Runde $s.normal), (Runde $aktionHeute), $s.q, $(if ($aktionHeute) { $s.at } else { $null }))
    $av = $s.av; $ab = $s.ab; $vp = $(if ($vorschau) { Runde $s.aktion } else { $null })
    if (-not $hist.Contains($s.key)) {
        $hist[$s.key] = [ordered]@{ m = $s.m; n = $s.n; k = $s.k; uk = $s.uk; g = $s.g; q = $s.q; e = $s.e; u = $s.u; b = $s.b; hs = $s.hs; ea = $s.ea; a = $Heute; z = $Heute; av = $av; ab = $ab; vp = $vp; p = (New-Object Collections.ArrayList) }
        [void]$hist[$s.key].p.Add($punkt); $neueArtikel++; continue
    }
    $h = $hist[$s.key]
    $h.n = $s.n; $h.k = $s.k; $h.uk = $s.uk; $h.g = $s.g; $h.q = $s.q; $h.e = $s.e; $h.u = $s.u; $h.b = $s.b; if ($s.hs) { $h.hs = $s.hs }; if ($s.ea) { $h.ea = $s.ea }; $h.z = $Heute
    $h.av = $av; $h.ab = $ab; $h.vp = $vp
    $letzt = $h.p[$h.p.Count - 1]
    $gleich = ([double]$letzt[1] -eq [double]$punkt[1]) -and ("$($letzt[2])" -eq "$($punkt[2])") -and ([double]$letzt[3] -eq [double]$punkt[3])
    if (-not $gleich) {
        if ($letzt[0] -eq $Heute) { $h.p[$h.p.Count - 1] = $punkt } else { [void]$h.p.Add($punkt) }
        $neuePunkte++
    }
}

# Ausgeblendete und lange verschwundene Artikel entfernen
$grenze = [DateTime]::ParseExact($Heute, 'yyyy-MM-dd', $Inv).AddDays(-$TageBehalten).ToString('yyyy-MM-dd')
# Maerkte, die heute komplett ohne Fehler geladen wurden
$vollstaendig = @{}
foreach ($markt in $Maerkte) {
    if (-not ($fehler | Where-Object { $_ -eq $markt -or $_ -like "$markt`:*" })) { $vollstaendig[$markt] = $true }
}
$entfernt = 0
foreach ($key in @($hist.Keys)) {
    $e = $hist[$key]
    if ($Ausgeblendet.ContainsKey($key) -or $e.z -lt $grenze -or ($e.k -and $Weglassen.ContainsKey([string]$e.k))) { $hist.Remove($key); continue }
    # Erst heute angelegt, beim jetzigen vollstaendigen Abruf aber nicht mehr zugeordnet
    # (z. B. nach einer Regelaenderung in konfig.json): wieder entfernen
    if ($e.a -eq $Heute -and $vollstaendig.ContainsKey($e.m) -and -not $neu.ContainsKey($key)) { $hist.Remove($key); $entfernt++ }
}
if ($entfernt) { Write-Host "Heute angelegte, nicht mehr passende Artikel entfernt: $entfernt" }

# Eine Zeile je Artikel, damit Git-Diffs klein und lesbar bleiben.
# Die JSON-Texte je Artikel werden einmal erzeugt und auch fuer die Seite wiederverwendet.
$ej = @{}
$zeilen = New-Object Collections.Generic.List[string]
foreach ($key in ($hist.Keys | Sort-Object)) {
    $j = ConvertTo-Json -InputObject $hist[$key] -Compress -Depth 5
    $ej[$key] = $j
    $zeilen.Add((ConvertTo-Json -InputObject $key -Compress) + ':' + $j)
}
[void](New-Item -ItemType Directory -Force (Split-Path $HistDatei))
[IO.File]::WriteAllText($HistDatei, "{`n" + ($zeilen -join ",`n") + "`n}`n", $Utf8)
Write-Host ("Historie: {0} Artikel, {1} neu, {2} Preisaenderungen" -f $hist.Count, $neueArtikel, $neuePunkte)

# ---------------------------------------------------------------- Dateien fuer die Seite (site/daten/)
# index.js     Uebersicht: Stand, Maerkte, Kategorien mit Anzahl, Schwellen, Tipps
# angebote.js  alle Artikel mit laufender oder kommender Aktion (inkl. Verlauf)
# suche.js     kompakter Suchindex aller Artikel [id, Name, Markt, Kat, Unterkat, Preis, Aktionspreis, Menge, Einheit, Hersteller, EAN (nur Lidl)]
# kat-<id>.js  alle Artikel einer Kategorie (inkl. Verlauf)
# Format: PT_LADE("<name>", <daten>); - funktioniert auch direkt von der Festplatte (file://)
$ausOrdner = Join-Path (Join-Path $Ordner 'site') 'daten'
[void](New-Item -ItemType Directory -Force $ausOrdner)
Get-ChildItem $ausOrdner -Filter '*.js' -ErrorAction SilentlyContinue | Remove-Item -Force
$abAnzeige = [DateTime]::ParseExact($Heute, 'yyyy-MM-dd', $Inv).AddDays(-$TageAnzeigen).ToString('yyyy-MM-dd')
function Artikel-Json([string]$Key) { return '{"id":' + (ConvertTo-Json -InputObject $Key -Compress) + ',' + $ej[$Key].Substring(1) }
function Schreibe-Js([string]$Name, [string]$Json) {
    $text = 'PT_LADE(' + (ConvertTo-Json -InputObject $Name -Compress) + ',' + $Json + ");`n"
    [IO.File]::WriteAllText((Join-Path $ausOrdner "$Name.js"), $text, $Utf8)
    return $text.Length
}
$jeKat = @{}; $angebote = New-Object Collections.Generic.List[string]; $suche = New-Object Collections.Generic.List[string]
$anzahl = @{}; $anzahlUk = @{}; $anzahlAkt = @{}; $anzahlAktUk = @{}
foreach ($key in $hist.Keys) {
    $h = $hist[$key]
    if ($h.z -lt $abAnzeige) { continue }
    $k = if ($h.k) { [string]$h.k } else { 'sonstiges' }
    if (-not $jeKat.ContainsKey($k)) { $jeKat[$k] = New-Object Collections.Generic.List[string] }
    $aj = Artikel-Json $key
    $jeKat[$k].Add($aj)
    $anzahl[$k] = 1 + [int]$anzahl[$k]
    $ukKey = "$k/$($h.uk)"; $anzahlUk[$ukKey] = 1 + [int]$anzahlUk[$ukKey]
    $lp = $h.p[$h.p.Count - 1]
    $inAktion = ($null -ne $lp[2]) -and ($h.z -eq $Heute)
    if ($inAktion -or $h.vp) { $angebote.Add($aj); $anzahlAkt[$k] = 1 + [int]$anzahlAkt[$k]; $anzahlAktUk[$ukKey] = 1 + [int]$anzahlAktUk[$ukKey] }
    $suche.Add((ConvertTo-Json -InputObject @($key, $h.n, $h.m, $k, $h.uk, $lp[1], $lp[2], $h.q, $h.e, $h.hs, $h.ea) -Compress))
}
$groesse = 0
foreach ($k in $jeKat.Keys) { $groesse += Schreibe-Js "kat-$k" ('[' + ($jeKat[$k] -join ',') + ']') }
$groesse += Schreibe-Js 'angebote' ('[' + ($angebote -join ',') + ']')
$groesse += Schreibe-Js 'suche' ('[' + ($suche -join ',') + ']')

$katListe = New-Object Collections.ArrayList
# Anzeigereihenfolge laut "pos" (Pruefreihenfolge bleibt die Reihenfolge in konfig.json)
foreach ($kat in @($Konfig.kategorien | Sort-Object { if ($_.pos) { [int]$_.pos } else { 500 } })) {
    if ($kat.weglassen) { continue }
    $unter = @($kat.unter | ForEach-Object { [ordered]@{ id = $_.id; name = $_.name; n = [int]$anzahlUk["$($kat.id)/$($_.id)"]; na = [int]$anzahlAktUk["$($kat.id)/$($_.id)"] } })
    [void]$katListe.Add([ordered]@{ id = $kat.id; name = $kat.name; n = [int]$anzahl[$kat.id]; na = [int]$anzahlAkt[$kat.id]; unter = $unter })
}
$index = [ordered]@{
    stand      = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    heute      = $Heute
    fehler     = $fehler
    maerkte    = @([ordered]@{ id = 'billa'; name = 'Billa' }, [ordered]@{ id = 'penny'; name = 'Penny' }, [ordered]@{ id = 'hofer'; name = 'Hofer' }, [ordered]@{ id = 'lidl'; name = 'Lidl' }, [ordered]@{ id = 'spar'; name = 'Spar' }, [ordered]@{ id = 'tchibo'; name = 'Tchibo' })
    kategorien = $katListe
    auswertung = $Konfig.auswertung
    tipps      = $tipps
    flugblaetter = $flugblaetter
    gesamt     = $suche.Count
    angebote   = $angebote.Count
}
$groesse += Schreibe-Js 'index' (ConvertTo-Json -InputObject $index -Compress -Depth 6)
Write-Host ("Seite: {0} Artikel, {1} Angebote, {2} Kategorie-Dateien, zusammen {3:N1} MB" -f $suche.Count, $angebote.Count, $jeKat.Count, ($groesse / 1MB))
if ($fehler.Count) { Write-Warning ("Nicht geladen: " + ($fehler -join ', ')) }
