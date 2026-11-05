<?php
// Página de estado: confirma que Apache, PHP y PostgreSQL funcionan juntos.
// Comprobación:  curl -s -H "Host: www.$DOMINIO" http://$IP_AULA/estado.php
header('Content-Type: text/plain; charset=utf-8');

function dsn() {   // cadena de conexión que admite contraseñas con espacios o comillas
    $p = ['host' => getenv('DB_HOST') ?: 'db', 'port' => '5432', 'dbname' => getenv('DB_NAME'),
          'user' => getenv('DB_USER'), 'password' => getenv('DB_PASSWORD')];
    $s = '';
    foreach ($p as $k => $v) $s .= "$k='" . addcslashes((string)$v, "'\\") . "' ";
    return $s;
}

$conn = @pg_connect(dsn());
if (!$conn) {
    http_response_code(500);
    die("ESTADO: ERROR - no hay conexión con PostgreSQL\n");
}

$filas = pg_fetch_result(pg_query($conn, 'SELECT count(*) FROM inventario'), 0, 0);
echo "ESTADO: OK\n";
echo "Servidor web: " . $_SERVER['SERVER_SOFTWARE'] . " / PHP " . PHP_VERSION . "\n";
echo "Base de datos: " . getenv('DB_NAME') . " (usuario " . getenv('DB_USER') . ")\n";
echo "Filas en inventario: $filas\n";
