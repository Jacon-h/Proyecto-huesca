<?php
// Conexión del panel con su base de PostgreSQL (BIFI_DB). Todos los datos del panel están ahí.
declare(strict_types=1);

/**
 * Abre la conexión con los datos que compose.yaml pone en el entorno del contenedor:
 * BIFI_HOST (el servicio "db"), y BIFI_DB, BIFI_USER y BIFI_PASSWORD, que salen de .env.
 * En el código no hay ni una contraseña. Si falta alguna variable o la conexión falla, lanza PDOException.
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
        // Preparadas de verdad en el servidor: la consulta y los datos viajan por separado, así que un
        // dato nunca se interpreta como SQL. Es el valor por defecto de pdo_pgsql; se deja escrito a propósito.
        PDO::ATTR_EMULATE_PREPARES   => false,
    ]);
}

/** Una sola conexión por petición, abierta la primera vez que se necesita. */
function bd(): PDO
{
    static $conexion = null;
    return $conexion ??= conectar_bifi();
}

/**
 * Todas las consultas del panel pasan por aquí: prepare() con la consulta fija y execute() con los datos.
 * Los valores van siempre en $parametros (marcadores ?), nunca pegados al texto del SQL.
 */
function consultar(string $sql, array $parametros = []): PDOStatement
{
    $consulta = bd()->prepare($sql);
    $consulta->execute($parametros);
    return $consulta;
}

/**
 * Lo que dice el gestor de esta conexión: quién soy, en qué base, desde qué IP me ve (Maestro),
 * con qué codificación y colación (P7) y qué límites me aplica (P5, P6).
 */
function estado_bifi(PDO $bd): array
{
    $sql = "SELECT current_user                              AS usuario,
                   current_database()                        AS base,
                   host(inet_client_addr())                  AS ip_cliente,
                   host(inet_server_addr())                  AS ip_servidor,
                   pg_encoding_to_char(d.encoding)           AS codificacion,
                   CASE d.datlocprovider WHEN 'i' THEN 'icu ' || d.daticulocale
                                         ELSE 'libc ' || d.datcollate END AS colacion,
                   current_setting('statement_timeout')      AS statement_timeout,
                   r.rolconnlimit                            AS limite_conexiones
            FROM pg_database d, pg_roles r
            WHERE d.datname = current_database() AND r.rolname = current_user";
    $consulta = $bd->prepare($sql);
    $consulta->execute();
    return $consulta->fetch();
}
