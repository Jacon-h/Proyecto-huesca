# db/ · ASGBD

Lo que hace que la base de datos nazca con su tabla, sus filas y su usuario de la web
sin intervención. No hay contraseñas escritas aquí: llegan desde `.env`.

## Qué hay

| Fichero | Qué hace |
|---|---|
| `01_esquema.sql` | Crea la tabla `inventario` y su secuencia de IDs. |
| `02_datos.sql` | Carga los 20 registros de material de la sede. |
| `03_usuario_web.sh` | Crea el usuario de la web (`DB_USER`) con permiso de **leer, insertar y editar, pero no borrar**. |

## Dos usuarios, dos papeles

| Usuario | Quién lo usa | Qué puede hacer |
|---|---|---|
| `postgres` | Solo el administrador (contraseña `POSTGRES_PASSWORD`) | Todo. Es el dueño de la tabla. |
| `DB_USER` (contraseña `DB_PASSWORD`) | La web (Apache + PHP) | `SELECT`, `INSERT` y `UPDATE` sobre `inventario`. Un `DELETE` da `permission denied`. |

Así, si la web se viese comprometida, no podría vaciar la tabla.

## En qué orden se ejecuta

PostgreSQL ejecuta los ficheros de esta carpeta en orden alfabético, **solo la primera vez**,
cuando el volumen de datos está vacío: esquema, datos y, por último, el usuario de la web.

La imagen de PostgreSQL crea el administrador y la base con `POSTGRES_USER`, `POSTGRES_PASSWORD` y `POSTGRES_DB`;
`03_usuario_web.sh` lee `DB_USER` y `DB_PASSWORD` del entorno del contenedor (los pasa `compose.yaml` desde `.env`).

## Registro (logs)

El servicio `db` arranca con `log_connections=on` y `log_disconnections=on`, así que `docker compose logs db`
muestra el arranque (`ready to accept connections`), cada conexión (`connection authorized`) y los errores
(`password authentication failed`). Ver las pruebas 5 a 9 de [`docs/comprobaciones.md`](../docs/comprobaciones.md).

## Comprobación

    docker compose exec -T db psql -U postgres -d "$DB_NAME" -c "SELECT COUNT(*) FROM inventario;"
    docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c "DELETE FROM inventario WHERE id = 1;"

La primera debe devolver 20; la segunda, `ERROR:  permission denied for table inventario`.

## Volver a empezar desde cero

Estos ficheros no se repiten si el volumen ya existe (por ejemplo, si cambias una contraseña en `.env`
o si la base se creó antes de que existiera `03_usuario_web.sh`). Para recrear solo la base:

    sudo ./instalar.sh reiniciar bd --si

Esto **borra** los datos de la base y la crea de nuevo con las 20 filas iniciales. No toca LDAP ni Forgejo.
(No uses `docker compose down -v`: borraría también los datos de LDAP.)
