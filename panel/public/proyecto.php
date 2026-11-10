<?php
declare(strict_types=1);

require __DIR__ . '/../comun/arranque.php';

$u = exigir_login();
$p = buscar_proyecto((string) ($_GET['codigo'] ?? ''));

// Aislamiento (RA5 i): si no existe o no es suyo, lo mismo. ¿Por qué no un 403 cuando no es suyo?
if ($p === null || !puede_ver($u, $p)) {
    pagina_error(404, 'No hay ningún proyecto con ese código entre los tuyos.');
}

// Añadir o quitar investigadores: solo su responsable o el CESAR.
$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!puede_gestionar($u, $p)) {
        pagina_error(403, 'Solo el responsable del proyecto o el CESAR cambian sus miembros.');
    }
    $error = gestionar_miembros($p, $_POST);
    if ($error === '') {
        redirigir('proyecto.php?codigo=' . urlencode($p['codigo']));  // PRG: recargar no repite el cambio
    }
}

$usos = usos_de($p['codigo']);
if ($u['perfil'] === 'investigador') {
    $usos = array_values(array_filter($usos, fn ($uso) => $uso['usuario'] === $u['usuario']));
}
$nh = nucleo_horas($usos);
$coste = $nh * (PRECIO_NUCLEO_HORA[$p['tarifa']] ?? 0);

cabecera($p['codigo'] . ' · ' . $p['titulo'], $u);
?>
<p>Responsable: <?= e(nombre_de($p['responsable'])) ?> ·
   Tarifa <?= e(TARIFAS[$p['tarifa']] ?? $p['tarifa']) ?></p>

<h2>Miembros</h2>
<ul>
  <?php foreach ($p['miembros'] as $m): ?>
  <li><?= e(nombre_de($m)) ?>
    <?php if (puede_gestionar($u, $p)): ?>
    <form method="post" class="en-linea"><input type="hidden" name="accion" value="quitar">
      <input type="hidden" name="investigador" value="<?= e($m) ?>"><button>Quitar</button></form>
    <?php endif ?>
  </li>
  <?php endforeach ?>
</ul>

<?php if (puede_gestionar($u, $p)): ?>
<form method="post" class="en-linea">
  <input type="hidden" name="accion" value="anadir">
  <?php if ($error !== ''): ?><p class="error"><?= e($error) ?></p><?php endif ?>
  <select name="investigador">
    <?php foreach (usuarios_con_perfil('investigador') as $i): ?>
      <?php if (!in_array($i['usuario'], $p['miembros'], true)): ?>
      <option value="<?= e($i['usuario']) ?>"><?= e($i['nombre']) ?></option>
      <?php endif ?>
    <?php endforeach ?>
  </select>
  <button>Añadir al proyecto</button>
</form>
<?php endif ?>

<h2><?= $u['perfil'] === 'investigador' ? 'Tu consumo' : 'Consumo' ?></h2>
<table>
  <tr><th>Fecha</th><th>Persona</th><th>Máquina</th><th>Núcleos</th><th>Horas</th><th>Núcleo-horas</th></tr>
  <?php foreach ($usos as $uso): ?>
  <tr>
    <td><?= e($uso['fecha']) ?></td>
    <td><?= e(nombre_de($uso['usuario'])) ?></td>
    <td><?= e($uso['maquina']) ?></td>
    <td class="num"><?= (int) $uso['nucleos'] ?></td>
    <td class="num"><?= number_format((float) $uso['horas'], 1, ',', '.') ?></td>
    <td class="num"><?= number_format($uso['nucleos'] * $uso['horas'], 1, ',', '.') ?></td>
  </tr>
  <?php endforeach ?>
</table>
<p><strong>Total: <?= number_format($nh, 1, ',', '.') ?> núcleo-horas ·
   estimación <?= number_format($coste, 2, ',', '.') ?> €</strong> (precios de ejemplo)</p>
<?php
pie();
