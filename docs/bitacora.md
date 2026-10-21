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
