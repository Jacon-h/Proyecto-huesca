<?php
// (A9) Qué pasa si la salida NO se escapa. Genera una página HTML de demostración, aparte del panel.
//
//   docker exec panel php /var/www/panel/pruebas/demo-xss.php > demo-xss.html
//   (abrir demo-xss.html en el navegador)
//
// Usa el mismo título malicioso que se puede dar de alta en el panel y lo pinta dos veces:
//   1. Con e()  → como hace el panel: se ve el texto tal cual y no se ejecuta nada.
//   2. Sin e()  → como estaría sin escapar: el navegador lo interpreta como HTML y ejecuta el script.
// No está en public/: el panel nunca sirve esta página.
declare(strict_types=1);

require __DIR__ . '/../comun/funciones.php';

// Lo que escribiría un usuario malintencionado en el campo "Título" del alta de proyecto.
$titulo = 'Proyecto <b>trampa</b><script>document.body.style.background="#f88";'
        . 'document.getElementById("aviso").textContent="¡Script ejecutado! Podría leer la página o enviarla a otro sitio.";</script>';
?>
<!doctype html>
<html lang="es">
<head><meta charset="utf-8"><title>A9 · Salida escapada y sin escapar</title></head>
<body>
<h1>A9 · El mismo título, con y sin escapar</h1>
<p id="aviso">Si este texto cambia y el fondo se pone rojo, el script se ha ejecutado.</p>

<h2>1. Con e() (lo que hace el panel)</h2>
<table border="1"><tr><td><?= e($titulo) ?></td></tr></table>
<p>HTML que se envía al navegador:</p>
<pre><?= e(e($titulo)) ?></pre>

<h2>2. Sin e() (lo que pasaría sin escapar)</h2>
<table border="1"><tr><td><?= $titulo ?></td></tr></table>
<p>HTML que se envía al navegador:</p>
<pre><?= e($titulo) ?></pre>
</body>
</html>
