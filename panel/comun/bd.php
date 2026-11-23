<?php
// Conexión del panel con su base de PostgreSQL (ASGBD RA2, P1).
// Por ahora el panel guarda sus datos en JSON; aquí solo se comprueba que entra en PostgreSQL desde
// Compose con su propio usuario. La usan public/estado-bd.php y pruebas/estado-bifi.php.
declare(strict_types=1);

/**
 * Abre la conexión con los datos que compose.yaml pone en el entorno del contenedor:
 * BIFI_HOST (el servicio "db"), y BIFI_DB, BIFI_USER y BIFI_PASSWORD, que salen de .env.
 * Si falta alguno o la conexión falla, lanza PDOException con el motivo.
 */
function conectar_bifi(): PDO
{
    $datos = [];
    foreach (['BIFI_HOST', 'BIFI_DB', 'BIFI_USER', 'BIFI_PASSWORD'] as $variable) {
        $valor = getenv($variable);
        if ($valor === false || $valor === '') {
            throw new PDOException("Falta la variable de entorno $variable (compose.yaml / .env)");
        }
        $datos[$variable] = $valor;
    }

    $dsn = sprintf('pgsql:host=%s;port=5432;dbname=%s;connect_timeout=5', $datos['BIFI_HOST'], $datos['BIFI_DB']);
    return new PDO($dsn, $datos['BIFI_USER'], $datos['BIFI_PASSWORD'], [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
}

/**
 * Lo que dice el gestor de esta conexión: quién soy, en qué base, desde qué IP me ve (Maestro),
 * con qué codificación y colación (P7) y qué límites me aplica (P5, P6).
 * Es una consulta fija, sin datos del usuario: no necesita parámetros.
 */
function estado_bifi(PDO $bd): array
{
    $sql = "SELECT current_user                              AS usuario,
                   current_database()                        AS base,
                   host(inet_client_addr())                  AS ip_cliente,
                   host(inet_server_addr())                  AS ip_servidor,
                   pg_encoding_to_char(d.encoding)           AS codificacion,
                   d.datcollate                              AS colacion,
                   current_setting('statement_timeout')      AS statement_timeout,
                   r.rolconnlimit                            AS limite_conexiones
            FROM pg_database d, pg_roles r
            WHERE d.datname = current_database() AND r.rolname = current_user";
    return $bd->query($sql)->fetch();
}
