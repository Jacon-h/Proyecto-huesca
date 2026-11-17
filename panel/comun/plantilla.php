<?php
// Cabecera, menú y pie comunes a todas las páginas.
declare(strict_types=1);

require_once __DIR__ . '/funciones.php';

function cabecera(string $titulo, ?array $u = null): void
{
    ?>
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?= e($titulo) ?> · Panel del BIFI</title>
  <link rel="stylesheet" href="estilo.css">
</head>
<body>
<header>
  <strong>Panel del BIFI</strong>
  <?php if ($u !== null): ?>
    <nav><?= menu($u) ?></nav>
    <span class="quien"><?= e($u['nombre']) ?> · <?= e(PERFILES[$u['perfil']]) ?></span>
  <?php endif ?>
</header>
<main>
<h1><?= e($titulo) ?></h1>
    <?php
}

/** (RA5 g). El menú cambia según el perfil: «Nuevo proyecto», solo el CESAR. */
function menu(array $u): string
{
    $enlaces = ['index.php' => 'Proyectos'];
    if ($u['perfil'] === 'cesar') {
        $enlaces['proyecto-nuevo.php'] = 'Nuevo proyecto';
    }
    $enlaces['logout.php'] = 'Salir';

    $html = '';
    foreach ($enlaces as $url => $texto) {
        $html .= '<a href="' . e($url) . '">' . e($texto) . '</a> ';
    }
    return $html;
}

function pie(): void
{
    echo "</main>\n</body>\n</html>\n";
}

function pagina_error(int $codigo, string $mensaje): never
{
    http_response_code($codigo);
    cabecera('Error ' . $codigo, usuario_actual());
    echo '<p class="error">' . e($mensaje) . '</p><p><a href="index.php">Volver</a></p>';
    pie();
    exit;
}
