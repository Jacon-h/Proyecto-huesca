### BITACORA GRUPO 2

## PRIMERA SEMANA

## 15/09/2026

Hemos clonado el repositorio, y aprendido a hacer commits en github.

Hemos asignado la ip fija 10.2.0.1/24.

## Empezamos con el servicio DNS

Hemos implementado el requisito N1 configurando nuestro propio servidor DNS como la autoridad raíz y fuente oficial para todos los nombres de la sede terminados en huesca.empresa.lan

Para conseguirlo, dejamos la configuración global de BIND9 en su estado base y declaramos la zona directa huesca.empresa.lan en el archivo /etc/bind/named.conf.local. Luego, creamos el fichero de zona /etc/bind/db.empresa.lan asociando directamente la IP 10.2.0.1 a los nombres principales ns1 y srv. Tras validar la sintaxis con named-checkconf y named-checkzone, reiniciamos el servicio y confirmamos mediante dig @10.2.0.1 ns1.huesca.empresa.lan que el servidor responde de forma autoritativa a los nombres de la sede sin depender de servidores externos.

## 16/09/2026

Comenzamos la jornada revisando y analizando la incidencia de DNS que impedía al servidor (10.2.0.1) detectar los portátiles por estar en una red distinta. Sigue en proceso.

Hemos instalado y configurado el servicio ssh y hemos podido conectarnos por ssh al servidor, hemos puesto seguridad para que solo se entre por clave.

Creamos una interfaz virtual nueva, porque no se puede tener una interfaz con dos redes distintas. Con las IPTABLES requeridas.

## 17/09/2026

Despliegue de infraestructura: Instalación de Apache utilizando contenedores con Docker y Docker Compose.

Pruebas y verificación: Comprobación del correcto acceso a la web prototipo mediante la IP en el navegador, validando el servicio tanto por HTTP como por HTTPS.
Seguridad: Instalación y configuración básica del cortafuegos UFW.

También el servidor responde por ns1, ns2, srv, www, intranet, git, db, correo, servidor.

## 18/09/2026

Empezamos el día dividiendonos los bloques faltantes.

El bloque de Forgejo está terminado, el git funciona pero con la IP 192.168.6.105 porque todavia no esta la dns puesta para poner el nombre de git.huesca.empresa.lan

Empezamos con el bloque de Red de la Sede, GNS3 instalado, configurado y funcionando.

Se ha empezado a configurar la pagina web.

Hemos migrado BIND9 A Docker porque antes no estaba en el docker necesario.

## 21/09/2026

Empezamos el día repartiendo los bloques restantes para optimizar el trabajo.

Migración de BIND9 y realización de varias tareas del apartado del servidor.

Empezar parte de bases de datos e intranet. Configuracion GNS3 y servidor secundario.

Investigación dockers y configuración de los mismos en el servidor.

## 22/09/2026

Comprobamos que la migración de BIND9 a Docker funciona correctamente resolviendo los nombres de la sede.

Unificamos Apache y PostgreSQL en un único proyecto de Docker Compose (~/proyecto_huesca), en vez de tenerlos configurados a mano con docker exec. Migramos a él la web pública y la intranet.

Nos encontramos con que la intranet no pedía credenciales y siempre servía la página por defecto de Apache. El problema era que seguía activo el Apache instalado directamente en el sistema además del de Docker, y ambos competían por el puerto 80. Lo solucionamos deshabilitando el Apache nativo (systemctl disable --now apache2) y corrigiendo permisos de los ficheros dentro del contenedor; tras esto, las pruebas con curl devolvieron los códigos esperados (200 en la web pública, 401 con credenciales erróneas en la intranet).

Al restaurar la copia de seguridad de la base de datos sobre el contenedor ya existente nos dieron errores de "relation already exists" y de clave duplicada, porque la tabla ya estaba creada. Los datos no se duplicaban, pero decidimos que para probar copias de seguridad de verdad es mejor restaurar sobre una base de datos limpia en lugar de una que ya tiene los datos.

Configuramos el NAT/redirección de puertos en UFW para que la red interna (GNS3) pueda llegar a los servicios del servidor: puerto 80 (web), 3000 (Forgejo) y 3080 (GNS3).

Añadimos los proxys inversos en Apache para git.huesca.empresa.lan y gns3.huesca.empresa.lan, y actualizamos la zona DNS con el nuevo registro de gns3.

## 23/09/2026

Comprobamos que PostgreSQL no es accesible desde fuera de la red interna (puerto 5432 cerrado), como se esperaba.

Hicimos una nueva copia de seguridad del inventario y la organizamos en una carpeta de backups con nombre por fecha. Esta vez, siguiendo lo aprendido el día anterior, la validamos restaurándola en una base de datos de pruebas nueva en lugar de sobre una ya existente; la restauración se hizo sin errores y se recuperaron las 20 filas correctamente.

Verificamos que el acceso a git.huesca.empresa.lan a través de Apache funciona correctamente: login, exploración de repositorios y operaciones de push/pull, sin incidencias.

## 24/09/2026

Empezamos el día con la prueba de reinicio completo del servidor. Jaime lanzó `sudo reboot` por SSH y la sesión cayó con "Connection reset", como era de esperar.

Tras el arranque comprobamos que los servicios volvían solos: `gns3server`, `ufw` y `docker` quedaron activos, y en el log de `dockerd` se ve cómo recupera `mi-bind9`, `forgejo` y `postgres-db`. Con `systemctl is-enabled` confirmamos que docker, ssh, gns3server y ufw están habilitados. El único aviso fue un WARNING transitorio de GNS3 ("Cannot connect to compute 'local'") que se resolvió solo a los 5 segundos. Docker arrancó unos dos minutos después que gns3server y ufw, y queda pendiente confirmar que es el arranque normal.

Comprobamos también que el servidor usa su propio DNS: un `dig www.wikipedia.org` sin indicar `@` lo atiende `127.0.0.1#53` (el `named` local).


## 25/09/2026

Dedicamos el día a comprobar el DNS secundario (`dns-secundario-1`, 10.5.0.2).

Primero configuramos la zona restringida en el primario: `allow-transfer` y `also-notify` limitados al secundario, de modo que solo él puede pedir la lista completa de nombres.

Después medimos la réplica: validamos la zona con `named-checkzone` (serial 12), reiniciamos `mi-bind9` y consultamos directamente al secundario. `dig @10.5.0.2 prueba-n4c.huesca.empresa.lan` respondía 10.5.0.96 a los 11 segundos, y el SOA tiene el mismo serial en ambos servidores. La réplica es muy inferior al minuto exigido.

Comprobamos el caché: la primera consulta a `www.google.com` tarda 48 ms y la segunda 0 ms, con el TTL ya descontado.

Desde un PC del aula preguntamos explícitamente a nuestro servidor con `nslookup`: `www` e `intranet` se resuelven, pero `www.google.com` devuelve "Query refused", así que el aula no puede usar nuestro DNS para navegar. También comprobamos `git.huesca.empresa.lan` con `curl -I`, que respondió 200 OK.

Por último paramos el primario con `docker stop mi-bind9` (Andreas) para la prueba de caída. La consulta al secundario con el primario parado no quedó capturada, así que queda pendiente repetirla.


## 28/09/2026

Repetimos la consulta al DNS secundario con el primario parado (`docker stop mi-bind9` y `dig @10.5.0.2 www.huesca.empresa.lan`) para cerrar la prueba de caída. Después volvimos a arrancar `mi-bind9` y comprobamos que responde y que el secundario mantiene el mismo serial.

Hicimos un `docker ps` completo tras el reinicio del jueves y verificamos que los siete contenedores están `Up`, y repasamos que DNS, web, intranet, base de datos y Forgejo siguen respondiendo.

Preparación de material para la feria de empleo del 29.


## 29/09/2026

Feria de empleo todo el día.


## 30/09/2026

Al empezar la mañana detectamos un problema, teniamos instalados dos contenedores de postgreSQL.

Al revisar la memoria vimos dos contenedores de PostgreSQL: `mi-postgres` (`postgres:16`) y `postgres-db` (`postgres:16-alpine`). Queríamos quedarnos solo con uno.

Al inspeccionarlos vimos que `mi-postgres` tenía la base `mi_base_datos` vacía, mientras que `postgres-db` tenía la tabla `inventario` con las 20 filas. Además estaban en redes distintas. Al principio pensamos que sobraba `postgres-db`, porque el `index.php` decía `mi-postgres`. Pero la web daba el error `could not translate host name "postgres-db"`: alguien había cambiado el fichero para apuntar a `postgres-db`, que era donde estaban los datos. Comprobar las filas antes de borrar nos evitó perder el inventario.

Nos quedamos con `mi-postgres` y migramos los datos: copia con `pg_dump` en `~/backups`, restauración en `mi_base_datos` (20 filas) y cambio del host en `index.php` a `mi-postgres`. La web muestra PostgreSQL 16.15 y `Filas: 20`. Después eliminamos `postgres-db` y su volumen `asir2_pgdata`.


## 01/10/2026

Continuamos con las comprobaciones finales del proyecto y realizamos las investigaciones web necesarias para completar la documentación de los servicios utilizados.

Investigamos diferentes soluciones y documentación relacionada con los servicios que forman parte de la sede, comparando alternativas y recopilando información sobre su funcionamiento, características y configuración.

También revisamos la documentación de DNS, acceso remoto, servidores web, bases de datos, Forgejo y simulación de red, dejando recogida la información necesaria para justificar las elecciones realizadas en el proyecto.

En la parte de Forgejo, comprobamos la configuración de la organización huesca, la cuenta Profesor y las plantillas y etiquetas necesarias para las incidencias.

## 02/10/2026

Continuamos con la investigación sobre Docker y contenedores, centrándonos en cómo se utilizan para desplegar y mantener los diferentes servicios de la sede.

Revisamos la utilización de Docker Compose, los contenedores utilizados en el proyecto, las redes, los volúmenes y la forma de comprobar que los servicios se encuentran funcionando correctamente mediante docker ps y los registros de los contenedores.

También revisamos la configuración de Apache y PostgreSQL dentro del proyecto proyecto_huesca, comprobando la relación entre los diferentes contenedores y los servicios que proporcionan.

Por último, revisamos el historial de Git y la configuración de Forgejo para comprobar el estado del trabajo realizado por los diferentes miembros del equipo.

## 05/10/2026

Continuamos con la investigación sobre bases de datos, centrada principalmente en PostgreSQL y en su utilización dentro del proyecto.

Revisamos el funcionamiento del contenedor de PostgreSQL, la estructura de almacenamiento de los datos, los registros, el catálogo interno y el directorio pg_wal.

También revisamos las copias de seguridad y las restauraciones realizadas durante el proyecto. Se comprobó que la restauración sobre una base de datos vacía había funcionado correctamente y que se recuperaban las 20 filas de la tabla inventario.

Durante esta revisión se identificó que todavía quedaba pendiente documentar un ejemplo de diagnóstico de un error real de PostgreSQL mediante los registros del contenedor.

Además, comprobamos nuevamente la comunicación entre Apache y PostgreSQL mediante la página estado.php, que permite mostrar información de la base de datos desde la web.

## 06/10/2026

Terminamos la revisión de la documentación final y organizamos los puntos que todavía quedaban pendientes de completar.

Se revisaron las pruebas de DNS, web, base de datos, Forgejo y reinicio del servidor, comprobando qué requisitos estaban cerrados y cuáles necesitaban alguna comprobación adicional.

También se revisaron los apartados de investigación realizados durante el proyecto para integrarlos correctamente con la parte práctica y justificar las tecnologías utilizadas.

Finalización de la investigación de base de datos.

Finalmente, dejamos identificadas las tareas pendientes relacionadas con Forgejo, las claves SSH individuales, la topología de GNS3, la política de contraseñas, las restauraciones sobre volúmenes nuevos y las confirmaciones y pull requests de los miembros del equipo.


## 07/10/2026

Empezamos la fase de cierre de la parte web. Lanzamos `web/probar.sh` y repasamos que `www.huesca.empresa.lan` responde 200 sin credenciales, que la intranet devuelve 401 sin usuario y 200 con las credenciales del `.env`, y que `estado.php` muestra la versión de PostgreSQL y el número de filas.

Leímos los registros de Apache con `docker logs mi-apache`, provocamos un 404 a propósito y localizamos su línea en el log para dejar el ejemplo de diagnóstico documentado.


## 08/10/2026

Empezamos cerrando el pendiente de PostgreSQL que quedó anotado el 5/10: documentar el diagnóstico de un error real mediante los registros del contenedor.

Provocamos dos fallos controlados: una conexión con contraseña incorrecta y una consulta a una tabla que no existe. Los leímos con `docker logs mi-postgres` y vimos que el servidor deja en el log el usuario, la base y el motivo exacto (`password authentication failed` y `relation "..." does not exist`). Dejamos capturada la salida y explicado cómo se llega de la línea del log a la causa.

Comprobamos también que el contenedor registra arranque, conexiones y errores, y lo dejamos fijado en la línea `command:` del servicio de base de datos en el `compose.yaml`.


## 09/10/2026

Dedicamos la jornada a la política de contraseñas (P1), que estaba redactada pero sin comprobar en la práctica.

Revisamos que los parámetros del documento `POLITICA_CONTRASENAS.md` se cumplen de verdad en cada servicio: servidor (longitud y complejidad mínimas), Forgejo, intranet y base de datos. Hicimos intentos reales con una contraseña débil y comprobamos que se rechaza, y guardamos las capturas para la documentación.

Aprovechamos para comprobar que ninguna contraseña real está escrita en ficheros que vayan a Git: las claves viven solo en `.env`, que está en el `.gitignore`, y en el repositorio queda únicamente la plantilla `.env.example`.


## 19/10/2026

Retomamos el trabajo tras las fiestas del Pilar con el acceso remoto.

Claves SSH individuales para todo el equipo. Hasta ahora solo Alvaro tenía su clave desplegada en su propio usuario y el resto seguíamos entrando con el usuario compartido `asir2`.

Creamos un usuario de sistema con permisos de administración para cada persona (Jaime, Andreas, Diego) y guardamos las claves públicas en `sistema/usuarios/*.pub`. Escribimos un script `crear_usuario.sh` para que el alta sea repetible y no se haga a mano en el servidor. Ninguna clave privada sale del portátil de su dueño.

Comprobamos que cada uno entra con su clave, que con contraseña el servidor rechaza la conexión y que `ssh root@...` sigue denegado. Con esto dejamos de depender de `asir2`.


## 20/10/2026

Pasamos a Forgejo: corregimos la incidencia pendiente del 19 de septiembre, el aviso del `ROOT_URL` en `app.ini`.

Decidimos que la dirección definitiva es `git.huesca.empresa.lan` (a través del proxy inverso de Apache) y no la IP del aula con el puerto 3000. Ajustamos `ROOT_URL` y `SSH_DOMAIN` en `forgejo-docker/gitea/conf/app.ini`, reiniciamos el contenedor y comprobamos que el aviso desaparece y que la dirección de clonado que muestra la interfaz es la correcta.

Después hicimos la restauración de Forgejo sobre un volumen completamente nuevo (F5 y prueba 20), que era lo que faltaba. Hicimos un `forgejo dump`, borramos el contenedor y su volumen, levantamos un Forgejo vacío y restauramos el dump. Volvieron la organización `huesca`, las cuentas, el repositorio y las plantillas y etiquetas de incidencias.


## 21/10/2026

Revisión del DNS. Reorganizamos el primario con dos vistas, interna y aula, de modo que el aula solo resuelva los nombres de la sede y la red interna tenga además recursividad para internet.

Pasamos las zonas a plantillas (`dns/*.tpl`) que se generan a partir de `sede.env`, y protegimos la transferencia de zona al secundario con una clave TSIG, de forma que solo quien tenga la clave pueda pedir la lista de nombres. Comprobamos la transferencia firmada, los registros `MX` y `CNAME` y que el secundario recibe las zonas con el mismo serial.

Cerramos también la prueba 6 con un intento real de transferencia de zona desde un equipo que no es el secundario (`nslookup` con `ls -d`), que el primario rechaza, y guardamos la captura.


## 22/10/2026

Trabajo sobre la red simulada. Exportamos la topología de GNS3 como proyecto portable (`gns3/red_huesca.gns3project`) y la subimos al repositorio, para cerrar la necesidad R5 (topología versionada y coincidente con la documentación).

Escribimos el `README.md` de la carpeta `gns3/`: qué hay que tener antes (servidor GNS3 en el propio servidor, puente `br-virtual` creado y la imagen del DNS secundario), cómo se importa el proyecto y el esquema de la topología (Cloud1, Switch1, PC1, PC2 y `dns-secundario-1`). Probamos a importarlo desde cero y los nodos arrancan, con el aviso esperable de interfaces que no existen en la máquina.


## 23/10/2026

Empezamos a convertir la instalación en un único instalador por fases, `instalar.sh`, para que la sede se pueda levantar desde cero sin tocar nada a mano. Escribimos las fases `comprobar`, `red`, `sistema`, `dns`, `gns3`, `forgejo` y `web`, además de `verificar`, que lanza las pruebas de red, contenedores, permisos de la base, DNS, GNS3 y las pruebas HTTP de `web/probar.sh`.

Centralizamos los datos de la sede (interfaz, IP del aula, puerta de enlace, red interna y dominio) en `sede.env`, sin secretos. Cada fase mira primero qué está hecho y solo cambia lo que falta, y nunca borra datos de la base ni de Forgejo; los borrados solo se hacen a mano con `reiniciar bd --si`. La fase `red` solo se aplica sola si la interfaz ya tiene la IP esperada, para no perder el acceso por SSH.

Dejamos además un único `compose.yaml` con los servicios que hay hasta ahora (`mi-apache`, `mi-postgres`, `forgejo` y `mi-bind9`), con versiones de imagen fijadas, volúmenes y salud en la base de datos.


## 26/10/2026

Prueba del despliegue en una máquina limpia. Partimos de un Ubuntu Server recién instalado, clonamos la rama, rellenamos `.env` y lanzamos `sudo ./instalar.sh`.

Aparecieron varios fallos que solucionamos rapidamente. Tras corregir los fallos en el instalador y repetimos hasta que dio `=== TODO CORRECTO ===` dos veces seguidas. También comprobamos que la segunda ejecución no cambia nada.

Escribimos `docs/comprobaciones.md`, con una prueba numerada por cada comprobación, la orden, la salida esperada y dónde mirar si falla, y los scripts `scripts/comprobaciones-contenedores.sh`, `scripts/prueba-fallos-bd.sh` y `scripts/recoger-datos-bd.sh` para repetirlas y recoger evidencias para las tareas que se nos pedian.


## 27/10/2026

Repetimos la prueba de reinicio (prueba 16). Tras `sudo reboot` esperamos a que volviera todo, lanzamos `docker ps` completo y comprobamos que los contenedores estaban `Up` sin tocar nada.

Después repetimos las pruebas 1 a 15 y todas pasaron. Anotamos que el arranque de Docker sigue tardando algo más que el resto de servicios, pero no afecta: todo termina levantándose solo.


## 28/10/2026

Dedicamos el día al funcionamiento por Forgejo: incidencias, ramas y pull requests.

Abrimos incidencias reales con las plantillas `tarea`, `ayuda` y `verificacion` y sus etiquetas por módulo, y las asignamos a cada persona. Hasta ahora todas las etiquetas mostraban 0 incidencias.

Fusionamos por pull request las investigaciones pendientes (nombres, acceso remoto, contenedores, web, base de datos, Forgejo y simulación de red) y cerramos las incidencias desde la propia confirmación que las resuelve. Revisamos que cada confirmación lleva la identidad de su autor y un mensaje que explica el cambio.


## 29/10/2026

Recibimos la segunda parte del encargo: servicio de directorio de usuarios, panel de gestión de proyectos del BIFI (Reto 1) y acceso externo a la base de datos para un responsable. Lo repartimos entre el equipo y repasamos qué piezas dependen de cuáles.

Siguiendo la norma de no implementar nada sin la investigación fusionada, empezamos por la investigación del servicio de directorio: qué es LDAP, cómo funciona, y la comparación entre OpenLDAP, 389 Directory Server y las opciones de Windows.


## 30/10/2026

Terminamos la investigación del directorio y elegimos OpenLDAP en contenedor, con LAM (LDAP Account Manager) como interfaz web de gestión, porque encaja con el resto de la sede, que ya corre en Docker Compose. La fusionamos por pull request antes de tocar el servidor.

En paralelo diseñamos el árbol del directorio: unidades `investigadores`, `visitas`, `grupos`, `servicios` y `politicas`, bajo `dc=huesca,dc=empresa,dc=lan`.


## 02/11/2026

Añadimos al `compose.yaml` los servicios `ldap` (puertos 389 y 636) y `lam` (puerto 8080), con volúmenes para que los datos sobrevivan a la destrucción del contenedor y con las contraseñas del administrador, de la configuración y de LAM en `.env`. Ampliamos `.env.example` con las variables nuevas.

Escribimos `ldif/01_estructura.ldif` con las unidades organizativas, los grupos `investigadores`, `visitas` y `admins` y una cuenta de servicio de solo lectura. Lo cargamos con `ldapadd` y comprobamos la estructura con `ldapsearch`.


## 03/11/2026

Cargamos los usuarios de ejemplo con `ldif/02_usuarios.ldif` y comprobamos con `ldapsearch` que cada uno pertenece a su grupo. Probamos que la cuenta de servicio de solo lectura puede consultar pero no modificar.

Reiniciamos el contenedor `ldap` y comprobamos que los datos se conservan. Entramos en LAM con la contraseña del `.env` y gestionamos un usuario desde la interfaz web.


## 04/11/2026

Hicimos que el servidor autentique contra OpenLDAP mediante SSSD. Instalamos `sssd`, `sssd-ldap`, `libpam-sss` y `libnss-sss`, y generamos `/etc/sssd/sssd.conf` con acceso restringido al grupo `investigadores` y con la cuenta de servicio de solo lectura para las consultas.

Comprobamos con `getent passwd` que el sistema ve a los usuarios del directorio, y que un usuario de LDAP puede iniciar sesión mientras uno del grupo `visitas` queda rechazado. Dejamos el procedimiento recogido en `scripts/sssd.sh` para que sea repetible.

Lo añadimos a `instalar.sh` como fase `sssd`.


## 05/11/2026

Abrimos la parte de Active Directory. Hablamos de cómo integrar las cuentas con el controlador de dominio de Windows Server (dc1, `ad.huesca.empresa.lan`) y decidimos que OpenLDAP sea el directorio principal y que sus cuentas se sincronicen hacia AD, no al revés.

Redactamos la investigación (Windows Server, AD y sincronización frente a alternativas) y la fusionamos antes de implementar nada. Anotamos que la estructura de AD que necesitan nuestros scripts no coincide con el diseño de ejemplo que figuraba en el enunciado, así que la documentaremos nosotros.


## 06/11/2026

Preparación de Active Directory en dc1. Escribimos `sincronizacion/windows-preparar-ad.ps1`, que crea la OU `Huesca` con `Investigadores`, `Visitas`, `Grupos` y `Servicios`, los grupos `GG-Investigadores` y `GG-Visitas` y la cuenta de servicio `svc-sync`.

A `svc-sync` le delegamos solo lo imprescindible: crear y eliminar usuarios, control sobre las cuentas de las dos OU y escribir la pertenencia a los grupos. Sin permisos de administrador. El script es repetible y pide la contraseña al ejecutarlo.


## 09/11/2026

Dedicamos el día al cifrado de la conexión con AD. La sincronización debe ir por LDAPS, y dc1 necesitaba un certificado a nombre de `dc1.ad.huesca.empresa.lan`.

Instalamos una entidad de certificación de empresa (`Huesca-CA`) en el controlador, comprobamos que dc1 solicita su certificado y exportamos el `.cer` de la CA a `sincronizacion/huesca-ad-ca.cer`. Desde Linux verificamos la conexión con `openssl s_client` contra el puerto 636 hasta obtener `Verify return code: 0`.

Por el camino aparecieron los errores típicos de verificación (certificado de otra CA y nombre que no coincide), que anotamos con su causa para la documentación.


## 10/11/2026

Escribimos el script de sincronización `sincronizacion/sincronizar-ad.sh`, que lee las cuentas y grupos de OpenLDAP y crea o actualiza sus equivalentes en AD usando `svc-sync`. Tiene un modo `DRY_RUN=1` que muestra lo que haría sin tocar nada.

Lo probamos primero en seco y después en real con un usuario de prueba, que apareció en la OU `Investigadores` y en el grupo `GG-Investigadores`. Comprobamos que repetir la sincronización no duplica nada.


## 12/11/2026

Automatizamos la sincronización con un servicio y un temporizador de systemd (`sincronizar-ad.service` y `sincronizar-ad.timer`) y comprobamos con `systemctl list-timers` y `journalctl` que se ejecuta sola y deja registro.

Para las altas añadimos `alta-investigador.sh`, que crea el usuario en OpenLDAP y lo deja listo para sincronizar. Descubrimos que AD crea las cuentas deshabilitadas hasta que tienen contraseña, así que lo dejamos como comportamiento esperado y lo explicamos en la documentación.


## 13/11/2026

Resolvimos el tema de las contraseñas en AD. Con `cambiar-clave.sh <usuario>` se fija o cambia la clave y se habilita la cuenta; también se puede definir `AD_CLAVE_INICIAL` (mínimo 12 caracteres) en `.env` para las altas nuevas.

Probamos el ciclo completo: alta en OpenLDAP, sincronización, cuenta deshabilitada en AD, fijar clave, cuenta habilitada e inicio de sesión desde un equipo Windows. También probamos que una contraseña que incumple la política se rechaza.

Escribimos `docs/ad-windows.md`, con lo que debe existir en AD, los pasos en dc1 y en Linux, las comprobaciones y una tabla de errores típicos con su causa. Una persona del equipo lo siguió sin ayuda sobre un dc1 limpio para validarlo, y corregimos dos pasos que estaban incompletos.

Añadimos la fase `ad` a `instalar.sh`: confía en la CA de AD, instala los scripts y el temporizador, comprueba LDAPS y `svc-sync` y hace la primera sincronización. Como la parte de Windows se hace a mano, en la ejecución completa solo avisa si dc1 no está listo.


## 16/11/2026

Acceso externo a PostgreSQL para el responsable que lo necesita. Creamos el rol `resp_demo`, solo de lectura, en `db/04_roles_externos.sql`, escrito para poder repetirse sin error.

Publicamos el puerto 5432, pero con `pg_hba.conf` restringido: desde fuera de las redes de Docker solo puede entrar `resp_demo`, y el usuario de la web sigue sin poder borrar datos. Probamos con `psql` desde otro equipo que `resp_demo` lee, que no puede escribir y que cualquier otro usuario es rechazado. Actualizamos la documentación porque esto cambia lo que dijimos el 23/09 sobre el puerto cerrado.


## 17/11/2026

Empezamos el Panel del BIFI (Reto 1), una aplicación en PHP 8.3 para gestionar proyectos de investigación. Montamos su `Dockerfile` (PHP con Apache sirviendo solo el directorio `public/`) y la estructura de carpetas, separando la lógica interna (`comun/`) de lo que se sirve por la web.

Implementamos el inicio y cierre de sesión con `password_verify` y regeneración del identificador de sesión, y cargamos los datos de ejemplo (usuarios, proyectos y consumos).

Después pasamos a perfiles y permisos. Investigadores solo ven sus proyectos y en modo lectura, los responsables gestionan los miembros de su proyecto y el personal del CESAR da de alta proyectos nuevos.

Hicimos que un proyecto al que el usuario no tiene acceso devuelva 404 y no 403, para no revelar que existe. Añadimos la validación de proyectos y miembros (sin duplicados ni usuarios que no sean investigadores) y que los datos se guarden en el volumen `datos-panel`.


## 18/11/2026

Pruebas de aceptación del panel. Definimos una matriz de pruebas (acceso anónimo, credenciales erróneas, vistas por perfil, acceso a un proyecto ajeno, alta solo por CESAR, añadir y quitar miembros, cálculo de consumos, cierre de sesión y regeneración de sesión) y las ejecutamos una por una, recogiendo el resultado real en `panel/pruebas.md`.

Añadimos el alias `panel` en la zona DNS y el proxy inverso en Apache para `panel.huesca.empresa.lan`. Comprobamos que funciona por nombre y por el puerto 8081.

Añadimos el servicio `panel` al `compose.yaml`, con lo que quedan los siete servicios (`mi-apache`, `mi-postgres`, `forgejo`, `mi-bind9`, `ldap`, `lam` y `panel`), y repetimos `sudo ./instalar.sh verificar` para comprobar que todo sigue en marcha.


## 19/11/2026

Fusionamos las ramas de trabajo de cada área en una sola (`main`) y resolvimos los conflictos, sobre todo en `compose.yaml`, `README.md` y la documentación, donde habían quedado marcas de conflicto sin limpiar en la tabla de pruebas de aceptación.

Actualizamos la documentación final con los apartados de LDAP, Active Directory, panel del BIFI y acceso externo a PostgreSQL, y revisamos el diagrama de red y las direcciones para que coincidan con `sede.env` (red interna `10.2.0.0/24`, servidor en `10.2.0.1` y DNS secundario en `10.2.0.2`). Repasamos el cuaderno de sesión contra los registros y las capturas, y pusimos al día los estados de los checklists.

## 23/11/2026

Repetimos las pruebas de aceptación del panel del BIFI con probar-panel.sh: login y cambio de sesión, perfiles y menú, acceso a proyectos ajenos (403 y 404), gestión de miembros, alta de proyectos solo para el CESAR, salida escapada (XSS) y cierre de sesión. Todo pasó. Anotamos que habría que repetirlas cuando los datos pasaran de JSON a PostgreSQL.


## 24/11/2026

Explicación y presentación de como vamos y como funciona el proyecto de bifi a Alejandro, mostrando el panel con sus perfiles y el resto de servicios de la sede.

Mejora de interfaz de la intranet y la web publica debido a peticiones del profesorado tras ver como llevábamos el proyecto. En la intranet, estado de los siete servicios y métricas del servidor y de cada contenedor con actualización automática. En la web pública, buscador, indicadores y mejoras de accesibilidad. Repetimos web/probar.sh para confirmar que seguía todo respondiendo bien.


## 25/11/2026

Realización de exámenes de ASO y sostenibilidad. Arreglos en la base de datos de bifi para la presentación de mañana y puesta a punto del proyecto para que todo salga bien, repaso de como esta montado todo: datos de ejemplo del panel, permisos de la base, docker ps y instalar.sh verificar.


## 26/11/2026

Pasamos los datos del panel del BIFI de los ficheros JSON a PostgreSQL. En la base `bifi` hay ahora cuatro tablas (`usuarios`, `proyectos`, `miembros` y `usos`) que crea `db/04_bifi.sh` con el administrador como dueño. El usuario `panel` solo tiene en cada tabla lo que usa alguna página (por ejemplo, `DELETE` solo en `miembros`) y no puede crear ni borrar tablas. `resp_demo` no ve ninguna.

`instalar.sh` (fase `bd`) carga los JSON de `panel/datos-ejemplo/` la primera vez, en una transacción que comprueba que ha entrado todo antes de confirmar. Después el panel ya no los usa y ni siquiera están dentro de su imagen. Quitamos el volumen `datos-panel`.

En el código del panel, todas las consultas son preparadas (`consultar()` en `comun/bd.php`). Añadimos el código CSRF al login y convertimos «Salir» en un formulario POST. Los errores de la base van al registro y no al navegador (`php.ini` de producción y un manejador en `arranque.php`). Juntamos `panel/pruebas.md` dentro de `panel/readme.md` y pusimos en el `README.md` de la raíz un índice de toda la documentación. Falta repetir las pruebas en la VM.

