<?php
// Cabecera, menú y pie comunes a todas las páginas.
declare(strict_types=1);

require_once __DIR__ . '/funciones.php';

/** Solo para pintar el avatar: «Ana Lorente» → «AL». */
function iniciales(string $nombre): string
{
    $partes = preg_split('/\s+/u', trim($nombre), -1, PREG_SPLIT_NO_EMPTY) ?: [];
    $letras = '';
    foreach (array_slice($partes, 0, 2) as $parte) {
        $letras .= mb_strtoupper(mb_substr($parte, 0, 1));
    }
    return $letras !== '' ? $letras : '?';
}

function cabecera(string $titulo, ?array $u = null): void
{
    // Versión en la URL de los ficheros estáticos: si cambian, el navegador no usa la copia vieja.
    $v_css = (int) @filemtime(__DIR__ . '/../public/estilo.css');
    $v_js  = (int) @filemtime(__DIR__ . '/../public/panel.js');
    ?>
<!doctype html>
<html lang="es" data-tema="oscuro">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="dark light">
  <title><?= e($titulo) ?> · Panel del BIFI</title>
  <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='9' fill='%2338bdf8'/%3E%3Cpath d='M16 9 9 21h14z' fill='none' stroke='%2304101f' stroke-width='2' stroke-linejoin='round'/%3E%3C/svg%3E">
  <script>try{document.documentElement.classList.add('js');var t=localStorage.getItem('panel-tema');if(t==='claro'||t==='oscuro')document.documentElement.dataset.tema=t}catch(e){}</script>
  <link rel="stylesheet" href="estilo.css?v=<?= $v_css ?>">
  <script src="panel.js?v=<?= $v_js ?>" defer></script>
</head>
<body class="<?= $u === null ? 'invitado' : 'con-sesion' ?>">
<header class="superior">
  <a class="marca" href="index.php">
    <svg class="logo" viewBox="0 0 32 32" aria-hidden="true">
      <defs><linearGradient id="lg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#38bdf8"/><stop offset="1" stop-color="#a78bfa"/></linearGradient></defs>
      <rect width="32" height="32" rx="9" fill="url(#lg)"/>
      <path d="M16 9 9 21h14z" fill="none" stroke="#04101f" stroke-width="1.6" stroke-linejoin="round"/>
      <g fill="#04101f"><circle cx="16" cy="9" r="2.6"/><circle cx="9" cy="21" r="2.6"/><circle cx="23" cy="21" r="2.6"/></g>
    </svg>
    <span>Panel del BIFI</span>
  </a>
  <?php if ($u !== null): ?>
    <nav aria-label="Principal"><?= menu($u) ?></nav>
    <span class="quien">
      <span class="avatar" aria-hidden="true"><?= e(iniciales($u['nombre'])) ?></span>
      <span class="quien-txt"><strong><?= e($u['nombre']) ?></strong><small><?= e(PERFILES[$u['perfil']]) ?></small></span>
    </span>
  <?php endif ?>
  <button type="button" class="tema" id="tema" aria-label="Cambiar entre tema claro y oscuro" title="Cambiar tema"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 3.5a8.5 8.5 0 0 1 0 17z" fill="currentColor"/></svg></button>
</header>
<main>
<h1><?= e($titulo) ?></h1>
    <?php
}

/**
 * (A5) El menú cambia según el perfil que hay en la sesión: «Nuevo proyecto» y «Estado de la base»,
 * solo el CESAR. Ocultar un enlace no protege nada: cada página comprueba el perfil (exigir_perfil).
 *
 * «Salir» es un botón de formulario y no un enlace: cerrar la sesión cambia algo, y con un enlace
 * cualquier otra web podría hacerlo con un simple <img src=".../logout.php">.
 * Solo para pintar: el enlace de la página en la que estás sale resaltado.
 */
function menu(array $u): string
{
    $enlaces = ['index.php' => 'Proyectos'];
    if ($u['perfil'] === 'cesar') {
        $enlaces['proyecto-nuevo.php'] = 'Nuevo proyecto';
        $enlaces['estado-bd.php'] = 'Estado de la base';
    }

    $actual = basename((string) ($_SERVER['SCRIPT_NAME'] ?? ''));
    if ($actual === 'proyecto.php') {
        $actual = 'index.php';   // el detalle de un proyecto cuelga de «Proyectos»
    }

    $html = '';
    foreach ($enlaces as $url => $texto) {
        $html .= '<a href="' . e($url) . '"'
            . ($url === $actual ? ' class="activa" aria-current="page"' : '')
            . '>' . e($texto) . '</a> ';
    }
    return $html . '<form method="post" action="logout.php" class="en-linea">' . campo_csrf()
         . '<button class="enlace salir">Salir</button></form>';
}

function pie(): void
{
    echo "</main>\n";
    echo "<footer class=\"pie\"><span>Panel del BIFI · Sede Huesca</span><span>Datos y precios de ejemplo</span></footer>\n";
    echo "</body>\n</html>\n";
}

function pagina_error(int $codigo, string $mensaje): never
{
    http_response_code($codigo);
    cabecera('Error ' . $codigo, usuario_actual());
    echo '<p class="error">' . e($mensaje) . '</p><p><a class="boton" href="index.php">Volver</a></p>';
    pie();
    exit;
}

