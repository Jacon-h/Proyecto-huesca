<?php
// Lo primero de cada página: carga las funciones y abre la sesión.
declare(strict_types=1);

require_once __DIR__ . '/funciones.php';
require_once __DIR__ . '/bd.php';
require_once __DIR__ . '/sesion.php';
require_once __DIR__ . '/proyectos.php';
require_once __DIR__ . '/plantilla.php';

// Si la base no responde o una consulta falla, el detalle (servidor, usuario, SQL) va al registro de
// Apache (docker logs panel) y el navegador solo recibe un mensaje genérico. Enseñar el error de PDO
// daría pistas a quien esté probando el panel desde fuera.
set_exception_handler(function (Throwable $ex): void {
    error_log('panel: ' . $ex);
    pagina_error(503, 'El panel no puede consultar sus datos en este momento. Prueba de nuevo en unos minutos.');
});

iniciar_sesion();
