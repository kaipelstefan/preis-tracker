// Strichcode-Scanner: EAN mit der Handykamera lesen und den Preis im Geschaeft bewerten.
// Zuordnung EAN -> Artikel: 1. eigene, gemerkte Zuordnung (Server), 2. Lidl liefert EANs mit,
// 3. Open Food Facts (Marke, Name, Menge) + Abgleich mit den eigenen Artikeln, Auswahl wird gemerkt.
(function () {
'use strict';
// window.PT entsteht erst, wenn die Daten geladen sind: so lange warten
if (!window.PT) { var versuche = 0, warte = setInterval(function () { if (window.PT || ++versuche > 600) { clearInterval(warte); if (window.PT) start(); } }, 200); } else start();
function start() {
var PT = window.PT;
var $ = function (id) { return document.getElementById(id); };
var esc = PT.esc, euro = PT.euro;
var lokal = location.protocol === 'file:';
var LIB = 'https://cdnjs.cloudflare.com/ajax/libs/html5-qrcode/2.3.8/html5-qrcode.min.js';

var css = document.createElement('style');
css.textContent = [
  '.scan-knopf { margin-left: auto; font-weight: 600; }',
  '.scan-kamera { width: 100%; max-width: 460px; aspect-ratio: 4 / 3; background: #000; border-radius: 12px; overflow: hidden; margin: 10px 0 6px; position: relative; }',
  '.scan-kamera video { width: 100% !important; height: 100% !important; object-fit: cover; }',
  '.scan-kamera[hidden] { display: none; }',
  '.scan-status { color: var(--leise); font-size: 13px; margin: 4px 0 10px; }',
  '.scan-form { display: flex; gap: 8px; margin: 6px 0 12px; }',
  '.scan-form input { flex: 1; min-width: 0; border: 1px solid var(--linie); background: var(--fl); border-radius: 8px; padding: 9px 10px; font-size: 16px; }',
  '.scan-form button, .scan-knopf2 { border: 1px solid var(--akzent); background: var(--akzent); color: #fff; border-radius: 8px; padding: 8px 14px; cursor: pointer; font-weight: 600; }',
  '.scan-produkt { background: var(--bg); border-radius: 10px; padding: 8px 12px; margin: 8px 0; font-size: 14px; }',
  '.scan-liste { list-style: none; margin: 8px 0; padding: 0; display: grid; gap: 6px; }',
  '.scan-liste li { border: 1px solid var(--linie); border-radius: 10px; padding: 8px 10px; display: grid; grid-template-columns: 1fr auto; gap: 4px 10px; align-items: center; }',
  '.scan-liste .nm { font-weight: 600; font-size: 14px; overflow-wrap: anywhere; }',
  '.scan-liste .mt { color: var(--leise); font-size: 12px; display: flex; gap: 6px; flex-wrap: wrap; align-items: center; grid-column: 1; }',
  '.scan-liste button { grid-row: 1 / span 2; grid-column: 2; }',
  '.scan-banner { background: var(--bg); border-radius: 8px; padding: 6px 10px; font-size: 12px; color: var(--leise); margin: 0 0 8px; display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }',
  '.scan-banner button { border: 0; background: none; color: var(--akzent); cursor: pointer; font-size: 12px; padding: 0; }'
].join('\n');
document.head.appendChild(css);

var knopf = document.createElement('button');
knopf.className = 'chip scan-knopf'; knopf.id = 'scan-knopf'; knopf.type = 'button';
knopf.textContent = '📷 Scannen'; knopf.title = 'Strichcode (EAN) im Geschäft scannen';
document.querySelector('.titel').appendChild(knopf);

// ------------------------------------------------------------------ Kamera
var scanner = null, libLaden = null;
function ladeLib() {
  if (window.Html5Qrcode) return Promise.resolve();
  if (libLaden) return libLaden;
  libLaden = new Promise(function (ok, fehler) {
    var s = document.createElement('script'); s.src = LIB; s.onload = ok;
    s.onerror = function () { libLaden = null; fehler(new Error('Scanner konnte nicht geladen werden')); };
    document.head.appendChild(s);
  });
  return libLaden;
}
function stoppe() {
  if (!scanner) return;
  var s = scanner; scanner = null;
  try { s.stop().then(function () { try { s.clear(); } catch (e) {} }, function () {}); } catch (e) {}
}
window.PT_SCAN_STOPP = stoppe;

function starteKamera() {
  var box = $('scan-kamera'); if (!box) return;
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || !window.isSecureContext) {
    box.hidden = true; status('Kamera ist hier nicht verfügbar – EAN bitte eintippen.'); return;
  }
  status('Kamera wird gestartet …');
  ladeLib().then(function () {
    if (!$('scan-kamera')) return;   // Fenster inzwischen geschlossen
    var F = window.Html5QrcodeSupportedFormats;
    scanner = new window.Html5Qrcode('scan-kamera', { verbose: false,
      formatsToSupport: [F.EAN_13, F.EAN_8, F.UPC_A, F.UPC_E],
      experimentalFeatures: { useBarCodeDetectorIfSupported: true } });
    return scanner.start({ facingMode: 'environment' }, { fps: 12, qrbox: function (w, h) { return { width: Math.round(w * 0.85), height: Math.round(h * 0.45) }; } },
      function (code) { if (gueltig(code)) { if (navigator.vibrate) navigator.vibrate(60); stoppe(); $('scan-kamera').hidden = true; sucheEan(code); } },
      function () {});
  }).then(function () { if (scanner) status('Strichcode in den Rahmen halten …'); })
    .catch(function (e) {
      if ($('scan-kamera')) $('scan-kamera').hidden = true;
      status((/Permission|NotAllowed/i.test(String(e)) ? 'Kamera-Zugriff wurde nicht erlaubt.' : 'Kamera nicht verfügbar.') + ' EAN bitte eintippen.');
      scanner = null;
    });
}
function status(t) { if ($('scan-status')) $('scan-status').textContent = t; }

// EAN-8/12/13 mit Pruefziffer
function gueltig(c) {
  c = String(c).replace(/\D/g, '');
  if (!/^(\d{8}|\d{12}|\d{13})$/.test(c)) return false;
  var s = 0, n = c.length;
  for (var i = 0; i < n - 1; i++) s += (+c[n - 2 - i]) * (i % 2 === 0 ? 3 : 1);
  return (10 - s % 10) % 10 === +c[n - 1];
}

// ------------------------------------------------------------------ Fenster
function oeffneScanner(ohneKamera) {
  PT.zeigeBlatt('<button class="zu" id="zu" aria-label="Schließen">×</button><h2>📷 Strichcode scannen</h2>' +
    '<div id="scan-kamera" class="scan-kamera"></div><div class="scan-status" id="scan-status"></div>' +
    '<form class="scan-form" id="scan-form"><input id="scan-ean" inputmode="numeric" autocomplete="off" placeholder="oder EAN eintippen (8 oder 13 Ziffern)" aria-label="EAN"><button>Suchen</button></form>' +
    '<div id="scan-ergebnis"></div>');
  $('zu').onclick = PT.schliesse;
  $('scan-form').onsubmit = function (ev) {
    ev.preventDefault();
    var c = $('scan-ean').value.replace(/\D/g, '');
    if (!gueltig(c)) { status('Das ist keine gültige EAN (Prüfziffer passt nicht).'); return; }
    stoppe(); $('scan-kamera').hidden = true; sucheEan(c);
  };
  PT.ladeSuche();   // Suchindex schon im Hintergrund laden
  if (ohneKamera === true) $('scan-kamera').hidden = true; else starteKamera();
}
knopf.onclick = function () { oeffneScanner(); };

function holeEan(ean) {
  if (lokal) return Promise.resolve({ ids: [], produkt: null });
  return fetch('api/ean.php?ean=' + encodeURIComponent(ean), { credentials: 'same-origin' })
    .then(function (r) { return r.json(); })
    .catch(function () { return { ids: [], produkt: null, fehler: 'Server nicht erreichbar' }; });
}
function merkeEan(ean, id, loeschen) {
  if (lokal) return Promise.resolve();
  return fetch('api/ean.php', { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ean: ean, id: id, loeschen: loeschen ? 1 : 0 }) }).catch(function () {});
}

function sucheEan(ean) {
  status('EAN ' + ean + ' wird gesucht …');
  $('scan-ean').value = ean;
  Promise.all([PT.ladeSuche(), holeEan(ean)]).then(function (x) {
    var S = x[0], antw = x[1] || {};
    if (!$('scan-ergebnis')) return;
    var ids = (antw.ids || []).filter(function (id) { return PT.SUCHE_ID[id]; });
    // Lidl liefert EANs mit (Feld 10 im Suchindex)
    var kurz = ean.replace(/^0+/, '');
    S.forEach(function (z) { if (z[10] && String(z[10]).replace(/^0+/, '') === kurz && ids.indexOf(z[0]) < 0) ids.push(z[0]); });
    if (ids.length) { zeigeArtikel(ean, ids[0], true); return; }
    var p = antw.produkt;
    var h = '';
    if (p && p.gefunden) h += '<div class="scan-produkt"><b>' + esc(p.name || 'Unbekannter Name') + '</b>' + (p.marke ? ' · ' + esc(p.marke) : '') + (p.menge ? ' · ' + esc(p.menge) : '') + '<br><small>laut Open Food Facts</small></div>';
    else h += '<div class="scan-produkt">EAN ' + esc(ean) + ' ist ' + (antw.fehler || (p && p.fehler) ? 'gerade nicht abrufbar' : 'in Open Food Facts nicht bekannt') + '. Bitte den Artikel unten suchen.</div>';
    var kand = p && p.gefunden ? kandidaten(S, p) : [];
    h += kand.length ? '<h3 style="font-size:14px;margin:12px 0 4px">Welcher Artikel ist es?</h3>' + listeHtml(kand) : (p && p.gefunden ? '<p class="scan-status">Kein passender Artikel gefunden.</p>' : '');
    h += '<form class="scan-form" id="scan-such"><input id="scan-text" autocomplete="off" placeholder="Artikel suchen, z. B. milka alpenmilch" value="' + esc(p && p.gefunden ? [p.marke && p.marke.split(',')[0], p.name].filter(Boolean).join(' ') : '') + '"><button>Suchen</button></form><div id="scan-such-ergebnis"></div>';
    $('scan-ergebnis').innerHTML = h;
    status(kand.length ? 'Tippe auf den richtigen Artikel – die Zuordnung wird für den nächsten Scan gemerkt.' : '');
    $('scan-such').onsubmit = function (ev) { ev.preventDefault(); $('scan-such-ergebnis').innerHTML = listeHtml(textSuche(S, $('scan-text').value)) || '<p class="scan-status">Nichts gefunden.</p>'; };
    $('scan-ergebnis').onclick = function (ev) {
      var b = ev.target.closest('[data-wahl]'); if (!b) return;
      merkeEan(ean, b.dataset.wahl).then(function () { zeigeArtikel(ean, b.dataset.wahl, false); });
    };
  });
}

// Gescannten Artikel zeigen (Detail mit Bewertung, Preisvergleich und Regalpreis-Feld)
function zeigeArtikel(ean, id, gemerkt) {
  Promise.resolve(PT.oeffne(id)).then(function () {
    var blatt = $('blatt'), h2 = blatt && blatt.querySelector('h2'); if (!h2) return;
    var d = document.createElement('div'); d.className = 'scan-banner';
    d.innerHTML = '<span>📷 EAN ' + esc(ean) + (gemerkt ? ' · gemerkte Zuordnung' : ' · Zuordnung gemerkt') + '</span><button type="button" id="scan-falsch">Falscher Artikel?</button><button type="button" id="scan-neu">Nächsten scannen</button>';
    h2.parentNode.insertBefore(d, h2);
    $('scan-falsch').onclick = function () { merkeEan(ean, id, true).then(function () { oeffneScanner(true); sucheEan(ean); }); };
    $('scan-neu').onclick = function () { oeffneScanner(); };
    var f = $('regal-preis'); if (f) f.focus({ preventScroll: true });
  });
}

// ------------------------------------------------------------------ Abgleich Open Food Facts -> eigene Artikel
function menge(text) {
  var m = /(?:(\d+)\s*[x×]\s*)?(\d+(?:[.,]\d+)?)\s*(kg|g|ml|cl|l)\b/i.exec(text || '');
  if (!m) return null;
  var z = parseFloat(m[2].replace(',', '.')) * (m[1] ? +m[1] : 1), e = m[3].toLowerCase();
  if (e === 'g') return { q: z / 1000, e: 'kg' }; if (e === 'kg') return { q: z, e: 'kg' };
  if (e === 'ml') return { q: z / 1000, e: 'l' }; if (e === 'cl') return { q: z / 100, e: 'l' }; return { q: z, e: 'l' };
}
function kandidaten(S, p) {
  var marken = String(p.marke || '').split(',').map(function (b) { return PT.vglWoerter(b); }).filter(function (w) { return w.length; });
  var mq = menge(p.menge) || menge(p.name);
  var nameW = PT.vglWoerter(p.name || '').filter(function (t) { return !/^\d+$/.test(t); });
  var liste = [];
  S.forEach(function (z) {
    var w = PT.vglWoerter(z[1] + ' ' + (z[9] || ''));
    var marke = marken.some(function (bw) { return bw.every(function (t) { return w.indexOf(t) >= 0; }); });
    var mengeOk = mq && z[8] === mq.e && Math.abs(z[7] - mq.q) <= mq.q * 0.03;
    var treffer = nameW.filter(function (t) { return w.indexOf(t) >= 0; }).length;
    var nameS = nameW.length ? treffer / nameW.length : 0;
    if (!marke && nameS < 0.5) return;
    // Zusatzwoerter (Sorte, Edition) im Artikelnamen kosten etwas: der schlichte Artikel kommt zuerst
    var bekannt = nameW.concat.apply(nameW, marken);
    var extra = PT.vglWoerter(z[1]).filter(function (t) { return !/^\d+$/.test(t) && bekannt.indexOf(t) < 0; }).length;
    var punkte = (marke ? 3 : 0) + (mengeOk ? 2.5 : (mq ? -1 : 0)) + 2 * nameS - Math.min(1.5, 0.3 * extra);
    if (punkte < 3) return;
    liste.push({ z: z, p: punkte });
  });
  liste.sort(function (a, b) { return b.p - a.p; });
  return gruppiert(liste.map(function (x) { return x.z; })).slice(0, 8);
}
function textSuche(S, text) {
  var q = PT.vglWoerter(text); if (!q.length) return [];
  var l = S.filter(function (z) { var w = PT.vglWoerter(z[1] + ' ' + (z[9] || '')); return q.every(function (t) { return w.some(function (x) { return x.indexOf(t) === 0; }); }); });
  l.sort(function (a, b) { return PT.vglWoerter(a[1]).length - PT.vglWoerter(b[1]).length; });   // schlichteste Namen zuerst
  return gruppiert(l.slice(0, 300)).slice(0, 12);
}
// je Ware (gleicher Artikel in mehreren Maerkten) nur eine Zeile
function gruppiert(zeilen) {
  var gesehen = {}, aus = [];
  zeilen.forEach(function (z) {
    var g = PT.gruppe(z[0]), key = g ? g.slice().sort()[0] : z[0];
    if (gesehen[key]) return; gesehen[key] = 1;
    aus.push({ z: z, ids: g || [z[0]] });
  });
  return aus;
}
function listeHtml(l) {
  if (!l.length) return '';
  return '<ul class="scan-liste">' + l.map(function (k) {
    var z = k.z, maerkte = k.ids.map(function (id) { var r = PT.SUCHE_ID[id]; return r ? r[2] : null; }).filter(Boolean);
    maerkte = maerkte.filter(function (m, i) { return maerkte.indexOf(m) === i; });
    var preis = z[6] != null ? z[6] : z[5];
    return '<li><div class="nm">' + esc(z[1]) + '</div><div class="mt">' + maerkte.map(function (m) { return '<span class="markt m-' + esc(m) + '">' + esc(PT.MARKTNAME[m] || m) + '</span>'; }).join('') +
      '<span>' + PT.packung(z[7], z[8]) + '</span><span>' + euro(preis) + '</span></div><button class="scan-knopf2" data-wahl="' + esc(z[0]) + '">Das ist er</button></li>';
  }).join('') + '</ul>';
}
window.PT_SCAN_TEST = { kandidaten: kandidaten, gueltig: gueltig, menge: menge };
}
})();
