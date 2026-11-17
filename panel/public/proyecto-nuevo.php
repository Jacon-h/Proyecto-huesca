<?php
declare(strict_types=1);

require __DIR__ . '/../comun/arranque.php';

$u = exigir_perfil(['cesar']);

$errores = [];
$p = ['codigo' => '', 'titulo' => '', 'tarifa' => 'academica', 'responsable' => ''];
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    [$p, $errores] = validar_proyecto($_POST, $u);
    if ($errores === []) {
        $proyectos = leer_datos('proyectos');
        $proyectos[] = $p;
        guardar_datos('proyectos', $proyectos);
        redirigir('proyecto.php?codigo=' . urlencode($p['codigo']));
    }
}

/** Mensaje de error de un campo, si lo hay. */
function error_de(array $errores, string $campo): string
{
    return isset($errores[$campo]) ? '<span class="error">' . e($errores[$campo]) . '</span>' : '';
}

cabecera('Nuevo proyecto', $u);
?>
<form method="post" class="tarjeta" novalidate>
  <label>Código <input name="codigo" value="<?= e($p['codigo']) ?>" placeholder="BIO-0003"></label>
  <?= error_de($errores, 'codigo') ?>
  <label>Título <input name="titulo" value="<?= e($p['titulo']) ?>"></label>
  <?= error_de($errores, 'titulo') ?>
  <label>Tarifa
    <select name="tarifa">
      <?php foreach (TARIFAS as $clave => $nombre): ?>
      <option value="<?= e($clave) ?>" <?= $p['tarifa'] === $clave ? 'selected' : '' ?>><?= e($nombre) ?></option>
      <?php endforeach ?>
    </select>
  </label>
  <?= error_de($errores, 'tarifa') ?>
  <label>Responsable
    <select name="responsable">
      <?php foreach (usuarios_con_perfil('responsable') as $r): ?>
      <option value="<?= e($r['usuario']) ?>" <?= $p['responsable'] === $r['usuario'] ? 'selected' : '' ?>><?= e($r['nombre']) ?></option>
      <?php endforeach ?>
    </select>
  </label>
  <?= error_de($errores, 'responsable') ?>
  <button>Dar de alta</button>
</form>
<?php
pie();
