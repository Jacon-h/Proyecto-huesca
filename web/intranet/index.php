<?php
$servicios = [
    'Servidor Web (Apache)'        => ['host' => '127.0.0.1', 'port' => 80,   'icono' => '🌐'],
    'Base de Datos (PostgreSQL)'   => ['host' => 'db',        'port' => 5432, 'icono' => '🗄️'],
    'Servicio Git (Forgejo)'       => ['host' => 'git',       'port' => 3000, 'icono' => '📦'],
    'Servidor DNS (BIND9)'         => ['host' => 'host.docker.internal', 'port' => 53, 'icono' => '🌍']
];

function verificar_puerto($host, $port) {
    $connection = @fsockopen($host, $port, $errno, $errstr, 1);
    if (is_resource($connection)) {
        fclose($connection);
        return true;
    }
    return false;
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard Sede Huesca</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&display=swap" rel="stylesheet">
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Inter', sans-serif; }
        body { background: #0b132b; color: #f1f5f9; min-height: 100vh; padding: 40px 20px; display: flex; justify-content: center; }
        .dashboard { width: 100%; max-width: 900px; }

        /* Header */
        .header { margin-bottom: 35px; border-bottom: 1px solid #1e293b; padding-bottom: 15px; display: flex; align-items: center; justify-content: space-between; }
        .header h1 { font-size: 1.75rem; font-weight: 700; color: #38bdf8; letter-spacing: -0.5px; }
        .header .badge-env { background: #1e293b; color: #94a3b8; padding: 4px 12px; border-radius: 20px; font-size: 0.8rem; font-weight: 600; border: 1px solid #334155; }

        /* Grid y Secciones */
        h2 { font-size: 1.1rem; text-transform: uppercase; letter-spacing: 1px; color: #64748b; margin-bottom: 15px; font-weight: 600; }
        .grid-servicios { display: grid; grid-template-columns: repeat(auto-fit, minmax(400px, 1fr)); gap: 15px; margin-bottom: 35px; }

        /* Targeta de Servicio */
        .card { background: #1c2541; border: 1px solid #2e3856; border-radius: 12px; padding: 18px 22px; display: flex; align-items: center; justify-content: space-between; transition: transform 0.2s, border-color 0.2s; }
        .card:hover { transform: translateY(-2px); border-color: #38bdf8; }
        .info-servicio { display: flex; align-items: center; gap: 14px; }
        .icono { font-size: 1.5rem; background: #0b132b; padding: 10px; border-radius: 10px; border: 1px solid #2e3856; }
        .detalles .nombre { font-weight: 600; font-size: 1rem; color: #ffffff; }
        .detalles .host { font-size: 0.8rem; color: #94a3b8; margin-top: 2px; }

        /* Badges de estado */
        .status { display: flex; align-items: center; gap: 8px; font-size: 0.85rem; font-weight: 700; padding: 6px 14px; border-radius: 20px; }
        .status-ok { background: rgba(34, 197, 94, 0.15); color: #4ade80; border: 1px solid rgba(34, 197, 94, 0.3); }
        .status-fail { background: rgba(239, 68, 68, 0.15); color: #f87171; border: 1px solid rgba(239, 68, 68, 0.3); }
        .dot { width: 8px; height: 8px; border-radius: 50%; }
        .status-ok .dot { background: #22c55e; box-shadow: 0 0 8px #22c55e; }
        .status-fail .dot { background: #ef4444; box-shadow: 0 0 8px #ef4444; }

        /* Accesos Rápidos */
        .grid-links { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; }
        .btn-link { background: #1c2541; border: 1px solid #2e3856; color: #38bdf8; text-decoration: none; padding: 18px; border-radius: 12px; text-align: center; font-weight: 700; font-size: 0.95rem; transition: all 0.2s ease; display: flex; flex-direction: column; align-items: center; gap: 8px; }
        .btn-link:hover { background: #38bdf8; color: #0b132b; border-color: #38bdf8; transform: translateY(-3px); box-shadow: 0 8px 20px rgba(56, 189, 248, 0.25); }
    </style>
</head>
<body>
    <div class="dashboard">
        <div class="header">
            <h1>Intranet Sede Huesca</h1>
            <span class="badge-env">Infraestructura Activa</span>
        </div>

        <h2>Estado del Sistema</h2>
        <div class="grid-servicios">
            <?php foreach ($servicios as $nombre => $info): ?>
                <?php $estado = verificar_puerto($info['host'], $info['port']); ?>
                <div class="card">
                    <div class="info-servicio">
                        <span class="icono"><?= $info['icono'] ?></span>
                        <div class="detalles">
                            <div class="nombre"><?= $nombre ?></div>
                            <div class="host"><?= $info['host'] ?>:<?= $info['port'] ?></div>
                        </div>
                    </div>
                    <div class="status <?= $estado ? 'status-ok' : 'status-fail' ?>">
                        <span class="dot"></span>
                        <?= $estado ? 'ONLINE' : 'OFFLINE' ?>
                    </div>
                </div>
            <?php endforeach; ?>
        </div>

        <h2>Accesos Rápidos</h2>
        <div class="grid-links">
            <a href="http://gns3.huesca.empresa.lan" class="btn-link" target="_blank">
                <span>GNS3</span>
            </a>
            <a href="http://git.huesca.empresa.lan" class="btn-link" target="_blank">
                <span>GIT</span>
            </a>
            <a href="http://www.huesca.empresa.lan" class="btn-link" target="_blank">
                <span>WEB</span>
            </a>
            <a href="http://intranet.huesca.empresa.lan" class="btn-link">
                <span>INTRANET</span>
            </a>
        </div>
    </div>
</body>
</html>