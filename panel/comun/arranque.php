<?php
// Lo primero de cada página: carga las funciones y abre la sesión.
declare(strict_types=1);

require_once __DIR__ . '/funciones.php';
require_once __DIR__ . '/sesion.php';
require_once __DIR__ . '/proyectos.php';
require_once __DIR__ . '/plantilla.php';

iniciar_sesion();
