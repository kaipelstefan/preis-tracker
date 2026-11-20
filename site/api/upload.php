<?php
// Rechnung hochladen (Foto oder PDF). Feld: "datei" (multipart/form-data), optional "notiz".
declare(strict_types=1);
require __DIR__ . '/db.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') fehler('Nur POST', 405);
if (empty($_FILES['datei']) || $_FILES['datei']['error'] !== UPLOAD_ERR_OK) fehler('Keine Datei empfangen (Fehler ' . ($_FILES['datei']['error'] ?? '?') . ')');

$f = $_FILES['datei'];
if ($f['size'] > 25 * 1024 * 1024) fehler('Datei zu gross (max. 25 MB)');
$mime = (new finfo(FILEINFO_MIME_TYPE))->file($f['tmp_name']) ?: 'application/octet-stream';
$erlaubt = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp', 'image/heic' => 'heic', 'image/heif' => 'heic', 'application/pdf' => 'pdf'];
if (!isset($erlaubt[$mime])) fehler('Nur Fotos (JPG, PNG, WebP, HEIC) oder PDF');

$name = date('Ymd-His') . '-' . bin2hex(random_bytes(4)) . '.' . $erlaubt[$mime];
$ziel = ablage() . '/' . $name;
if (!move_uploaded_file($f['tmp_name'], $ziel)) fehler('Speichern fehlgeschlagen', 500);

$st = db()->prepare('INSERT INTO pt_rechnung (datei, original, mime, hochgeladen, notiz) VALUES (?, ?, ?, NOW(), ?)');
$st->execute([$name, mb_substr((string)$f['name'], 0, 255), $mime, $_POST['notiz'] ?? null]);
antwort(['ok' => true, 'id' => (int)db()->lastInsertId(), 'datei' => $name]);
