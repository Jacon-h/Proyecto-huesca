<?php
// Estado de la conexión del panel con su base (BIFI_DB). Solo para el CESAR (P1 y "qué IP ve el gestor").
declare(strict_types=1);

require __DIR__ . '/../comun/arranque.php';

$u = exigir_perfil(['cesar']);

// Esta página es justo para diagnosticar la conexión, y solo la ve el CESAR: por eso aquí sí se enseña
// el motivo del fallo, en vez de dejar que lo recoja el manejador general de arranque.php.
$estado = null;
$error = '';
try {
    $estado = estado_bifi(bd());
} catch (PDOException $ex) {
    $error = $ex->getMessage();
}

$etiquetas = [
    'usuario'           => 'Usuario con el que entra el panel',
    'base'              => 'Base',
    'ip_cliente'        => 'IP del panel que ve el gestor',
    'ip_servidor'       => 'IP del gestor en esa red',
    'codificacion'      => 'Codificación',
    'colacion'          => 'Colación',
    'statement_timeout' => 'statement_timeout',
    'limite_conexiones' => 'Límite de conexiones del usuario',
];

cabecera('Estado de la base', $u);
if ($error !== '') {
    echo '<p class="error">El panel no puede entrar en la base: ' . e($error) . '</p>';
} else {
    ?>
<table>
  <?php foreach ($etiquetas as $campo => $texto): ?>
  <tr><th><?= e($texto) ?></th><td><?= e((string) $estado[$campo]) ?></td></tr>
  <?php endforeach ?>
</table>
    <?php
}
pie();
