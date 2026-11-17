<?php
declare(strict_types=1);

require __DIR__ . '/../comun/arranque.php';

if (usuario_actual() !== null) {
    redirigir('index.php');
}

$error = '';
$usuario = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
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
  <?php if ($error !== ''): ?><p class="error"><?= e($error) ?></p><?php endif ?>
  <label>Usuario <input name="usuario" value="<?= e($usuario) ?>" required autofocus></label>
  <label>Contraseña <input name="clave" type="password" required></label>
  <button>Entrar</button>
</form>
<?php
pie();
