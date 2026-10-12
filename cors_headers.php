<?php
// CORS / Cross-Origin-Resource-Policy para backends PHP (drop-in).
// Uso:  require __DIR__ . '/cors_headers.php';
header('Cross-Origin-Resource-Policy: cross-origin');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET,HEAD,POST,PUT,PATCH,DELETE,OPTIONS');
header('Access-Control-Allow-Headers: *');
header('Access-Control-Expose-Headers: *');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}
