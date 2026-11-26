<?php
declare(strict_types=1);

require __DIR__ . '/../comun/arranque.php';

// Solo se sale con el botón del menú (POST con su código CSRF). Una visita por GET no cierra nada.
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    redirigir('index.php');
}
exigir_csrf();

salir();
redirigir('login.php');
