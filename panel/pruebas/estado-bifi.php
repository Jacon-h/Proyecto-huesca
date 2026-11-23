<?php
// Prueba P1 desde la línea de órdenes: el contenedor del panel entra en su base (BIFI_DB).
//   docker exec panel php /var/www/panel/pruebas/estado-bifi.php
// Lo lanza db/pruebas/probar.sh. No está en public/: no se puede abrir desde el navegador.
declare(strict_types=1);

require __DIR__ . '/../comun/bd.php';

try {
    $estado = estado_bifi(conectar_bifi());
} catch (PDOException $ex) {
    fwrite(STDERR, 'ERROR: el panel no entra en su base: ' . $ex->getMessage() . PHP_EOL);
    exit(1);
}

echo 'usuario: ' . $estado['usuario'] . PHP_EOL;
echo 'base: ' . $estado['base'] . PHP_EOL;
echo 'IP que ve el gestor: ' . $estado['ip_cliente'] . PHP_EOL;
echo 'IP del gestor en esa red: ' . $estado['ip_servidor'] . PHP_EOL;
echo 'codificación y colación: ' . $estado['codificacion'] . ' ' . $estado['colacion'] . PHP_EOL;
echo 'statement_timeout: ' . $estado['statement_timeout'] . PHP_EOL;
echo 'límite de conexiones: ' . $estado['limite_conexiones'] . PHP_EOL;
