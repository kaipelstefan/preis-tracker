// Einkaeufe: Rechnungen hochladen, Auswertung ansehen, Ersparnis gesamt, eigene Kaeufe im Artikel-Detail.
// Braucht den Server (PHP + MySQL unter api/). Lokal (file://) wird nur ein Hinweis gezeigt.
(function () {
'use strict';
var API = 'api/';
var $ = function (id) { return document.getElementById(id); };
var lokal = location.protocol === 'file:';
var euroF = new Intl.NumberFormat('de-AT', { style: 'currency', currency: 'EUR' });
function euro(x) { return x == null || !isFinite(x) ? '–' : euroF.format(x); }
function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
function datum(s) { if (!s) return '–'; var p = String(s).slice(0, 10).split('-'); return p[2] + '.' + p[1] + '.' + p[0].slice(2); }
var MARKT = { billa: 'Billa', penny: 'Penny', hofer: 'Hofer', lidl: 'Lidl', spar: 'Spar', tchibo: 'Tchibo', bipa: 'BIPA' };
function marktHtml(m) { return m ? '<span class="markt m-' + esc(m) + '">' + esc(MARKT[m] || m) + '</span>' : ''; }
function holeJson(url, opt) {
  return fetch(API + url, Object.assign({ credentials: 'same-origin' }, opt || {})).then(function (r) {
    return r.json().catch(function () { return { fehler: 'Antwort ' + r.status }; }).then(function (j) { if (!r.ok || j.fehler) throw new Error(j.fehler || ('HTTP ' + r.status)); return j; });
  });
}

// ------------------------------------------------------------------ Stil
var css = document.createElement('style');
css.textContent = [
  '#einkaeufe { max-width: 980px; margin: 0 auto; padding: 8px 16px 40px; }',
  '.ek-karte { background: var(--fl); border: 1px solid var(--linie); border-radius: 10px; padding: 12px; margin-bottom: 10px; }',
  '.ek-summen { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 8px; }',
  '.ek-summen .kz b { font-size: 20px; }',
  '.ek-upload { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }',
  '.ek-upload label.knopf { border: 1px solid var(--akzent); background: var(--akzent); color: #fff; border-radius: 8px; padding: 8px 14px; cursor: pointer; font-weight: 600; }',
  '.ek-upload input[type=file] { display: none; }',
  '.scan-liste.mit-bild li { grid-template-columns: 52px 1fr auto; }',
  '.scan-liste.mit-bild .bild { width: 52px; height: 52px; grid-row: 1 / span 2; grid-column: 1; }',
  '.scan-liste.mit-bild .nm, .scan-liste.mit-bild .mt { grid-column: 2; }',
  '.scan-liste.mit-bild button { grid-column: 3; }',
  '.ek-upload label.knopf-zwei { background: var(--fl); color: var(--akzent); }',
  '.ek-vorschau { margin-top: 10px; }',
  '.ek-bilder { display: flex; gap: 6px; overflow-x: auto; padding-bottom: 4px; }',
  '.ek-bilder canvas { height: 160px; width: auto; border: 1px solid var(--linie); border-radius: 6px; background: #fff; flex: 0 0 auto; }',
  '.ek-aktionen .ek-haupt { background: var(--akzent); border-color: var(--akzent); color: #fff; font-weight: 600; }',
  '.ek-weiter { border: 1px solid var(--linie); background: var(--bg); border-radius: 8px; padding: 5px 10px; font-size: 13px; cursor: pointer; }',
  '.ek-rechnung summary { cursor: pointer; display: grid; grid-template-columns: 1fr auto; gap: 4px 12px; list-style: none; }',
  '.ek-rechnung summary::-webkit-details-marker { display: none; }',
  '.ek-rechnung .meta { color: var(--leise); font-size: 13px; display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }',
  '.ek-rechnung .rechts { text-align: right; }',
  '.ek-rechnung .rechts b { font-size: 16px; }',
  '.ek-gut { color: var(--gut); font-weight: 600; }',
  '.ek-pos { width: 100%; border-collapse: collapse; font-size: 13px; margin-top: 8px; }',
  '.ek-pos td, .ek-pos th { padding: 4px 6px; border-bottom: 1px solid var(--linie); text-align: left; vertical-align: top; }',
  '.ek-pos td.z, .ek-pos th.z { text-align: right; white-space: nowrap; }',
  '.ek-pos a { cursor: pointer; }',
  '.ek-status { font-size: 12px; border-radius: 6px; padding: 2px 7px; background: var(--mittel-bg); color: var(--mittel); font-weight: 600; }',
  '.ek-aktionen { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px; }',
  '.ek-aktionen a, .ek-aktionen button { border: 1px solid var(--linie); background: var(--bg); border-radius: 8px; padding: 5px 10px; font-size: 13px; color: var(--text); text-decoration: none; cursor: pointer; }',
  '.ek-normal li { margin: 4px 0; }',
  '.ek-normal small { color: var(--leise); }',
  '#kaeufe h3 { font-size: 14px; margin: 16px 0 4px; }',
  '.ek-zuordnen { border: 0; background: none; color: var(--akzent); cursor: pointer; font-size: 12px; padding: 0 2px; }',
  '.ek-zuordnen.offen { border: 1px solid var(--mittel); background: var(--mittel-bg); color: var(--mittel); border-radius: 6px; padding: 1px 6px; font-weight: 600; }'
].join('\n');
document.head.appendChild(css);

// ------------------------------------------------------------------ Reiter "Einkaeufe"
var reiter = document.querySelector('.reiter');
var knopf = document.createElement('button');
knopf.setAttribute('role', 'tab'); knopf.id = 'r-einkaeufe'; knopf.setAttribute('aria-selected', 'false'); knopf.textContent = 'Einkäufe';
reiter.appendChild(knopf);
var bereich = document.createElement('section');
bereich.id = 'einkaeufe'; bereich.hidden = true;
bereich.style.gridColumn = '1 / -1';
document.querySelector('main').after(bereich);

function zeige(an) {
  bereich.hidden = !an;
  document.querySelector('main').hidden = an;
  if ($('katnav')) $('katnav').hidden = an;
  document.querySelector('.filter').hidden = an;
  $('unter').hidden = an || !$('unter').innerHTML;
  knopf.setAttribute('aria-selected', an);
  if (an) { $('r-angebote').setAttribute('aria-selected', 'false'); $('r-alle').setAttribute('aria-selected', 'false'); laden(); }
}
knopf.onclick = function () { zeige(true); };
$('r-angebote').addEventListener('click', function () { zeige(false); });
$('r-alle').addEventListener('click', function () { zeige(false); });

var DATEN = null;
function laden() {
  if (lokal) {
    bereich.innerHTML = '<div class="hinweis">Einkäufe und Rechnungen brauchen den Server (PHP und Datenbank). Sie funktionieren auf preise.kaipel.at, nicht in der lokalen Vorschau.</div>';
    return;
  }
  bereich.innerHTML = '<div class="hinweis">Einkäufe werden geladen …</div>';
  holeJson('einkaeufe.php').then(function (d) { DATEN = d; zeichne(); }, function (e) {
    bereich.innerHTML = '<div class="hinweis">Einkäufe konnten nicht geladen werden: ' + esc(e.message) + '</div>';
  });
}

function zeichne() {
  var d = DATEN, g = d.gesamt, h = '';
  // Hochladen
  h += '<div class="ek-karte"><div class="ek-upload"><label class="knopf">📷 Rechnung fotografieren<input type="file" id="ek-foto" accept="image/*" capture="environment"></label>' +
       '<label class="knopf knopf-zwei">📄 Datei wählen<input type="file" id="ek-datei" accept="image/*,application/pdf" multiple></label>' +
       '<span id="ek-status" style="color:var(--leise);font-size:13px">Foto oder PDF. Ausgewertet wird in Claude Code („werte die neuen Rechnungen aus“).</span></div>' +
       '<div id="ek-vorschau" class="ek-vorschau" hidden></div></div>';
  // Summen
  var quote = g.summe + g.ersparnis > 0 ? 100 * g.ersparnis / (g.summe + g.ersparnis) : 0;
  h += '<div class="ek-karte ek-summen">' +
       '<div class="kz"><span>Gespart gesamt</span><b class="ek-gut">' + euro(g.ersparnis) + '</b><span>' + Math.round(quote) + ' % vom Normalpreis</span></div>' +
       '<div class="kz"><span>Ausgegeben</span><b>' + euro(g.summe) + '</b><span>' + g.einkaeufe + ' ausgewertete Einkäufe</span></div>' +
       (d.monate.length ? '<div class="kz"><span>Dieser Monat (' + esc(d.monate[0].monat) + ')</span><b class="ek-gut">' + euro(d.monate[0].ersparnis) + '</b><span>gespart bei ' + euro(d.monate[0].summe) + '</span></div>' : '') +
       '</div>';
  // Zum Normalpreis gekauft (haeufig) - mit Hinweis, wenn gerade irgendwo in Aktion
  var normal = {};
  d.rechnungen.forEach(function (r) { r.positionen.forEach(function (p) { if (p.aktion) return; var k = p.artikel_id || ('#' + p.name_bon); var e = normal[k] || (normal[k] = { id: p.artikel_id, name: p.name_bon, n: 0, summe: 0, zuletzt: r.datum }); e.n += +p.menge || 1; e.summe += +p.gesamt || 0; if (r.datum > e.zuletzt) e.zuletzt = r.datum; }); });
  var nl = Object.keys(normal).map(function (k) { return normal[k]; }).sort(function (a, b) { return b.summe - a.summe; }).slice(0, 15);
  if (nl.length) {
    h += '<div class="ek-karte"><b>Zum Normalpreis gekauft</b> <span style="color:var(--leise);font-size:13px">– hier lohnt es sich, auf Aktionen zu achten</span><ul class="ek-normal">';
    nl.forEach(function (e) {
      var z = e.id && window.PT && window.PT.SUCHE_ID[e.id];
      var jetzt = z && z[6] != null ? ' <span class="badge b-echt">jetzt in Aktion: ' + euro(z[6]) + '</span>' : '';
      h += '<li>' + (e.id ? '<a data-artikel="' + esc(e.id) + '">' + esc(e.name) + '</a>' : esc(e.name)) + ' <small>' + (+e.n.toFixed(2)) + '× · ' + euro(e.summe) + ' · zuletzt ' + datum(e.zuletzt) + '</small>' + jetzt + '</li>';
    });
    h += '</ul></div>';
  }
  // Rechnungen
  if (!d.rechnungen.length) h += '<div class="hinweis">Noch keine Rechnungen. Lade oben die erste hoch.</div>';
  d.rechnungen.forEach(function (r) {
    h += '<details class="ek-karte ek-rechnung"' + (OFFEN_RECHNUNG === r.id ? ' open' : '') + '><summary><div><div><b>' + (r.datum ? datum(r.datum) : 'Hochgeladen ' + datum(r.hochgeladen)) + '</b> ' + marktHtml(r.markt) + '</div>' +
         '<div class="meta">' + (r.filiale ? '<span>' + esc(r.filiale) + '</span>' : '') + (r.status !== 'ausgewertet' ? '<span class="ek-status">wartet auf Auswertung</span>' : '<span>' + r.positionen.length + ' Positionen</span>') + '</div></div>' +
         '<div class="rechts">' + (r.summe != null ? '<b>' + euro(r.summe) + '</b>' : '') + (r.ersparnis ? '<div class="ek-gut">−' + euro(r.ersparnis) + ' gespart</div>' : '') + '</div></summary>';
    if (r.positionen.length) {
      h += '<table class="ek-pos"><tr><th>Artikel</th><th class="z">Menge</th><th class="z">Bezahlt</th><th class="z">Rabatt</th></tr>';
      r.positionen.forEach(function (p) {
        var name = p.artikel_id ? '<a data-artikel="' + esc(p.artikel_id) + '">' + esc(p.name_bon) + '</a>' : esc(p.name_bon);
        var zu = '<button class="ek-zuordnen' + (p.artikel_id ? '' : ' offen') + '" data-zuordnen="' + p.id + '" data-rechnung="' + r.id + '" title="' + (p.artikel_id ? 'Zuordnung ändern' : 'Artikel zuordnen') + '">' + (p.artikel_id ? '✎' : 'zuordnen') + '</button>';
        h += '<tr><td>' + name + (p.aktion ? ' <span class="badge b-echt">Aktion</span>' : '') + ' ' + zu + '</td><td class="z">' + (+(+p.menge).toFixed(3)) + (p.einheit && p.einheit !== 'stk' ? ' ' + esc(p.einheit) : '') + '</td><td class="z">' + euro(p.gesamt) + '</td><td class="z">' + (p.rabatt ? '−' + euro(p.rabatt) : '') + '</td></tr>';
      });
      h += '</table>';
    }
    if (r.notiz) h += '<p style="color:var(--leise);font-size:13px">' + esc(r.notiz) + '</p>';
    h += '<div class="ek-aktionen"><a href="' + API + 'datei.php?id=' + r.id + '" target="_blank" rel="noopener">Scan ansehen ↗</a><button data-loeschen="' + r.id + '">Rechnung löschen</button></div></details>';
  });
  bereich.innerHTML = h;
  $('ek-datei').onchange = function () { hochladen(Array.prototype.slice.call(this.files)); };
  $('ek-foto').onchange = function () { var f = this.files[0]; this.value = ''; if (f) fotoDazu(f); };
  if (FOTOS.length) zeigeVorschau();
}

// ------------------------------------------------------------------ Rechnung fotografieren
// Lange Rechnungen: mehrere Fotos nacheinander, sie werden untereinander zu einem Bild zusammengesetzt.
// Vor dem Hochladen verkleinert (schneller Upload im Geschaeft, Text bleibt gut lesbar).
var FOTOS = [];   // geladene Bilder (HTMLImageElement / ImageBitmap) in Reihenfolge
function bildLaden(datei) {
  if (window.createImageBitmap) return createImageBitmap(datei, { imageOrientation: 'from-image' }).catch(function () { return bildLadenAlt(datei); });
  return bildLadenAlt(datei);
}
function bildLadenAlt(datei) {
  return new Promise(function (ok, fehler) {
    var url = URL.createObjectURL(datei), img = new Image();
    img.onload = function () { ok(img); }; img.onerror = function () { URL.revokeObjectURL(url); fehler(new Error('Foto konnte nicht gelesen werden')); };
    img.src = url;
  });
}
function fotoDazu(datei) {
  var st = $('ek-status'); if (st) st.textContent = 'Foto wird vorbereitet …';
  bildLaden(datei).then(function (b) { FOTOS.push(b); zeigeVorschau(); }, function (e) {
    // Kann der Browser das Format nicht anzeigen (z. B. HEIC), die Datei unveraendert hochladen
    if (st) st.textContent = e.message + ' – wird unverändert hochgeladen.';
    hochladen([datei]);
  });
}
function zusammensetzen() {
  // gemeinsame Breite: schmalstes Foto, hoechstens 1600 px; Gesamthoehe fuer Handy-Browser begrenzt
  var breite = Math.min(1600, Math.min.apply(null, FOTOS.map(function (b) { return b.width; })));
  var hoehen = FOTOS.map(function (b) { return Math.round(b.height * breite / b.width); });
  var gesamt = hoehen.reduce(function (s, x) { return s + x; }, 0);
  // ein Foto: laengste Seite hoechstens 2600 px; mehrere: Hoehe hoechstens 14000 px;
  // dazu hoechstens 16 Mio. Bildpunkte (Grenze von Safari am iPhone)
  var f = FOTOS.length === 1 ? Math.min(1, 2600 / Math.max(breite, gesamt)) : Math.min(1, 14000 / gesamt);
  f = Math.min(f, Math.sqrt(16e6 / (breite * gesamt)));
  var c = document.createElement('canvas');
  c.width = Math.round(breite * f); c.height = Math.round(gesamt * f);
  var ctx = c.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height);
  var y = 0;
  FOTOS.forEach(function (b, i) { var h = Math.round(hoehen[i] * f); ctx.drawImage(b, 0, y, c.width, h); y += h; });
  return new Promise(function (ok) { c.toBlob(function (blob) { ok(blob); }, 'image/jpeg', 0.85); });
}
function zeigeVorschau() {
  var box = $('ek-vorschau'); if (!box) return;
  box.hidden = !FOTOS.length;
  if (!FOTOS.length) { box.innerHTML = ''; return; }
  box.innerHTML = '<div class="ek-bilder" id="ek-bilder"></div>' +
    '<div class="ek-aktionen"><button class="ek-haupt" id="ek-senden">⬆ Rechnung hochladen' + (FOTOS.length > 1 ? ' (' + FOTOS.length + ' Fotos)' : '') + '</button>' +
    '<label class="ek-weiter">＋ Weiteres Foto (lange Rechnung)<input type="file" id="ek-foto2" accept="image/*" capture="environment" hidden></label>' +
    '<button id="ek-verwerfen">Verwerfen</button></div>' +
    '<p style="color:var(--leise);font-size:12px;margin:6px 0 0">Tipp: Rechnung flach hinlegen, gut ausleuchten. Bei langen Rechnungen von oben nach unten in Teilen fotografieren – die Fotos werden zusammengesetzt.</p>';
  FOTOS.forEach(function (b) {
    var c = document.createElement('canvas'), h = 160, w = Math.round(b.width * h / b.height);
    c.width = w; c.height = h; c.getContext('2d').drawImage(b, 0, 0, w, h);
    $('ek-bilder').appendChild(c);
  });
  var st = $('ek-status'); if (st) st.textContent = 'Foto bereit. Lesbar? Dann hochladen – oder weiteres Foto anfügen.';
  $('ek-foto2').onchange = function () { var f = this.files[0]; this.value = ''; if (f) fotoDazu(f); };
  $('ek-verwerfen').onclick = function () { FOTOS = []; zeigeVorschau(); var s = $('ek-status'); if (s) s.textContent = 'Verworfen.'; };
  $('ek-senden').onclick = function () {
    this.disabled = true; var s = $('ek-status'); if (s) s.textContent = 'Wird hochgeladen …';
    zusammensetzen().then(function (blob) {
      FOTOS = [];
      var name = 'rechnung-' + new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-') + '.jpg';
      hochladen([new File([blob], name, { type: 'image/jpeg' })]);
    });
  };
}

function hochladen(dateien) {
  if (!dateien.length) return;
  var st = $('ek-status'), fertig = 0, fehler = [];
  st.textContent = 'Lade ' + dateien.length + ' Datei(en) hoch …';
  dateien.reduce(function (p, f) {
    return p.then(function () {
      var fd = new FormData(); fd.append('datei', f);
      return holeJson('upload.php', { method: 'POST', body: fd }).then(function () { fertig++; }, function (e) { fehler.push(f.name + ': ' + e.message); });
    });
  }, Promise.resolve()).then(function () {
    laden();
    setTimeout(function () { var s = $('ek-status'); if (s) s.textContent = fertig + ' hochgeladen' + (fehler.length ? ', Fehler: ' + fehler.join('; ') : '') + '. Zum Auswerten in Claude Code Bescheid sagen.'; }, 300);
  });
}

bereich.addEventListener('click', function (ev) {
  var a = ev.target.closest('[data-artikel]');
  if (a) { ev.preventDefault(); var id = a.dataset.artikel; if (window.PT) window.PT.ladeSuche().then(function () { window.PT.oeffne(id); }); return; }
  var zb = ev.target.closest('[data-zuordnen]');
  if (zb) { ev.preventDefault(); zuordnen(+zb.dataset.zuordnen, +zb.dataset.rechnung); return; }
  var l = ev.target.closest('[data-loeschen]');
  if (l && confirm('Rechnung samt Scan endgültig löschen?')) holeJson('einkaeufe.php?loeschen=' + l.dataset.loeschen, { method: 'POST' }).then(laden, function (e) { alert(e.message); });
});

// ------------------------------------------------------------------ Bon-Position haendisch zuordnen
var OFFEN_RECHNUNG = null;   // nach dem Neuladen dieselbe Rechnung wieder aufklappen
function zuordnen(posId, rechnungId) {
  var PT = window.PT; if (!PT || !DATEN) return;
  var r = DATEN.rechnungen.filter(function (x) { return x.id === rechnungId; })[0]; if (!r) return;
  var p = r.positionen.filter(function (x) { return x.id === posId; })[0]; if (!p) return;
  var stueck = p.einzelpreis != null ? p.einzelpreis : (p.menge ? p.gesamt / p.menge : p.gesamt);
  // Bon-Kuerzel als Startwert: Zahlen und Einheiten weg ("COKE ZERO0,5" -> "coke zero")
  var start = String(p.name_bon).toLowerCase().replace(/(\d)([a-z])/g, '$1 $2').replace(/([a-z])(\d)/g, '$1 $2').replace(/\d+([.,]\d+)?\s*(kg|g|l|ml|cl)?\b/g, ' ').replace(/[^a-zäöüß*]+/g, ' ').trim();
  PT.zeigeBlatt('<button class="zu" id="zu" aria-label="Schließen">×</button><h2>Bon-Position zuordnen</h2>' +
    '<div class="scan-produkt"><b>' + esc(p.name_bon) + '</b> · ' + (+(+p.menge).toFixed(3)) + (p.einheit && p.einheit !== 'stk' ? ' ' + esc(p.einheit) : ' ×') + ' · ' + euro(stueck) + (p.einheit === 'kg' ? ' / kg' : ' je Stück') + ' · ' + marktHtml(r.markt) + ' ' + datum(r.datum) +
    (p.artikel_id ? '<br><small>Derzeit: ' + esc((PT.SUCHE_ID[p.artikel_id] || [null, p.artikel_id])[1]) + '</small>' : '<br><small>Noch keinem Artikel zugeordnet</small>') + '</div>' +
    '<form class="scan-form" id="zo-form"><input id="zo-text" autocomplete="off" value="' + esc(start) + '" placeholder="Artikel suchen, z. B. coca cola zero" aria-label="Artikel suchen"><button>Suchen</button></form>' +
    '<label style="font-size:13px;color:var(--leise);display:flex;gap:6px;align-items:center"><input type="checkbox" id="zo-alle"> auch in anderen Märkten suchen</label>' +
    '<div id="zo-liste" class="scan-status">Wird geladen …</div>' +
    (p.artikel_id ? '<div class="ek-aktionen"><button id="zo-weg">Zuordnung entfernen</button></div>' : ''));
  $('zu').onclick = PT.schliesse;
  function suche() {
    PT.ladeSuche().then(function (S) {
      var q = PT.vglWoerter($('zo-text').value), alle = $('zo-alle').checked || !r.markt;
      if (!q.length) { $('zo-liste').innerHTML = 'Suchbegriff eingeben.'; return; }
      var l = S.filter(function (z) {
        if (!alle && z[2] !== r.markt) return false;
        var w = PT.vglWoerter(z[1] + ' ' + (z[9] || ''));
        return q.every(function (t) { return w.some(function (x) { return x.indexOf(t) === 0; }); });
      });
      // aehnlicher Preis zuerst (Stueckpreis bzw. kg-Preis wie am Bon), dann kuerzere Namen
      // Groessen am Bon ("0,5", "250G", "1,5L") -> passende Packungen bevorzugen
      var groessen = [];
      String(p.name_bon).replace(/(\d+(?:[.,]\d+)?)\s*(kg|g|ml|cl|l)?/gi, function (_, n, e) {
        var v = parseFloat(n.replace(',', '.')); e = (e || '').toLowerCase();
        if (e === 'g' || e === 'ml') v /= 1000; else if (e === 'cl') v /= 100;
        if (v > 0) groessen.push(v);
      });
      function abstand(z) {
        var pr = z[6] != null ? z[6] : z[5]; if (p.einheit === 'kg' && z[8] === 'kg' && z[7] > 0) pr = pr / z[7];
        var passt = groessen.some(function (g) { return Math.abs(z[7] - g) <= g * 0.02; });
        return Math.abs(Math.log((pr || 1) / (stueck || 1))) - (passt ? 1 : 0);
      }
      l.sort(function (a, b) { return abstand(a) - abstand(b) || a[1].length - b[1].length; });
      $('zo-liste').className = '';
      var zeige = function () { $('zo-liste').innerHTML = l.length ? '<ul class="scan-liste mit-bild">' + l.slice(0, 25).map(function (z) {
        var pr = z[6] != null ? z[6] : z[5];
        return '<li>' + PT.bild(z[0]) + '<div class="nm">' + esc(z[1]) + '</div><div class="mt">' + marktHtml(z[2]) + '<span>' + PT.packung(z[7], z[8]) + '</span><span>' + euro(pr) + (z[6] != null ? ' (Aktion)' : '') + '</span>' + (z[0] === p.artikel_id ? '<span class="badge b-echt">aktuell</span>' : '') + '</div>' +
          '<button class="scan-knopf2" data-wahl="' + esc(z[0]) + '">Zuordnen</button></li>';
      }).join('') + '</ul>' + (l.length > 25 ? '<p class="scan-status">' + (l.length - 25) + ' weitere – Suche genauer machen.</p>' : '')
        : '<p class="scan-status">Nichts gefunden' + (alle ? '' : ' bei ' + esc(MARKT[r.markt] || r.markt) + ' – Häkchen „auch in anderen Märkten“ setzen oder anders suchen') + '.</p>'; };
      zeige();
      // Bilder stecken in den Kategorie-Dateien: fuer die angezeigten Treffer nachladen, dann neu zeichnen
      var ids = l.slice(0, 25).map(function (z) { return z[0]; });
      if (ids.some(function (id) { return !PT.POOL[id] || PT.POOL[id].kompakt; })) PT.ladeVoll(ids).then(function () { if ($('zo-liste')) zeige(); });
    });
  }
  function speichere(aid) {
    holeJson('einkaeufe.php?zuordnen=' + posId, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ artikel_id: aid }) })
      .then(function () { OFFEN_RECHNUNG = rechnungId; PT.schliesse(); laden(); }, function (e) { alert('Speichern fehlgeschlagen: ' + e.message); });
  }
  $('zo-form').onsubmit = function (ev) { ev.preventDefault(); suche(); };
  $('zo-alle').onchange = suche;
  $('zo-liste').onclick = function (ev) { var b = ev.target.closest('[data-wahl]'); if (b) speichere(b.dataset.wahl); };
  if ($('zo-weg')) $('zo-weg').onclick = function () { speichere(null); };
  suche();
}

// ------------------------------------------------------------------ Im Artikel-Detail: eigene Kaeufe und Preisentwicklung seither
window.PT_KAEUFE = function (id, el) {
  if (lokal || !el) return;
  holeJson('einkaeufe.php?artikel=' + encodeURIComponent(id)).then(function (d) {
    if (!d.kaeufe.length) return;
    var r = window.PT && window.PT.POOL[id];
    var jetzt = r ? r.bezahlt : null;
    var h = '<h3>Deine Käufe</h3><table class="ek-pos"><tr><th>Datum</th><th>Markt</th><th class="z">Menge</th><th class="z">je Stück</th><th class="z">heute</th></tr>';
    d.kaeufe.forEach(function (k) {
      var stueck = k.einzelpreis != null ? k.einzelpreis : (k.menge ? k.gesamt / k.menge : k.gesamt);
      var diff = jetzt != null && stueck ? 100 * (jetzt / stueck - 1) : null;
      h += '<tr><td>' + datum(k.datum) + '</td><td>' + marktHtml(k.markt) + '</td><td class="z">' + (+(+k.menge).toFixed(3)) + '</td><td class="z">' + euro(stueck) + (k.aktion ? ' <span class="badge b-echt">Aktion</span>' : '') + '</td><td class="z">' + (diff == null ? '–' : (diff > 0 ? '+' : '') + Math.round(diff) + ' %') + '</td></tr>';
    });
    el.innerHTML = h + '</table>';
  }, function () {});
};
})();
