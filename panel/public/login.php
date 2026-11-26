<?php
declare(strict_types=1);

require __DIR__ . '/../comun/arranque.php';

if (usuario_actual() !== null) {
    redirigir('index.php');
}

$error = '';
$usuario = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // También en el login: sin esto, otra web podría meter a la víctima en una cuenta del atacante
    // (login CSRF) y todo lo que hiciera después quedaría en esa cuenta.
    exigir_csrf();
    $usuario = trim((string) ($_POST['usuario'] ?? ''));
    $clave = (string) ($_POST['clave'] ?? '');
    if (entrar($usuario, $clave)) {
        redirigir('index.php');
    }
    $error = 'Usuario o contraseña incorrectos.';
}

cabecera('Entrar');
?>
<form method="post" class="tarjeta">
  <?= campo_csrf() ?>
  <?php if ($error !== ''): ?><p class="error"><?= e($error) ?></p><?php endif ?>
  <label>Usuario <input name="usuario" value="<?= e($usuario) ?>" autocomplete="username" required autofocus></label>
  <label>Contraseña <input name="clave" type="password" autocomplete="current-password" required></label>
  <button>Entrar</button>
</form>
<?php
pie();

