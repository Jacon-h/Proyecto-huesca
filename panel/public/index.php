<?php
declare(strict_types=1);

require __DIR__ . '/../comun/arranque.php';

$u = exigir_login();
$proyectos = proyectos_visibles($u);

cabecera('Proyectos', $u);
if ($proyectos === []) {
    echo '<p>No tienes proyectos.</p>';
} else {
    ?>
<table>
  <tr><th>Código</th><th>Título</th><th>Responsable</th><th>Tarifa</th><th>Núcleo-horas</th></tr>
  <?php foreach ($proyectos as $p): ?>
  <tr>
    <td><a href="proyecto.php?codigo=<?= urlencode($p['codigo']) ?>"><?= e($p['codigo']) ?></a></td>
    <td><?= e($p['titulo']) ?></td>
    <td><?= e(nombre_de($p['responsable'])) ?></td>
    <td><?= e(TARIFAS[$p['tarifa']] ?? $p['tarifa']) ?></td>
    <td class="num"><?= number_format(nucleo_horas(usos_de($p['codigo'])), 1, ',', '.') ?></td>
  </tr>
  <?php endforeach ?>
</table>
    <?php
}
pie();
