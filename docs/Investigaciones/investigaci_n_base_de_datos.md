# Investigación · Base de datos

Gestor: **PostgreSQL 16.15** en Docker · Sede Huesca · ASGBD RA1

> **Convenciones y entorno de ejecución**
> - Servidor de prueba: usuario `prueba`, carpeta `~/Proyecto-huesca`, IP `192.168.6.84` (y `192.168.6.2`). Servidor definitivo: `/home/asir2/proyecto_huesca`.
> - Nombres reales: servicio `db`, contenedor `mi-postgres`, base de datos `mi_base_datos`, administrador `postgres` (área de datos) y usuario web `usuario_app`. Volumen: `datos` (`proyecto-huesca_datos`).
> - Salidas integradas directamente desde las evidencias obtenidas en el servidor (`evidencias/datos-bd.txt`, `evidencias/fallos-bd.txt`).

---

## Ampliación del encargo · Necesidades de la base de datos

| # | Necesidad a cubrir | Cumplimiento | Estado |
| --- | --- | --- | --- |
| D1 | Gestor del estándar, versión mayor fijada, fecha límite de soporte y plan de migración | Pregunta 4 | Cumplida: `postgres:16.15` |
| D2 | Sin credenciales en repositorio ni historial; paso seguro mediante ficheros | Pregunta 3 | `.env` fuera de Git; limpieza de `app.ini` en Forgejo |
| D3 | Usuario de aplicación web restringido sin privilegios de superusuario ni borrado | Pregunta 3 | Cumplida: `usuario_app` (lectura, inserción y modificación; sin `DELETE`) |
| D4 | `docker compose up -d` en servidor limpio inicializa esquema y datos automáticos | Pregunta 2 | Cumplida: scripts en `/docker-entrypoint-initdb.d/` |
| D5 | Reinicio automático, comprobación de estado (*healthcheck*) y dependencias | Pregunta 6 | Cumplida y verificada tras `sudo reboot` |
| D6 | Copia de seguridad externa restaurada con éxito en un gestor desde cero | Pregunta 8 | Cumplida: transferencia SSH/SCP a equipo local Windows |
| D7 | Registro de conexiones activo e identificación de acceso rechazado | Pregunta 7 | Cumplida: `log_connections=on` |
| D8 | Plan de verificación y comprobaciones documentado y ejecutado | Sección Comprobación | Ejecutado por el equipo de administración |

---

## Preguntas sobre nuestro gestor

### 1. Qué hay dentro del contenedor · CE a · teoría 1, 2 y 4

**Procesos del contenedor.** Inspección real con `docker top mi-postgres`:

```
UID        PID    PPID   CMD
dnsmasq    38481  38457  postgres -c log_connections=on -c log_disconnections=on
dnsmasq    38539  38481  postgres: checkpointer
dnsmasq    38540  38481  postgres: background writer
dnsmasq    38542  38481  postgres: walwriter
dnsmasq    38543  38481  postgres: autovacuum launcher
dnsmasq    38544  38481  postgres: logical replication launcher
```

| Proceso | Función y cometido dentro del gestor |
| --- | --- |
| `postgres` (PID 1) | Proceso maestro (*postmaster*). Escucha conexiones en la red/socket y gestiona subprocesos. |
| `checkpointer` | Vuelca periódicamente las páginas de memoria modificadas (*dirty pages*) hacia los archivos en disco. |
| `background writer` | Vuelca páginas modificadas de forma gradual para aliviarlas del checkpointer principal. |
| `walwriter` | Escribe los registros de transacciones (*Write-Ahead Logging*) a disco antes de confirmar un commit. |
| `autovacuum launcher` | Lanza tareas automáticas de limpieza para reclamar espacio de tuplas muertas y actualizar estadísticas. |
| `logical replication launcher` | Administra la replicación lógica de datos hacia nodos secundarios. |

*Aclaración sobre `UID 999 / dnsmasq`:* El comando `docker top` muestra los datos según el archivo `/etc/passwd` del **anfitrión**. El UID `999` corresponde al usuario `postgres` dentro del contenedor, pero la máquina anfitriona asigna dicho UID al servicio `dnsmasq`. Es un mapeo numérico de IDs normal en entornos aislados.

**Proceso ante conexión web:** Al abrir una sesión HTTP la aplicación abre una conexión a PostgreSQL. El *postmaster* genera inmediatamente un proceso hijo:
```
dnsmasq    39102  38481  postgres: usuario_app mi_base_datos 172.19.0.3(48192) idle
```
Al finalizar la ejecución del script PHP, dicho subproceso se destruye inmediatamente.

**Ubicación física de la tabla en disco:**
```bash
prueba@prueba:~/Proyecto-huesca$ docker exec mi-postgres psql -U postgres -d mi_base_datos -c "SELECT pg_relation_filepath('inventario');"
 pg_relation_filepath 
----------------------
 base/16384/16385
```
El archivo de datos real se encuentra en la ruta `/var/lib/postgresql/data/base/16384/16385`, guardado dentro del volumen del anfitrión `/var/lib/docker/volumes/proyecto-huesca_datos/_data/`.

**Estructura del directorio de datos:**
```
drwx------  6 postgres postgres  4096 base
drwx------  2 postgres postgres  4096 global
-rw-------  1 postgres postgres  5743 pg_hba.conf
-rw-------  1 postgres postgres     3 PG_VERSION
drwx------  3 postgres postgres  4096 pg_wal
-rw-------  1 postgres postgres 30050 postgresql.conf
```
- `pg_wal/`: Contiene el registro WAL. **Es crítico:** garantiza que no se pierdan datos ante cortes de electricidad. Borrar este directorio corrompe la base de datos de manera irreversible.
- `PG_VERSION`: Almacena la versión mayor (`16`). Determina si la imagen debe ejecutar la inicialización o saltársela.

---

### 2. Cómo nació nuestro gestor · CE f, i · teoría 8 · D4

**Primer arranque vs Arranques posteriores:**
- **Primer arranque (Volumen vacío):** El punto de entrada `docker-entrypoint.sh` detecta que el directorio `/var/lib/postgresql/data` no contiene un clúster. Invoca `initdb`, crea las bases por defecto, levanta un servidor temporal escuchando únicamente por socket Unix y ejecuta todos los scripts montados en `/docker-entrypoint-initdb.d/` por orden alfabético.
- **Arranques posteriores:** El script encuentra el archivo `PG_VERSION`. Imprime en el registro `Skipping initialization` y arranca directamente el servicio principal en el puerto 5432 sin volver a ejecutar los scripts de inicialización.

**Comportamiento de `ON_ERROR_STOP=1` en el primer arranque:**
Los scripts SQL ejecutados por la imagen oficial incluyen la bandera `ON_ERROR_STOP=1`. Si un archivo `.sql` de inicialización contiene una sintaxis errónea (ej. `SELEC 1;`), el proceso `psql` aborta la ejecución con un código de salida distinto de cero y el contenedor se detiene antes de abrir la red. Dado que la carpeta ya contiene parte de la estructura y el archivo `PG_VERSION`, en el siguiente arranque la imagen **omitirá la inicialización**. Por ello, para aplicar la corrección del SQL es **imprescindible eliminar el volumen** con `docker volume rm` antes de volver a levantar.

**Resolución del requisito D4:**
Se montan 3 archivos en `/docker-entrypoint-initdb.d` en modo lectura (`:ro`):
1. `01_esquema.sql`: Define las tablas e índices.
2. `02_datos.sql`: Inserta los registros iniciales de la sede.
3. `03_usuario_web.sh`: Crea el rol `usuario_app` asignando las variables de entorno.

Script `03_usuario_web.sh`:
```bash
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 -v usuario="$DB_USER" -v clave="$DB_PASSWORD" \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
CREATE ROLE :"usuario" LOGIN PASSWORD :'clave';
GRANT USAGE ON SCHEMA public TO :"usuario";
GRANT SELECT, INSERT, UPDATE ON inventario TO :"usuario";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :"usuario";
SQL
```

---

### 3. Quién entra y cómo · CE f, j · teoría 2, 3 y 8 · D2 y D3

#### 3.1 Auditoría de credenciales

| Credencial | Destinado a | Ubicación | Visibilidad / Acceso |
| --- | --- | --- | --- |
| `POSTGRES_PASSWORD` | Administrador `postgres` | Fichero `.env` $\rightarrow$ Entorno | Propietario en servidor / `docker inspect` |
| `DB_PASSWORD` | Usuario `usuario_app` | Fichero `.env` $\rightarrow$ Entorno | Propietario en servidor / `docker inspect` |
| `INTRANET_CLAVE` | Intranet Apache | Hash en `.htpasswd` | Fichero accesible en modo lectura |

**Hallazgo y limpieza de seguridad (Forgejo):**
Durante la auditoría del repositorio se detectó que el archivo `app.ini` de Forgejo había sido versionado en commits antiguos incluyendo claves secretas en claro (`SECRET_KEY`, `INTERNAL_TOKEN`, `JWT_SECRET`).
- **Acciones correctivas tomadas el 10/11/2026:**
  1. Eliminación del archivo del seguimiento con `git rm --cached`.
  2. Purgado completo del historial de Git mediante `git filter-repo --invert-paths --path forgejo-docker/`.
  3. Ejecución de `git push --force` y rotación completa de todos los tokens del gestor.

#### 3.2 Gestión de secretos y permisos (`700` vs `644`)

Para proteger los secretos en el servidor anfitrión:
- La carpeta contenedora `secrets/` se configura con permisos `700` (`drwx------`), restringiendo el acceso exclusivamente al usuario propietario y al superusuario `root`.
- Los archivos individuales de contraseñas dentro de la carpeta disponen de permisos `644` (`-rw-r--r--`). Esto es necesario porque cuando Docker Compose monta un archivo de secreto dentro del contenedor en `/run/secrets/`, respeta los permisos del archivo. Como el proceso interno corre bajo el UID `999` (`postgres`), requiere permisos de lectura en el archivo para que el gestor pueda leer la clave durante el arranque.

#### 3.3 Separación de privilegios de usuario (D3)

El usuario `usuario_app` creado para la web no posee el atributo de superusuario.

```
Role name   | Attributes
-------------+------------------------------------------------------------
postgres    | Superuser, Create role, Create DB, Replication, Bypass RLS
usuario_app | 

Access privileges for table "inventario":
public | inventario | table | postgres=arwdDxt/postgres+
       |            |       | usuario_app=arw/postgres
```
- Privilegios concedidos a `usuario_app`: `a` (append/INSERT), `r` (read/SELECT), `w` (write/UPDATE).
- **Protección:** Se omite explícitamente el permiso `d` (DELETE). Ante una inyección SQL en la web, el atacante no podrá eliminar registros de la base de datos.

#### 3.4 Control de autenticación y reglas de `pg_hba.conf`

Mecanismo de autenticación configurado en `/var/lib/postgresql/data/pg_hba.conf`:

```
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
host    all             all             all                     scram-sha-256
```

**Mecanismo de defensa frente a la enumeración de usuarios:**
- Conexión local mediante socket Unix (`local`): Aplica la regla `trust`. Si se intenta conectar con un usuario inexistente (ej. `psql -U falso`), el gestor responde de inmediato: `FATAL: role "falso" does not exist`.
- Conexión por red TCP (desde la web u otros contenedores): Aplica la regla `scram-sha-256`. Si un cliente intenta conectarse con un usuario inexistente, PostgreSQL **devuelve exactamente el mismo mensaje que si la contraseña fuera errónea**: `FATAL: password authentication failed for user "falso"`. Esto impide que un atacante externo determine qué nombres de usuario existen escaneando el puerto. El motivo real (`Role "falso" does not exist`) se escribe de forma segura únicamente en los registros internos del servidor.

---

### 4. Qué versión y hasta cuándo · CE c, d · D1

- **Versión en uso:** `PostgreSQL 16.15` (Imagen `postgres:16.15`).
- **Soporte oficial:** La rama 16 de PostgreSQL recibe parches de seguridad y correcciones hasta el **9 de noviembre de 2028**.
- **Prueba de cambio de versión mayor:** Se sustituyó la etiqueta por `postgres:17` sobre el mismo volumen de datos. El contenedor abortó el arranque notificando en el registro:
  ```
  FATAL: database files are incompatible with server
  DETAIL: The data directory was initialized by PostgreSQL version 16, which is not compatible with this version 17.11.
  ```
- **Procedimiento de actualización mayor:** Para migrar a una versión mayor nueva se requiere exportar los datos con `pg_dump`, instanciar la nueva versión en un volumen limpio y restaurar la copia.

---

### 5. Qué necesita la máquina · CE e

Mediciones reales obtenidas en el servidor anfitrión:

| Recurso hardware | Consumo medido | Método de medición | Disponible en Servidor | ¿Aguanta el doble? |
| --- | --- | --- | --- | --- |
| Memoria RAM (Reposo) | 19,57 MiB | `docker stats --no-stream mi-postgres` | 5,2 GiB | Sí, sin problemas |
| Memoria RAM (Carga) | 21,58 MiB | `docker stats` durante 300 peticiones | 5,2 GiB | Sí, sin problemas |
| Disco (Base de Datos) | 47 MB | `docker exec mi-postgres du -sh /var/lib/...` | 25 GB (16 GB libres) | Sí |
| Disco (Copia Backup) | 5,1 KB | `ls -lh ~/backups/` | 16 GB libres | Sí |
| Registro WAL (`pg_wal`) | 17 MB | `docker exec mi-postgres du -sh .../pg_wal` | 16 GB libres | Sí |
| Uso de CPU | 0.20% (Reposo) / 40% (Ráfaga) | `docker stats` | 4 Núcleos | Sí |

Parámetro clave de memoria de PostgreSQL: `shared_buffers = 128MB`.

---

### 6. Arranque, parada y caídas · CE f, i · D5

- **Parada ordenada (`docker stop`):** Envía la señal `SIGTERM`. PostgreSQL finaliza las transacciones activas, realiza un checkpoint y cierra de forma limpia (`database system was shut down`).
- **Parada abrupta (`docker kill`):** Envía `SIGKILL`. El proceso se interrumpe inmediatamente. Al arrancar de nuevo, el gestor detecta un estado inconsistente e inicia la **recuperación automática releyendo el WAL**:
  ```
  LOG: database system was interrupted; last known up at 2026-11-10 08:40:12 UTC
  LOG: automatic recovery in progress
  LOG: redo starts at 0/15A2040
  LOG: database system is ready to accept connections
  ```

Prueba de reinicio del servidor anfitrión (`sudo reboot`): Los servicios levantan de forma automática en el orden correcto gracias a la directiva `restart: unless-stopped` y al estado de salud `healthcheck`.

---

### 7. Qué cuenta cuando falla · CE h, i · D7

El servicio se ejecuta con las opciones de auditoría activa: `command: ["postgres", "-c", "log_connections=on", "-c", "log_disconnections=on"]`.

**Matriz de fallos provocados en las pruebas:**

| # | Fallo provocado | Lo que ve el cliente | Lo que escribe el registro (`docker logs`) | Tipo de error |
| --- | --- | --- | --- | --- |
| 1 | Contraseña errónea | `FATAL: password authentication failed...` | `FATAL: password authentication failed for user "usuario_app"... DETAIL: Connection matched file... line 128` | Autenticación |
| 2 | Usuario inexistente (TCP) | `FATAL: password authentication failed...` | `FATAL: password authentication failed... DETAIL: Role "usuario_falso" does not exist.` | Autenticación |
| 3 | Base de datos inexistente | `FATAL: database "db_falsa" does not exist` | `FATAL: database "db_falsa" does not exist` | Conexión |
| 4 | Intento de `DELETE` (Web) | `ERROR: permission denied for table inventario` | `ERROR: permission denied for table inventario STATEMENT: DELETE FROM inventario...` | Autorización |
| 5 | Consulta a tabla inexistente | `ERROR: relation "tabla_falsa" does not exist` | `ERROR: relation "tabla_falsa" does not exist at character 15` | Consulta SQL |
| 6 | Acceso fuera de red | `Connection refused / timed out` | *Ninguna entrada registrada* (No llega al proceso) | Red |
| 7 | Arranque sin clave admin | Contenedor detenido con código 1 | `Error: Database is uninitialized and superuser password is not specified...` | Inicialización |
| 8 | Error de sintaxis en SQL | Contenedor detenido con código 3 | `psql:/docker-entrypoint-initdb.d/01.sql: ERROR: syntax error at or near "SELEC"` | Inicialización |
| 9 | Incompatibilidad de versión | Contenedor en ciclo `Restarting` | `FATAL: database files are incompatible with server... initialized by version 16` | Compatibilidad |

---

### 8. Copias · W6, D6

Generación y extracción de copia de seguridad en caliente con `pg_dump` desde un cliente externo (Windows) mediante SSH/SCP:

```powershell
PS C:\WINDOWS\system32> ssh -i $env:USERPROFILE\.ssh\id_ed25519 prueba@192.168.6.2 "mkdir -p ~/backups && docker exec mi-postgres pg_dump -U postgres -d mi_base_datos --clean --if-exists --no-owner > ~/backups/backup_2026-11-09.sql"
PS C:\WINDOWS\system32> scp -i $env:USERPROFILE\.ssh\id_ed25519 prueba@192.168.6.2:backups/backup_2026-11-09.sql .
backup_2026-11-09.sql                        100% 5188     1.7MB/s   00:00
PS C:\WINDOWS\system32> Get-ChildItem backup_2026-11-09.sql

    Directorio: C:\WINDOWS\system32

Mode                LastWriteTime         Length Name
----                -------------         ------ ----
-a----       10/11/2026      9:49           5188 backup_2026-11-09.sql
```

Restauración probada en un contenedor PostgreSQL completamente vacío:
```bash
docker run -d --name pg-restore-test -e POSTGRES_PASSWORD=test postgres:16.15
docker exec pg-restore-test psql -U postgres -c "CREATE DATABASE mi_base_datos;"
docker exec -i pg-restore-test psql -U postgres -d mi_base_datos < backup_2026-11-09.sql
docker exec pg-restore-test psql -U postgres -d mi_base_datos -c "SELECT count(*) FROM inventario;"
# Devuelve: 20 filas cargadas correctamente.
```

---

## Investigación · Qué gestor y por qué

### Comparativa · CE b

| Criterio | PostgreSQL | MariaDB | MySQL | SQL Server | Oracle Database | SQLite |
| --- | --- | --- | --- | --- | --- | --- |
| **Mantenedor** | PostgreSQL Group | MariaDB Foundation | Oracle Corp. | Microsoft | Oracle Corp. | D. Richard Hipp |
| **Licencia** | PostgreSQL (Libre) | GPL v2 (Libre) | GPL v2 / Comercial | Propietaria | Propietaria | Dominio Público |
| **Edición Gratuita** | Sin límites | Community Server | Community Server | Express (10GB límit) | Free (12GB límit) | Completa |
| **Arquitectura** | Cliente/Servidor | Cliente/Servidor | Cliente/Servidor | Cliente/Servidor | Cliente/Servidor | Embebido (Librería) |
| **Modelo Conexión** | Proceso por conexión | Hilo por conexión | Hilo por conexión | Hilos compartidos | Procesos / Hilos | Proceso de Aplicación |
| **Puerto por Defecto** | 5432/TCP | 3306/TCP | 3306/TCP | 1433/TCP | 1521/TCP | Ninguno |
| **Copia en Caliente** | `pg_dump` | `mariadb-backup` | `mysqldump` | `BACKUP DATABASE` | RMAN | API / `VACUUM INTO` |
| **Ventaja principal** | Estándar SQL riguroso | Copia física libre | Compatibilidad CMS | Ecosistema MS | Altas prestaciones | Cero administración |
| **Inconveniente** | Proceso por conexión | Versiones no LTS | Copia física de pago | Licencia muy cara | Muy complejo | Bloqueo por archivo |

**DBaaS (Base de Datos en la Nube):** Amazon RDS PostgreSQL `db.t4g.micro` (~13$/mes). No requerida en la sede por exigir autohospedaje local en servidor propio.

---

### Comprobación · CE g, j · D8

Plan de comprobación ejecutado en la sede:

| # | Comprobación | Comando | Resultado Esperado |
| --- | --- | --- | --- |
| 1 | Estado del gestor | `docker compose ps` | `mi-postgres` estado `healthy` |
| 2 | Versión exacta | `docker exec mi-postgres psql -U postgres -tAc "SHOW server_version;"` | `16.15 (Debian 16.15-1.pgdg13+2)` |
| 3 | Conteo de datos | `docker exec mi-postgres psql -U postgres -d mi_base_datos -tAc "SELECT count(*) FROM inventario;"` | `20` |
| 4 | Web sin borrado | `docker exec -e PGPASSWORD=*** mi-postgres psql -h db -U usuario_app -d mi_base_datos -c "DELETE FROM inventario;"` | `ERROR: permission denied for table inventario` |
| 5 | Aislamiento red | `docker port mi-postgres` | Salida vacía (sin puertos expuestos) |
| 6 | Verificación copia | `scp -i ... prueba@192.168.6.2:backups/backup_2026-11-09.sql .` | Descarga completada de 5188 bytes |
| 7 | Reinicio servidor | `sudo reboot` $\rightarrow$ `docker compose ps` | Todos los servicios `Up` y `healthy` |

*Comprobación ejecutada por:* **Álvaro Rivero** · *Fecha:* **10/11/2026** · *Estado:* **Verificado al 100%.**

---

## Contradicciones encontradas y corregidas

1. **Exposición del puerto 5432:** Se eliminó la directiva `ports: ["5432:5432"]` del compose original para cumplir estrictamente con el requisito de aislamiento W5.
2. **Acceso superusuario desde la web:** Se sustituyó la conexión directa como `postgres` por el usuario con privilegios limitados `usuario_app`.
3. **Limpieza de historial Git:** Se purgaron tokens versionados por error en Forgejo (`app.ini`) aplicando `git filter-repo`.
4. **Registro de fallos de autenticación:** Se activó el registro explícito `log_connections=on` para auditoría de accesos denegados.

---

## Fuentes

- **PostgreSQL 16 Documentation:** https://www.postgresql.org/docs/16/index.html (Consultado: 10/11/2026).
- **Docker Official Image Postgres:** https://hub.docker.com/_/postgres (Consultado: 10/11/2026).
- **MariaDB Foundation:** https://mariadb.org/about/ (Consultado: 10/11/2026).