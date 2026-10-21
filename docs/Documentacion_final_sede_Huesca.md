# Documentación final de la sede · Huesca (`huesca.empresa.lan`)

## 0\. Datos de la sede

| Dato | Valor |
| --- | --- |
| Sede | Huesca |
| Red interna | `10.5.0.0/24` (decisión del equipo, ver nota de arriba) |
| Dirección fija del servidor en el aula | `192.168.6.105` (interfaz `enp5s0`) |
| Puerta de enlace de la red interna | `br-virtual` — `10.5.0.1/24` |
| Resolutor del centro (forwarders) | `8.8.8.8` y `1.1.1.1` |
| Usuarios con sudo en el servidor | `asir2`, `Jaime`, `Andreas`, `Alvaro`, `Diego` |
| Administrador de Forgejo | `admin_huesca` |
| Cuenta de Forgejo para el profesorado | `Profesor`, dada de alta como miembro de la organización `huesca` |
| Responsables por módulo | 🟡 **parcial** — `docs/CLASIFICACION_DATOS.md` recoge el "Equipo de administración" (Alvaro, Jaime, Andreas, Diego), y el `README` ya muestra la tabla "Datos de la sede" (captura de abajo), pero sigue faltando la tabla de responsable + suplente por área |

![README del repositorio: sección "Datos de la sede" (sede, dominio, IP fija, resolutor, usuario del profesorado `Profesor`) y equipo de administración](imagenes/77_readme_datos_de_la_sede.png)

---

## 1\. La sede

El servidor de Huesca es una máquina Ubuntu Server con dos patas de red:  
`enp5s0` hacia la red del aula (`192.168.6.0/24`, IP `192.168.6.105` por DHCP) y `br-virtual` hacia  
la red interna de la sede (`10.5.0.0/24`, simulada con GNS3). Sobre él corren en contenedores  
Docker: el servidor de nombres (BIND9, migrado a contenedor a mitad de reto), un servidor web  
Apache con dos sitios (pública e intranet) más PHP, una base de datos PostgreSQL, un servidor Git  
Forgejo, y GNS3 Server para simular la red interna. Todo esto da autonomía a la sede (no depende de  
otras sedes para nombres, web o repositorio) y debería sobrevivir a un reinicio del servidor.

![docker ps con los siete contenedores del stack: GNS3, dns-secundario-1, forgejo, mi-apache, mi-postgres, mi-bind9 y postgres-db](imagenes/48_docker_ps_stack_completo_bind9_apache_postgres_forgejo_gns3.png)

**🟡 Avance:** el `README` del repositorio ya incluye la tabla "Datos de la sede" y nombra al equipo de  
administración (Álvaro, Jaime, Andreas, Diego), igual que `docs/CLASIFICACION_DATOS.md`.

**🔴 Lo que falta:** la tabla de responsables y suplente por área y persona en el `README` del  
repositorio (ni el `README` ni `docs/` reparten áreas ni suplentes).

---

## 2\. Red

### 2.1 Diagrama

```
graph LR
  subgraph AULA["Red del aula 192.168.6.0/24"]
    PROF["Dirección de Sistemas"]
    OTRAS["Otras sedes"]
    LAP["Portátiles del equipo"]
  end
  subgraph SRV["Servidor Huesca — dos patas de red"]
    direction TB
    ENP["enp5s0<br/>192.168.6.105 (DHCP aula)"]
    BR["br-virtual<br/>10.5.0.1/24 (puerta de enlace interna)"]
    SVC["Contenedores Docker:<br/>bind9 · apache (mi-apache) · postgres (mi-postgres) · forgejo · gns3server"]
    ENP --- SVC
    SVC --- BR
  end
  subgraph INT["Red interna 10.5.0.0/24 · simulada en GNS3"]
    SW["Switch1"]
    NS2["dns-secundario-1 (10.5.0.2)"]
    PC1["PC1 = pc-01 (10.5.0.20)"]
    PC2["PC2 = pc-02 (10.5.0.21)"]
    SW --- NS2
    SW --- PC1
    SW --- PC2
  end
  AULA --- ENP
  BR --- SW
```

### 2.2 Direccionamiento

`enp5s0` recibe IP por DHCP del aula; `br-virtual` es la puerta de enlace fija  
de la red interna. Los nombres de la zona DNS apuntan casi todos a la misma IP del servidor  
(`10.5.0.1`) mediante registros `A` y `CNAME`.

![Interfaces enp5s0 y br-virtual, docker ps final](imagenes/32_dig_google_2_ip_a_interfaces.png)

| Elemento | Dirección | Evidencia |
| --- | --- | --- |
| `enp5s0` (salida al aula) | `192.168.6.105/24` (DHCP) | `ip a show enp5s0` |
| `br-virtual` (puerta de enlace interna) | `10.5.0.1/24` | `ip a show br-virtual` |
| `servidor` / `ns1` / `correo` (DNS) | `10.5.0.1` | zona `huesca.empresa.lan` |
| `ns2` | `10.5.0.2` | zona `huesca.empresa.lan` |
| PC1 | `10.5.0.20/24`, gateway `10.5.0.1` | consola VPCS |
| PC2 | `10.5.0.21/24`, gateway y DNS `10.5.0.1` | `show ip` en VPCS |

### 2.3 Cómo sale la red interna a internet (NAT)

`sysctl net.ipv4.ip_forward=1` activa el reenvío de paquetes en el kernel. Una  
regla NAT tipo `MASQUERADE` en `/etc/ufw/before.rules` (`-A POSTROUTING -s 10.5.0.0/24 -o enp5s0 -j MASQUERADE`) traduce las IP internas a la del servidor cuando salen por `enp5s0`. Además, reglas  
`ufw route allow` entre `br-virtual` y `enp5s0` permiten el reenvío a nivel de cortafuegos, y reglas  
`DNAT` en `PREROUTING` redirigen `192.168.6.105:80/3000/3080` hacia el servidor interno para poder  
publicar la web, Forgejo y GNS3 desde el aula.

![Reglas ufw, before.rules con MASQUERADE, ufw route allow](imagenes/04_ufw_reglas_nat_beforerules.png)

![ufw status verbose e iptables -t nat POSTROUTING](imagenes/05_ufw_status_verbose_iptables_nat.png)

![Ajuste final de DEFAULT_FORWARD_POLICY e ip_forward en /etc/ufw](imagenes/42_ufw_forward_policy_fix.png)

![Reglas DNAT finales, iptables -t nat -L PREROUTING, apachectl -S con 3 vhosts](imagenes/43_dnat_final_iptables_apachectl.png)

Por qué el NAT y las DNAT se resolvieron en ufw (/etc/ufw/before.rules) en vez de en iptables/nftables puro:Se centralizó la configuración de NAT y DNAT en /etc/ufw/before.rules para garantizar su carga automática e integración persistente con la gestión del cortafuegos del sistema (ufw), evitando así conflictos de filtrado o que las reglas manuales de iptables/nftables queden sobrescritas al recargar el servicio. Por qué hacen falta las reglas DNAT:Las reglas DNAT (Destination NAT) en la cadena PREROUTING son necesarias para hacer accesibles desde la red del aula (192.168.6.0/24) los servicios alojados dentro de la red interna o en los contenedores Docker de la sede. Dado que los contenedores escuchan en la red interna o en puertos locales específicos aislados del exterior, la DNAT redirige el tráfico entrante destinado a la IP del servidor en el aula (192.168.6.105) en un puerto determinado hacia la dirección IP interna y puerto de escucha real del contenedor objetivo (como el servidor Web, Forgejo o GNS3 Server).

### 2.4 Topología GNS3

**📝 Explicación.** La red interna se simula en GNS3: un switch conecta dos clientes VPCS (PC1,  
PC2) y un segundo servidor de nombres (`dns-secundario-1`), y una nube conecta ese switch con  
`br-virtual` del servidor real. Con esto se cumple el mínimo de tener un segundo DNS y dos clientes  
en la red interna.

![Topología GNS3: Switch1, PC1, PC2, dns-secundario-1 y nube hacia br-virtual](imagenes/08_topologia_gns3_y_pc1.png)

![Pruebas ping desde PC2 a 10.5.0.1, 192.168.6.105 y 8.8.8.8, e instalación de GNS3](imagenes/06_ping_pc2_y_gns3_instalacion.png)

![Unidad systemd de gns3server, permisos y GNS3 Web UI con el proyecto 10.5.0.0](imagenes/07_gns3_systemd_y_webui.png)

![Pings para comprobar que funciona la resolucion de nombres](imagenes/pings_gns3.png)

---

## 3\. Instalación desde cero

> Reconstruida en el mismo orden en que aparecen las capturas del PDF.

### 3.0 Instalación de Ubuntu Server

Paso 0 antes de cualquier configuración: instalar el sistema operativo base  
(particionado, usuario inicial, red mínima) sobre el que luego se monta todo lo demás.

**🔴 Lo que falta:** no hay ninguna captura de este paso en el PDF. Hace falta al menos una captura  
del particionado/instalación y del primer arranque con el usuario `asir2` creado.

### 3.1 Red fija del servidor (netplan)

Se instala `bridge-utils`, se edita `/etc/netplan/00-installer-config.yaml`  
para fijar la interfaz física `enp5s0` (por MAC, con `match`/`set-name`) y se crea el puente  
`br-virtual` con IP estática `10.5.0.1/24`, que hace de puerta de enlace de la red interna. Se  
aplica con `netplan apply` y se comprueba con `ip a show br-virtual`.

![netplan 00-installer-config.yaml, netplan apply, ip a show br-virtual, ip_forward, apt install bind9](imagenes/01_ip_fija_y_dns_inicio.png)

### 3.2 Reenvío de paquetes

`net.ipv4.ip_forward=1` en `/etc/sysctl.d/99-forward.conf` (aplicado con  
`sysctl -p`) es lo que permite que el servidor actúe de router entre `enp5s0` y `br-virtual`; sin  
esto, el NAT del apartado 2.3 no tendría ningún paquete que reenviar.

![sysctl net.ipv4.ip_forward y ufw status verbose completo](imagenes/33_ip_forward_ufw_verbose_repetida.png)

### 3.3 Cortafuegos base (ufw)

Se instala `ufw` y se abren, uno a uno, los puertos necesarios: SSH, DNS  
(53/udp y 53/tcp) — más tarde también HTTP, HTTPS, Forgejo (3000, 2222) y GNS3 (3080) — y se  
activa con política por defecto `deny (incoming)` / `allow (outgoing)` / `deny (routed)`, salvo lo  
permitido explícitamente.

![Instalación y activación de ufw: allow ssh, allow 22/tcp, enable](imagenes/15_ufw_instalacion_activacion.png)

![ufw status verbose final con política deny (routed) por defecto](imagenes/16_ufw_verbose_final_y_forgejo_mkdir.png)

### 3.4 Acceso remoto (SSH)

Se instala `openssh-server`, se arranca y habilita el servicio, se abre el  
puerto en `ufw`, y se copian las claves públicas del equipo a `~/.ssh/authorized_keys` para poder  
entrar sin contraseña desde cada portátil.

![apt install openssh-server, systemctl start/enable, ufw allow ssh, ssh desde Windows, copia de clave pública](imagenes/09_pc2_show_ip_y_ssh_instalacion.png)

![sshd_config endurecido (PubkeyAuthentication yes, PasswordAuthentication no)](imagenes/10_sshd_config_y_alta_usuarios_1.png)

![sshd_config con PermitRootLogin no sin comentar, y ssh root@192.168.6.105 rechazado con Permission denied (publickey)](imagenes/46_sshd_permitrootlogin_no_y_ssh_root_denegado.png)

![Clave pública de Alvaro desplegada en su propio usuario: mkdir /home/Alvaro/.ssh, authorized_keys, chown y chmod 700/600](imagenes/45_ssh_clave_individual_alvaro_y_forgejo_volumen_persistente.png)

Para los demas miembros del equipo el ssh se realiza de la misma manera que Alvaro pero cambiando el nombre por el respectivo de cada uno y poniendo la clave ssh de cada uno en su directorio correspondiente.

**🔴 Lo que falta:**

*   Probar la conexión también desde Linux, no solo desde Windows.
*   Una prueba de copia de ficheros (`scp`/`sftp`) o túnel SSH.

### 3.5 Usuarios del equipo

`adduser` + `usermod -aG sudo` para cada persona del equipo (Jaime, Andreas,  
Alvaro, Diego), verificado con `/etc/passwd` y `getent group sudo`; después se añaden también al  
grupo `docker` para poder usar contenedores sin `sudo` en cada orden.

![adduser Jaime, adduser Andreas](imagenes/10_sshd_config_y_alta_usuarios_1.png)

![adduser Alvaro, adduser Diego, /etc/passwd, getent group sudo, usermod -aG docker](imagenes/11_alta_usuarios_2_y_docker_install.png)

### 3.6 Docker y Docker Compose

`apt install docker.io docker-compose-v2` y `systemctl enable --now docker`  
dejan el motor de contenedores listo y arrancando solo tras un reinicio.

ver la parte final de la captura anterior (apartado 3.5).

### 3.7 Servicio de nombres (BIND9)

+Instalación de `bind9 bind9utils bind9-doc`, configuración de  
`named.conf.options` (recursión, `allow-query`, `forwarders`, `listen-on`) y `named.conf.local`  
(zona maestra y zona inversa), creación de las zonas directa e inversa, verificación con  
`named-checkconf`/`named-checkzone` antes de recargar el servicio.

![apt install bind9 (al final de la captura de red fija)](imagenes/01_ip_fija_y_dns_inicio.png)

![systemctl status bind9 (arranque inicial), named.conf.options, named-checkconf, named.conf.local](imagenes/02_bind9_named_conf_options_local.png)

![Zona directa db.huesca.empresa.lan, named-checkzone OK, zona inversa db.10.5, restart bind9, ufw enable](imagenes/03_bind9_zona_directa_inversa_restart.png)

_(La explicación detallada de la zona, los huecos de servidor secundario, etc. están en el_  
_apartado 4.1, para no repetirlos aquí.)_

### 3.8 GNS3 Server

Repositorio PPA oficial, paquetes `gns3-server`, `ubridge` y `dynamips`;  
usuario de sistema `gns3` en los grupos `kvm` y `docker`; capacidades de red en `ubridge`  
(`setcap cap_net_admin,cap_net_raw=ep`); unidad `systemd` propia escuchando en `0.0.0.0:3080`.

ver apartado 2.4 (mismas capturas).

### 3.9 Web — Apache (dos iteraciones)

Primero una prueba con `httpd:latest` en Docker y HTML estático; después se le  
añade HTTPS con certificado autofirmado; y al final se sustituye por una imagen propia  
(`php:8.2-apache`) dentro del proyecto Compose final (`proyecto_huesca`), con dos `VirtualHost`  
(web pública e intranet).

![Estructura apache-docker, index.html de prueba, docker-compose.yml con httpd, "Apache funcionando" en el navegador](imagenes/12_apache_docker_prueba_inicial.png)

![apt install apache2 en el host (prueba de control), mkdir certs, openssl req -x509, ls certs](imagenes/13_apache_certificados_https.png)

![my-httpd-ssl.conf: VirtualHost 443, SSLEngine on, certificado y clave](imagenes/14_apache_httpd_ssl_conf.png)

![docker-compose.yml con puertos 8080/443 y volúmenes de certificados y config SSL](imagenes/14_apache_httpd_ssl_conf.png)

![Proyecto final: mkdir proyecto_huesca, Dockerfile (php:8.2-apache + pgsql), .env, docker-compose.yml con red red-huesca](imagenes/40_proyecto_huesca_dockerfile_compose.png)

**🔴 Lo que falta:** confirmar que el `apache2` instalado directamente en el host (captura del  
apartado 3.9, primera imagen) fue solo una prueba de control y que el servicio final vive  
**solo** en Docker (si el `apache2` del host sigue activo, compite por el puerto 80 con el  
contenedor).

### 3.10 Base de datos — PostgreSQL

Contenedor `mi-postgres` con la tabla `inventario` (20 filas de equipos de la  
sede), copia de seguridad con `pg_dump` y prueba de restauración con `psql`.

![CREATE TABLE inventario, INSERT 20 filas, SELECT COUNT(*), pg_dump backup](imagenes/35_postgres_tabla_inventario_htpasswd.png)

![Restauración: TRUNCATE + psql < backup, docker logs de arranque de postgres](imagenes/36_postgres_restauracion_logs_init.png)

### 3.11 Forgejo

Contenedor con volumen persistente, asistente inicial con SQLite3, dominio  
`git.huesca.empresa.lan`, organización `huesca`, repositorio `sede-huesca`, alta de usuarios y  
clave SSH, y una copia (`forgejo dump`) restaurada por prueba mediante `git clone`.

![mkdir forgejo-docker, docker-compose.yml de forgejo](imagenes/16_ufw_verbose_final_y_forgejo_mkdir.png)

![docker-compose.yml forgejo completo, ufw allow 3000/2222, ufw reload](imagenes/17_forgejo_compose_y_ufw_puertos.png)

![Asistente inicial: base de datos SQLite3, título "Sede Huesca", dominio git.huesca.empresa.lan, puerto SSH 2222](imagenes/18_forgejo_wizard_bd_general.png)

![Configuración opcional y cuenta de administrador (admin_huesca)](imagenes/19_forgejo_wizard_opcional_admin.png)

![Nueva organización "huesca" y nuevo repositorio](imagenes/20_forgejo_organizacion_y_repo.png)

![Repositorio sede-huesca creado con README inicial](imagenes/21_forgejo_repo_sede_huesca_creado.png)

![Etiquetas: creación de la etiqueta "Crítico"](imagenes/22_forgejo_etiquetas.png)

![Plantilla de incidencia .forgejo/ISSUE_TEMPLATE/plantilla.md](imagenes/23_forgejo_plantilla_incidencia.png)

![Commit del cambio, panel de administración de usuarios, alta de Alvaro](imagenes/24_forgejo_commit_y_alta_usuario.png)

![5 usuarios dados de alta, miembros del equipo, clave SSH de Alvaro añadida](imagenes/25_forgejo_usuarios_y_claves_ssh.png)

![git clone por SSH desde Windows (fingerprint aceptado), forgejo dump](imagenes/26_forgejo_git_clone_y_dump.png)

![docker cp del backup.zip al host, rm dentro del contenedor, unzip -o (inicio)](imagenes/27_forgejo_backup_copiado_unzip_1.png)

![unzip -o (resto del contenido), docker compose restart, panel de Forgejo funcionando](imagenes/28_forgejo_backup_unzip_2_y_migracion_bind_inicio.png)

![Miembros de la organización "huesca": Alvaro, Andreas, Diego, Jaime, Profesor y admin_huesca, todos como Propietario](imagenes/44_forgejo_miembros_organizacion_profesor.png)

![Plantilla de incidencia adicional .forgejo/ISSUE_TEMPLATE/bug.md añadida por admin_huesca](imagenes/49_forgejo_plantilla_incidencia_bug_md.png)

![forgejo dump ejecutado dentro del contenedor: inicialización de todos los almacenes (adjuntos, avatares, LFS, paquetes, actions), volcado de la base de datos y empaquetado en forgejo-dump-1790157601.zip](imagenes/50_forgejo_dump_ejecucion_detallada.png)

![Destrucción y recreación del contenedor forgejo (docker rm -f + docker compose up -d): el repositorio sede-huesca.git sigue presente en el volumen tras el reinicio](imagenes/45_ssh_clave_individual_alvaro_y_forgejo_volumen_persistente.png)

![forgejo dump restore --from ... sobre una instancia, y unzip -o del backup con toda la estructura del repositorio (refs, hooks, logs) recreada en /tmp/restored](imagenes/51_forgejo_dump_restore_unzip_en_instancia.png)

![ls -la de /tmp/restored (app.ini, data, repos, forgejo-db.sql) y cabecera del volcado SQL con las tablas forgejo_auth_token y oauth2_application restauradas](imagenes/52_forgejo_restore_ls_y_sqlite_tablas.png)

**🔴 Lo que falta:**

*   La restauración de arriba se ha probado copiando el `dump` dentro del propio contenedor  
    (`/tmp/restored`), pero falta levantar un contenedor de Forgejo **completamente nuevo** (volumen  
    vacío) y restaurar el `dump` sobre él para dar F5 por cerrado del todo.
*   Incidencias reales abiertas y cerradas desde confirmaciones (no hay ninguna captura del tablero  
    en uso).
*   Aclarar y corregir (o justificar por qué se deja así) el aviso `Your ROOT_URL in app.ini …`.

---

## 4\. Cada servicio

### 4.1 DNS — BIND9

`named.conf.options` define `recursion yes`, restringe `allow-query` a las  
redes internas y del aula, usa `8.8.8.8`/`1.1.1.1` como _forwarders_ y valida DNSSEC. La zona  
`huesca.empresa.lan` tiene SOA, dos `NS`, un `MX` hacia `correo`, registros `A` para `servidor`,  
`ns1`, `ns2`, `correo`, y `CNAME` para `srv`, `www`, `intranet`, `git`, `db` — cubre el mínimo de  
nombres pedido. La zona inversa (`5.10.in-addr.arpa`) tiene el `PTR` de `servidor`. A mitad de  
reto se migró BIND9 de servicio nativo a contenedor Docker (imagen  
`internetsystemsconsortium/bind9`), reutilizando la configuración copiada de `/etc/bind`.

![docker ps --format con el contenedor mi-bind9 confirmado junto al resto del stack (forgejo, mi-apache, mi-postgres, postgres-db)](imagenes/53_docker_ps_format_bind9_confirmado.png)

![mkdir bind-docker, cp /etc/bind, curl root.hints, logs de arranque de named, dig www.huesca.empresa.lan](imagenes/29_bind_docker_config_y_arranque.png)

![docker ps con el contenedor bind, dig www/git/correo.huesca.empresa.lan](imagenes/30_bind_docker_dig_pruebas.png)

![dig @10.5.0.1 www.google.com — resolución recursiva funcionando](imagenes/31_dig_google_recursiva_1.png)

![dig final a www.huesca.empresa.lan y /etc/resolv.conf del propio servidor](imagenes/34_dig_final_resolvconf_bd_inicio.png)

**Segundo servidor de nombres (**`**dns-secundario-1**`**), configurado de verdad.** Corre en el nodo Docker  
de la topología GNS3, con IP fija `10.5.0.2/24` y ruta por defecto hacia `10.5.0.1`, y sus dos zonas  
declaradas como `type slave` apuntando al primario (`masters { 10.5.0.1; }`):

![dns-secundario/dockerfile: imagen debian:bookworm-slim con bind9, bind9utils, dnsutils e iproute2](imagenes/68_dns_secundario_dockerfile.png)

![dns-secundario/entrypoint.sh: IP fija 10.5.0.2/24, ruta por defecto y arranque de named como usuario bind](imagenes/69_dns_secundario_entrypoint_sh.png)

![named.conf.options del secundario: directory /var/cache/bind, recursion no, allow-query any](imagenes/70_dns_secundario_named_conf_options.png)

![named.conf.local del secundario: zonas huesca.empresa.lan y 5.10.in-addr.arpa como type slave con masters { 10.5.0.1; }](imagenes/71_dns_secundario_named_conf_local_zona_slave.png)

**Zona restringida en el primario.** El primario separa el tráfico en una `acl internos` (red  
`10.5.0.0/24` + `127.0.0.1`) y una `acl aula_ip`, y en la vista `"interna"` la zona maestra solo  
permite transferencia y notificación al secundario (`allow-transfer { 10.5.0.2; }`,  
`also-notify { 10.5.0.2; }`), no a cualquiera:

![named.conf.local del primario: acl internos/aula_ip, view "interna" con recursion yes solo para internos, y zona master con allow-transfer/also-notify restringidos a 10.5.0.2](imagenes/72_dns_primario_named_conf_local_master_acl_allow_transfer.png)

**Pruebas de resolución.** Desde un cliente de la red interna (PC1, en GNS3) se resuelven tanto el  
nombre propio de la sede como uno de internet a través del mismo resolutor:

![PC1: ping www.huesca.empresa.lan resuelto a 10.5.0.1 y ping www.google.com resuelto vía forwarder](imagenes/73_pc1_ping_interno_y_externo_resuelto.png)

Y desde un equipo del **aula** (fuera de la `acl internos`), preguntando explícitamente al servidor  
de Huesca: los nombres propios de la sede (`www`, `intranet`) se siguen resolviendo, pero una  
consulta recursiva hacia internet (`www.google.com`) es rechazada por el servidor  
(`Query refused`) — la prueba que faltaba de que el aula no puede usar este DNS para navegar por  
internet:

![nslookup desde un PC del aula: www.huesca.empresa.lan e intranet.huesca.empresa.lan resuelven, www.google.com devuelve "Query refused"](imagenes/74_nslookup_aula_internos_ok_internet_query_refused.png)

Y, ya con el nombre resuelto, el servicio detrás también responde desde el aula (prueba R4 del  
apartado 8):

![nslookup git.huesca.empresa.lan 192.168.6.105 resuelto, y curl -I http://git.huesca.empresa.lan:3000 → 200 OK, ambos desde un PC del aula](imagenes/67_nslookup_curl_git_desde_aula_200ok.png)

Por último, un intento de comprobar la réplica rápida (alta de un registro de prueba `prueba-n5 IN A 10.5.0.99` en el primario, con marca de tiempo del sistema justo al lado):

![Edición de zona con el registro de prueba "prueba-n5 IN A 10.5.0.99" y hora del sistema (10:43:21) para cronometrar la réplica](imagenes/75_zona_registro_nuevo_prueba_n5_y_uptime_apache.png)

**Réplica al secundario, medida.** Se validó la zona en el primario (`named-checkzone`, serial 12), se  
reinició `mi-bind9` (12:06:17) y se consultó directamente al **secundario** (`dig @10.5.0.2`) por un  
nombre de prueba nuevo (`prueba-n4c`): ya respondía `10.5.0.96` 11 segundos después y siguió  
respondiendo en las consultas posteriores. Además, la consulta `SOA` a ambos servidores devuelve el mismo  
serial (12):

![named-checkzone serial 12, restart de mi-bind9 con hora, tres dig @10.5.0.2 prueba-n4c.huesca.empresa.lan → 10.5.0.96 y SOA con serial 12 en primario y secundario](imagenes/78_dns_replica_secundario_prueba_n4c_soa_serial12.png)

**Primario parado.** Para la prueba de caída se paró el contenedor del primario:

![docker stop mi-bind9 ejecutado por Andreas](imagenes/79_docker_stop_mi_bind9_primario_parado.png)

**El propio servidor usa su DNS.** Una consulta hecha en el servidor _sin_ indicar `@servidor` la atiende  
`127.0.0.1#53` (el `named` local, primera línea de `/etc/resolv.conf`), y la respuesta llega en 0 ms  
con el TTL ya descontado (37 s), es decir, desde caché:

![dig www.wikipedia.org sin @: SERVER 127.0.0.1#53, Query time 0 msec, TTL 37 en dyna.wikimedia.org](imagenes/86_dig_wikipedia_resolutor_propio_servidor.png)

**Estado de lo que faltaba en este apartado:**

*   🟢 Réplica en \<1 min (N4, prueba 8): cerrada con la captura del `dig @10.5.0.2` (11 s tras recargar el  
    primario, mismo serial en ambos).
*   🟢 El propio servidor usa su DNS (N10): `dig` sin `@` atendido por `127.0.0.1#53`.
*   🟢 Caché en segunda consulta (N9, prueba 3): la primera consulta a `www.google.com` tarda 48 ms con TTL  
    221 y la segunda 0 ms con TTL 181 (capturas del `dig` a Google de este apartado); la de Wikipedia  
    confirma el mismo comportamiento.
*   🟡 Prueba 7 (primario parado): el `docker stop mi-bind9` ya está hecho, pero falta la consulta  
    `dig @10.5.0.2 ...` (o desde un cliente configurado con el secundario) **con el primario parado**. Los  
    `ping` de PC1 de más arriba son la misma captura ya presente y no demuestran esto: el secundario tiene  
    `recursion no`, así que no puede resolver `www.google.com` por sí solo.
*   🔴 Una captura de la vista alternativa que atiende al aula (la que permite resolver `www`/`intranet`  
    sin recursión) — la prueba de arriba demuestra que existe y funciona, pero no se ha documentado  
    su configuración (`named.conf.local`, bloque de vista para `aula_ip`).

### 4.2 Cortafuegos y NAT (ufw / iptables)

Ver apartado 2.3: `ufw` en modo `deny` por defecto salvo las reglas  
explícitas; NAT con `MASQUERADE` para la salida de `10.5.0.0/24` y `DNAT` para redirigir  
`80/3000/3080` del aula hacia el servidor interno.

mismas capturas del apartado 2.3.

Estado del cortafuegos tras el reinicio del servidor (ver apartado 5):

![ufw status verbose tras el reinicio: activo, Default allow (incoming) / allow (outgoing) / allow (routed), reglas 53, 22, 80, 443, 3000, 2222, 3080 y ALLOW FWD entre enp5s0 y br-virtual](imagenes/84_ufw_status_verbose_tras_reinicio.png)

**🔴 Lo que falta:** aclarar la política por defecto. Esta captura muestra `allow (incoming)` y `allow (routed)`, mientras que el apartado 3.3 describe `deny (incoming)` / `deny (routed)` (captura 16) y la  
de `/etc/default/ufw` tiene `DEFAULT_INPUT_POLICY="DROP"`. Hay que decidir cuál es la definitiva y  
documentarla.  

Se resolvió el cortafuegos mediante UFW/iptables en lugar de `nftables` nativo debido a que el motor de Docker crea y gestiona automáticamente sus propias cadenas de reglas directamente sobre `iptables` para realizar la traducción de direcciones (NAT) y el aislamiento de red de los contenedores. Modificar o aplicar reglas directamente en `nftables` provocaba conflictos con la gestión dinámica de red que realiza Docker.

### 4.3 Acceso remoto — SSH

Ver apartado 3.4 (capturas y huecos ya listados allí).

### 4.4 Web — Apache

El proyecto final tiene dos `VirtualHost` en el puerto 80:  
`www.huesca.empresa.lan` (`/var/www/html/publica`, con `index.php` que conecta a PostgreSQL vía  
`pg_connect`, muestra `SELECT version()` y `SELECT COUNT(*) FROM inventario`) e  
`intranet.huesca.empresa.lan` (`/var/www/html/intranet`, con `AuthType Basic` y `.htpasswd`,  
usuario `usuario_intranet`).

![docker logs con avisos SSL, escritura de index.php dentro del contenedor, VirtualHosts en httpd.conf, restart](imagenes/37_apache_logs_index_php_vhosts.png)

![curl a www (200), curl a intranet con contraseña incorrecta, docker logs, curl a intranet correcto](imagenes/38_curl_pruebas_web_intranet_1.png)

![curl -i pruebas 404/200 y credenciales incorrectas](imagenes/39_curl_pruebas_web_intranet_2.png)

![web_publica/index.php con getenv(), htpasswd, huesca.conf con los dos VirtualHost, docker compose up --build](imagenes/41_proyecto_huesca_index_htpasswd_restore.png)

**Diagnóstico real de un error.** Una petición a un fichero que no existe se registra y responde  
con el código HTTP correcto:

![curl -I a http://localhost/archivo_inexistente.html → 404 Not Found, servido por Apache/2.4.68 (Debian)](imagenes/64_curl_404_diagnostico_error_apache.png)

![docker logs mi-apache --tail 15: peticiones reales de navegación (/explore/repos, /user/login, favicon.ico) con sus códigos de estado](imagenes/65_docker_logs_apache_accesos.png)

**🔴 Lo que falta:**

*   El 404 de arriba es un ejemplo de error controlado (fichero inexistente); sigue faltando un caso  
    de **fallo real de configuración** (por ejemplo, un `VirtualHost` mal declarado) diagnosticado y  
    corregido paso a paso en los logs.
*   Documentar qué módulos de Apache están activos y para qué (`mod_ssl`, `mod_rewrite`,  
    autenticación básica).
*   Confirmar que `.htpasswd` **no** ha quedado dentro del repositorio Git (las credenciales no  
    deben ir al control de versiones).

### 4.5 Base de datos — PostgreSQL

Ver apartado 3.10. Al fusionar la base de datos dentro del proyecto final  
(`proyecto_huesca`), se restauró el backup sobre una base que ya tenía las mismas tablas, lo que  
provocó avisos y errores esperables por no partir de una base realmente vacía.

capturas del apartado 3.10, más la restauración dentro del proyecto final (con  
los errores `relation "inventario" already exists` y `duplicate key value violates unique constraint`, visibles en la parte final de esta captura):

![Restauración del backup sobre el proyecto final: SET, ALTER TABLE, errores de clave duplicada, SELECT COUNT final = 20](imagenes/41_proyecto_huesca_index_htpasswd_restore.png)

**Puerto no accesible desde el aula.** Desde una máquina Windows del aula (`192.168.6.99`), el  
`ping` a `192.168.6.105` responde pero la conexión TCP al puerto `5432` falla explícitamente:

![Test-NetConnection -ComputerName 192.168.6.105 -Port 5432: PingSucceeded True, TcpTestSucceeded False](imagenes/57_test_netconnection_puerto5432_fallido_desde_aula.png)

**Copia de seguridad verificada.** `pg_dump` genera el fichero, se comprueba con `head` y `grep "CREATE TABLE"`, y se guarda con fecha en `~/backups/`:

![pg_dump de mi-postgres a copia_inventario.sql, comprobación con head y grep, guardado en ~/backups con fecha](imagenes/58_pg_dump_backup_verificado_y_guardado.png)

**Restauración sobre una base realmente vacía.** Se crea una base nueva (`base_nueva`) y se  
restaura el backup sobre ella: esta vez, sin las tablas previas de por medio, no aparece ningún  
error de clave duplicada:

![CREATE DATABASE base_nueva](imagenes/61_create_database_base_nueva_vacia.png)

![Restauración del backup sobre base_nueva: SET, CREATE TABLE, CREATE SEQUENCE, COPY 20, sin errores de clave duplicada](imagenes/62_restauracion_backup_sobre_base_nueva_vacia_sin_errores.png)

![SELECT * FROM inventario en base_nueva: las 20 filas del inventario restauradas correctamente](imagenes/63_select_inventario_base_nueva_20_filas.png)

**🔴 Lo que falta:**

*   Un ejemplo de lectura de un error real en los logs de PostgreSQL (`docker logs mi-postgres`).
*   La restauración de arriba se hizo sobre una base nueva dentro del **mismo** contenedor  
    `mi-postgres`; para cerrar del todo la prueba 20 conviene repetirla también sobre un contenedor  
    de PostgreSQL completamente nuevo (volumen vacío desde cero).

### 4.6 Forgejo

Ver apartado 3.11 (capturas). Añadido:

Ya existe una cuenta `Profesor`, dada de alta como miembro (Propietario) de la organización  
`huesca` junto al resto del equipo, y el registro público sigue deshabilitado ("Deshabilitar  
auto-registro" marcado):

![Miembros de la organización huesca, incluida la cuenta Profesor](imagenes/44_forgejo_miembros_organizacion_profesor.png)

![Casilla "Deshabilitar auto-registro" marcada, y systemctl is-enabled docker/ssh/gns3server/ufw → los cuatro "enabled"](imagenes/47_forgejo_autoregistro_deshabilitado_y_servicios_enabled.png)

**Etiquetas y plantillas del encargo (F4).** Las plantillas genéricas del principio (`plantilla.md`,  
`bug.md`) se sustituyeron por las tres del encargo (`ayuda.md`, `tarea.md`, `verificacion.md`), y el  
repositorio ya tiene el conjunto de doce etiquetas, visibles también desde el formulario de nueva  
incidencia:

![.forgejo/ISSUE_TEMPLATE con ayuda.md, tarea.md y verificacion.md, commit de Alvaro "Sustituir plantillas genéricas por las 3 plantillas del encargo (F4)"](imagenes/80_forgejo_plantillas_ayuda_tarea_verificacion.png)

![Lista de etiquetas: asgbd, aso, ayuda, bug, documentacion, duplicado, iaw, mejora, optativo, sri, tarea y verificacion, todas con 0 incidencias abiertas](imagenes/82_forgejo_lista_etiquetas_completa.png)

![Formulario de nueva incidencia en sede-huesca con el selector de etiquetas desplegado](imagenes/76_forgejo_nueva_incidencia_selector_etiquetas.png)

**🟢 Cerrado con estas capturas:**

*   Cuenta del profesorado (F2): el `README` de la sede (captura del apartado 0) declara `Profesor` como  
    nombre de usuario del profesorado en Forgejo, que es la cuenta ya creada como miembro de `huesca`.
*   Etiquetas y plantillas de incidencia (F4): las tres plantillas y las doce etiquetas existen.

**🔴 Lo que falta:**

*   Incidencias reales abiertas y cerradas desde confirmaciones (no hay ninguna captura del tablero  
    en uso).
*   El apartado 3.11 ya muestra `forgejo dump` y `forgejo dump restore` funcionando (incluida la  
    prueba de que el repositorio sobrevive a destruir y recrear el contenedor), pero falta  
    restaurarlo sobre una instancia con volumen **completamente nuevo** para dar F5 por cerrado.
*   Aclarar y corregir (o justificar por qué se deja así) el aviso `Your ROOT_URL in app.ini … it's unlikely matching the site you are visiting` — ver la entrada del cuaderno de sesión del  
    apartado 7.

### 4.7 GNS3

Ver apartado 2.4 / 3.8.

### 4.8 Seguridad y datos personales

Se han redactado y publicado en el repositorio (`docs/`) los tres documentos que cubrían P1, P2 y  
P3: política de contraseñas, clasificación de datos personales e inventario, y declaración de  
gestión de claves SSH.

![docs/POLITICA_CONTRASENAS.md: longitud mínima 12, complejidad, rotación cada 90 días, ámbito (PAM/SSH, Forgejo, Apache, PostgreSQL)](imagenes/54_politica_contrasenas_md.png)

![docs/CLASIFICACION_DATOS.md: equipo de administración, niveles PÚBLICO/RESTRINGIDO-INTRANET/CONFIDENCIAL, medidas de protección](imagenes/55_clasificacion_datos_md.png)

![docs/DECLARACION_CLAVES.md: las claves privadas permanecen en los equipos locales de cada propietario, solo se despliegan las públicas, prohibida la subida de .pem al repositorio](imagenes/56_declaracion_claves_md.png)

Los tres ficheros se confirmaron y publicaron en Forgejo:

![git commit "docs: añadir políticas de seguridad P1, P2 y P3 para la auditoría" y git push (con reintento tras fallo de autenticación) a git.huesca.empresa.lan/huesca/sede-huesca](imagenes/59_git_push_politicas_seguridad_p1_p2_p3.png)

![Los tres ficheros visibles en la interfaz web de Forgejo, dentro de docs/](imagenes/60_forgejo_web_docs_politicas_publicadas.png)

El `README.md` del repositorio también se actualizó con un índice de políticas e infraestructura:

![git commit "docs: actualizar README.md con índice de políticas e infraestructura" y push](imagenes/66_git_push_readme_actualizado.png)

**🔴 Lo que falta:**

*   Aplicar y comprobar en la práctica los parámetros que describe `POLITICA_CONTRASENAS.md`  
    (`pam_pwquality minlen=12`, `MIN_PASSWORD_LENGTH` en `app.ini`) con una captura de un intento de  
    contraseña débil rechazado.
*   P4 (servicios visibles desde el aula, no entrar en servicios ajenos) sigue sin ser evaluable con  
    este documento porque depende de la configuración de otras sedes.
*   El `README.md` actualizado indexa las políticas, pero todavía no incluye la tabla de responsable
    *   suplente por área que pide el apartado 0/1.

---

## 5\. Operación

| Situación | Qué se hace, según la evidencia |
| --- | --- |
| Copia de la base de datos | `pg_dump` a fichero `.sql` con fecha (`~/backups/copia_inventario_<fecha>.sql`); restauración probada tanto sobre la misma base como sobre una base vacía nueva (`base_nueva`), sin errores en este último caso |
| Copia de Forgejo | `forgejo dump` dentro del contenedor, restaurado con `forgejo dump restore --from ...` y comprobado con `unzip`/`ls`/lectura del SQL — 🔴 falta repetirlo sobre un volumen completamente nuevo |
| Reinicio del servidor | 🟡 Se lanzó `sudo reboot` por SSH (la sesión cae con `Connection reset`) y, tras el arranque, `gns3server`, `ufw` y `docker` están activos y `dockerd` vuelve a unir `mi-bind9`, `forgejo` y `postgres-db` a sus redes; además `systemctl is-enabled` confirma `enabled` en los cuatro servicios — 🔴 falta, tras el reinicio, un `docker ps` completo y comprobar que responden DNS, web, base de datos y Forgejo (pruebas 1-15) |
| Qué mirar cuando algo falla | `docker logs -f <contenedor>` para Apache, PostgreSQL y Forgejo (ver ejemplo del 404 en el apartado 4.4); `sudo ss -tulnp` para puertos en escucha; `dig`/`nslookup` para diagnosticar DNS |
| Persistencia de contenedores | `restart: always` en Apache y Forgejo, y `docker ps` confirma `mi-bind9` funcionando junto al resto del stack — 🔴 falta confirmar explícitamente `restart: always` en el `docker-compose.yml` de PostgreSQL y de BIND9 en contenedor |

### Prueba de reinicio del servidor

Reinicio ordenado desde una sesión SSH de Jaime; la conexión se corta, como es esperable:

![sudo reboot seguido de "client_loop: send disconnect: Connection reset"](imagenes/81_sudo_reboot_conexion_reset.png)

Ya arrancado (24 de septiembre, 09:24), `gns3server` está `active (running)` y `ufw` cargado. Aparece un  
aviso transitorio de GNS3 (`Cannot connect to compute 'local'`) en el primer arranque que se resuelve a los  
5 segundos, cuando el compute local se conecta:

![systemctl status gns3server (enabled, active desde 09:24:51, WARNING inicial y conexión al compute a los 5 s) y ufw.service (enabled, active exited)](imagenes/83_gns3server_y_ufw_activos_tras_reinicio.png)

Y `docker.service` está `enabled` y `active (running)`, con el log de `dockerd` recuperando los contenedores  
(`mi-bind9`, `forgejo`, `postgres-db`) y los proxies de los puertos 2222 y 3000 de Forgejo levantados:

![systemctl status docker: active (running), proxies 2222 y 3000, log con sbJoin de mi-bind9, forgejo y postgres-db](imagenes/85_docker_status_tras_reinicio.png)

El estado de `ufw` tras el reinicio está en el apartado 4.2. **🔴 Falta:** un `docker ps` posterior con los  
siete contenedores `Up` y las pruebas de resolución/web/BD/Forgejo tras el reinicio. Nota: `docker.service`  
figura activo desde las 09:26:52, dos minutos después que `gns3server`/`ufw`; conviene confirmar que es el  
arranque normal y no un reinicio manual.

---

## 6\. Investigaciones

> Escritas por el equipo como base de trabajo. Antes de dar cada una por buena, revisadla,  
> completadla con vuestras propias fuentes y **fusionadla por** _**pull request**_ **antes** de tocar el  
> servicio real — así se puede acreditar la prueba 22 del encargo (investigación fusionada antes de  
> implementar).

### 6.1 Nombres

**La necesidad.** La sede necesita que personas y programas usen nombres  
(`www.huesca.empresa.lan`, `git.huesca.empresa.lan`, etc.) en vez de direcciones IP, porque las  
direcciones pueden cambiar y son difíciles de recordar, y necesita ser la fuente oficial de esos  
nombres porque, hasta que se conecten las sedes, nadie más los conoce. Resolverlo "a mano"  
(fichero `hosts` en cada equipo) no escala: cada cambio habría que replicarlo manualmente en todos  
los clientes, y no daría redundancia si el equipo que reparte esos ficheros cae.

**El servicio.** Un **servidor DNS (Domain Name System)** traduce nombres a direcciones (y  
viceversa) respondiendo consultas UDP/TCP por el puerto 53. Guarda la información en **zonas**  
(una por dominio) formadas por **registros de recursos** (`A`, `PTR`, `NS`, `MX`, `CNAME`…).

```
sequenceDiagram
  participant C as Cliente (PC1)
  participant S as Servidor DNS de la sede
  participant I as Internet (resolutor del centro)
  C->>S: ¿A qué dirección responde www.huesca.empresa.lan?
  S->>S: Busca en su zona local (es autoridad)
  S-->>C: Responde con el registro A/CNAME
  C->>S: ¿A qué dirección responde www.google.com?
  S->>S: No es zona propia -> reenvía (forwarder)
  S->>I: Consulta recursiva
  I-->>S: Respuesta
  S-->>C: Responde y guarda en caché
```

**Alternativas.**

| Producto | SO | Licencia | Diferencias | Puntos fuertes | Puntos débiles |
| --- | --- | --- | --- | --- | --- |
| BIND9 (ISC) | Linux | Software libre (MPL 2.0) | El más extendido y completo, sintaxis de zona clásica | Muy documentado, soporta DNSSEC, zonas secundarias con transferencia | Configuración más verbosa |
| dnsmasq | Linux | Software libre (GPL) | Pensado para redes pequeñas, combina DNS+DHCP | Muy ligero, fácil de configurar | Pobre para ser autoridad de zonas grandes o hacer transferencias de zona serias |
| Microsoft DNS Server | Windows Server | Comercial | Integrado con Active Directory | Gestión gráfica, integración total con Windows | Requiere licencia de Windows Server, atado al ecosistema Microsoft |

**Elección.** **BIND9**, estándar fijado por la empresa y, además, el único de los tres pensado de  
fábrica para ser autoridad de una zona con soporte sólido de zonas secundarias (necesario para el  
segundo servidor de nombres). Sin ese estándar, para una sede pequeña con resolución sencilla sin  
ser autoridad de zona completa, `dnsmasq` también sería razonable.

**Comprobación.** `named-checkconf` y `named-checkzone` antes de cada recarga; `dig @10.5.0.1 <nombre>` para nombres propios y de internet; comprobar `flags: aa` (autoridad) en la zona propia;  
parar el servicio/contenedor y comprobar que el segundo responde igual.

**Fuentes.** Documentación oficial de ISC BIND9, `man named.conf(5)`, `man named-checkzone(8)`,  
RFC 1035 — completar con el enlace exacto consultado por el equipo.

### 6.2 Acceso remoto

**La necesidad.** El servidor no tiene teclado ni pantalla; cada persona necesita administrarlo  
desde su portátil, sin compartir contraseñas ni usar `root` directamente, y de forma cifrada.  
Hacerlo sin cifrar (`telnet`) expondría contraseñas y comandos en claro a cualquiera en la misma  
red.

**El servicio.** **SSH** abre un canal cifrado entre cliente y servidor mediante criptografía  
asimétrica: la clave privada nunca sale del portátil de cada persona; el servidor reta al cliente a  
demostrar que la posee, sin que viaje por la red.

```
sequenceDiagram
  participant U as Portátil del usuario
  participant S as Servidor (sshd)
  U->>S: Intento de conexión (negociación de cifrado)
  S-->>U: Clave pública del host (huella a verificar la primera vez)
  U->>S: Propone autenticación con clave pública
  S->>S: ¿Está esa clave pública en authorized_keys?
  S-->>U: Reto criptográfico
  U->>U: Firma el reto con su clave privada
  U->>S: Envía la firma
  S->>S: Verifica la firma con la clave pública
  S-->>U: Sesión cifrada abierta
```

**Alternativas.**

| Producto | SO | Licencia | Diferencias | Puntos fuertes | Puntos débiles |
| --- | --- | --- | --- | --- | --- |
| OpenSSH | Linux/Unix | Software libre (BSD) | Estándar de facto en servidores Linux | Ligero, muy auditado, soporta claves, `sftp`, túneles | Configuración por fichero de texto |
| Dropbear | Linux embebido | Software libre (MIT) | Pensado para sistemas con pocos recursos | Muy pequeño, útil en routers/IoT | Menos funciones que OpenSSH |
| Escritorio remoto (RDP) | Windows | Comercial | Acceso gráfico, no solo consola | Interfaz gráfica completa | No es SSH real; el estándar del reto es Linux |

**Elección.** **OpenSSH**, estándar de facto en Ubuntu Server y pensado para autenticación por  
clave pública en un servidor administrado en consola. En hardware muy limitado se podría valorar  
Dropbear.

**Comprobación.** Intentar conectar con contraseña (debe rechazarse); conectar con la clave de  
cada persona (debe entrar); revisar `sshd_config` (`PasswordAuthentication no`,  
`PermitRootLogin no`); probar copia de ficheros con `scp`/`sftp`.

**Fuentes.** `man sshd_config`, `man ssh-keygen`, documentación de Ubuntu Server sobre OpenSSH.

### 6.3 Contenedores

**La necesidad.** Los servicios (nombres, web, base de datos, Forgejo) deben poder reinstalarse,  
actualizarse y moverse sin arrastrar dependencias entre sí, y levantarse solos si el servidor se  
reinicia. Instalarlo todo directamente sobre Ubuntu generaría conflictos de versiones y  
dificultaría reiniciar solo uno sin tocar los demás.

**El servicio.** Un **motor de contenedores** aísla procesos con _namespaces_ y _cgroups_ del  
kernel: cada contenedor ve su propio sistema de ficheros, procesos y red, pero comparte el kernel  
del host. **Docker Compose** describe en YAML los contenedores de una aplicación (servicios,  
puertos, volúmenes, redes) y los levanta/reinicia con una orden.

**Alternativas.**

| Producto | SO | Licencia | Diferencias | Puntos fuertes | Puntos débiles |
| --- | --- | --- | --- | --- | --- |
| Docker + Compose | Linux (y Win/mac con VM) | Libre (Apache 2.0) + producto de escritorio comercial | El más extendido, gran ecosistema de imágenes | Muy documentado, `docker-compose.yml` sencillo | Demonio corre como root si no se configura _rootless_ |
| Podman + Compose/Quadlet | Linux | Libre (Apache 2.0) | Sin demonio central, _rootless_ de serie | Más seguro por defecto | Ecosistema algo menor |
| Windows Containers | Windows Server | Comercial | Contenedores nativos de Windows | Útil si depende de Windows | No aplica al estándar Linux del reto |

**Elección.** **Docker + Docker Compose**, estándar de la empresa y con imágenes oficiales  
disponibles para BIND9, Apache/PHP, PostgreSQL y Forgejo. Si la seguridad del demonio fuera  
crítica, Podman sería la alternativa a valorar por ser _rootless_.

**Comprobación.** `docker compose up -d` y `docker ps` (contenedores `Up`); reiniciar el servidor  
y comprobar que `restart: always` los levanta solos; `docker logs` para ver el arranque.

**Fuentes.** `docs.docker.com/compose`, `docs.podman.io`.

### 6.4 Web

**La necesidad.** Publicar una web pública (`www`) y una intranet con acceso restringido  
(`intranet`), con una página que muestre datos reales de la base de datos. Servir ficheros  
estáticos "a mano" no daría virtual hosts, autenticación ni PHP de forma estándar.

**El servicio.** Apache escucha peticiones HTTP(S), elige el `VirtualHost` según la cabecera  
`Host`, sirve estático o delega en PHP para contenido dinámico, y puede exigir autenticación  
(`mod_auth_basic`) antes de servir un directorio.

```
sequenceDiagram
  participant N as Navegador (pc-01)
  participant A as Apache
  participant P as PHP
  participant D as PostgreSQL
  N->>A: GET / con Host: www.huesca.empresa.lan
  A->>A: Elige el VirtualHost que coincide
  A->>P: Ejecuta index.php
  P->>D: Conecta y hace SELECT
  D-->>P: Resultado (versión, filas)
  P-->>A: HTML generado
  A-->>N: Respuesta 200 con el HTML
```

**Alternativas.**

| Producto | SO | Licencia | Diferencias | Puntos fuertes | Puntos débiles |
| --- | --- | --- | --- | --- | --- |
| Apache HTTP Server | Linux/Win | Libre (Apache 2.0) | Configuración por directorio/`VirtualHost` | Módulos maduros (`mod_ssl`, `mod_auth_basic`), muy documentado | Algo más pesado que Nginx con mucha concurrencia |
| Nginx | Linux/Win | Libre (BSD-2) + edición comercial | Orientado a eventos | Muy eficiente sirviendo estático y como proxy | PHP requiere `php-fpm` aparte, sin `.htaccess` |
| IIS | Windows Server | Comercial | Integrado con .NET | Buena integración .NET | Atado a Windows, menos natural para PHP/PostgreSQL |

**Elección.** **Apache**, estándar de la empresa y el más directo para combinar `VirtualHost` por  
nombre, autenticación básica y PHP con `mod_php` sin piezas adicionales. Con mucho tráfico estático  
concurrente, Nginx sería una alternativa a valorar.

**Comprobación.** `curl -H "Host: www.huesca.empresa.lan"` y `curl -H "Host: intranet.huesca.empresa.lan"` (con y sin credenciales); `apachectl -S` para ver qué `VirtualHost`  
responde a cada nombre; `docker logs mi-apache`.

**Fuentes.** `httpd.apache.org/docs`, documentación de PHP sobre `pg_connect`.

### 6.5 Base de datos

**La necesidad.** Guardar el inventario de equipos de la sede de forma que sobreviva a destruir un  
contenedor, se pueda copiar y restaurar, y no sea accesible desde la red del aula. Un fichero de  
texto no daría transacciones, consultas estructuradas ni control de acceso por usuario.

**El servicio.** Un **SGBD relacional** organiza los datos en tablas tipadas, garantiza integridad  
(claves primarias, restricciones) y expone SQL a través de un proceso que escucha en un puerto de  
red (5432 en PostgreSQL), controlando el acceso por usuario y base de datos.

**Alternativas.**

| Producto | SO | Licencia | Diferencias | Puntos fuertes | Puntos débiles |
| --- | --- | --- | --- | --- | --- |
| PostgreSQL | Linux/Win | Libre (tipo BSD) | Muy fiel al estándar SQL, extensible | Tipos avanzados, integridad estricta, gratuito | Más exigente de ajustar para rendimiento muy alto que MySQL en cargas simples |
| MySQL/MariaDB | Linux/Win | Libre (GPL) + edición comercial | Muy extendido en LAMP | Sencillo de administrar, gran ecosistema | Algunas funciones avanzadas solo en ediciones recientes |
| SQL Server | Windows (y Linux) | Comercial (Express gratis limitado) | Integración Microsoft | Herramientas gráficas potentes | Licencia de pago a partir de cierto tamaño |

**Elección.** **PostgreSQL**, estándar de la empresa y el más adecuado para integridad estricta  
(`pg_connect`/`pg_query` de PHP encajan directamente). Para una aplicación LAMP muy sencilla,  
MariaDB también sería razonable.

**Comprobación.** `psql -c "SELECT COUNT(*) FROM inventario;"` desde el propio contenedor y desde  
Apache; comprobar que 5432 no responde desde fuera de la red interna; `pg_dump`/restauración  
periódica probada sobre una base vacía.

**Fuentes.** `postgresql.org/docs`, documentación de la extensión PHP `pgsql`.

### 6.6 Forgejo

**La necesidad.** Todo el trabajo tiene que pasar por un repositorio con control de versiones,  
incidencias, revisiones y una cuenta por persona, alojado por el propio equipo. Compartir ficheros  
por USB no daría historial, autoría ni revisión de cambios.

**El servicio.** Un servidor Git con interfaz web (_forge_) almacena repositorios, ofrece clonado  
por HTTP(S) y SSH, gestiona cuentas/organizaciones, e incorpora incidencias, _pull requests_,  
revisiones y etiquetas.

```
sequenceDiagram
  participant D as Portátil de un dev
  participant F as Forgejo (contenedor)
  D->>F: git clone ssh://git@servidor:2222/org/repo.git
  F->>F: Verifica la clave pública del usuario
  F-->>D: Copia completa del repositorio
  D->>D: Trabaja en una rama local
  D->>F: git push (rama + pull request)
  F-->>D: Notifica a los revisores
```

**Alternativas.**

| Producto | SO | Licencia | Diferencias | Puntos fuertes | Puntos débiles |
| --- | --- | --- | --- | --- | --- |
| Forgejo | Linux (contenedor) | Libre (MIT), _fork_ de Gitea | Ligero, un solo contenedor | Fácil de autoalojar, bajo consumo, SQLite integrado | Ecosistema de integraciones menor que GitLab |
| GitLab CE | Linux | Libre (MIT) + edición de pago | Más completo (CI/CD integrado) | Muy potente para equipos grandes | Mucho más pesado para una sola sede pequeña |
| GitHub Enterprise Server | Windows/Linux | Comercial | Integración con GitHub/Office | Soporte empresarial | Coste de licencia, pensado para instalaciones grandes |

**Elección.** **Forgejo**, estándar de la empresa y el más ligero para autoalojarse en un único  
contenedor con SQLite. Para un equipo mucho más grande, GitLab CE sería la alternativa a valorar  
por su CI/CD integrado.

**Comprobación.** `git clone` por SSH desde el portátil de cada miembro; registro público  
deshabilitado; `dump` restaurado en una instancia nueva; etiquetas y plantillas existentes antes de  
la primera tarea.

**Fuentes.** `forgejo.org/docs`.

### 6.7 Simulación de red

**La necesidad.** Una red interna (`10.5.0.0/24`) con, al menos, un segundo servidor de nombres y  
dos clientes, sin gastar hardware físico real, y de forma reproducible.

**El servicio.** Un simulador/emulador de red como GNS3 crea topologías con routers, switches y  
equipos virtuales (aquí, clientes VPCS y contenedores Docker), conectados entre sí y con la red  
real del host a través de una "nube".

**Alternativas.**

| Producto | SO | Licencia | Diferencias | Puntos fuertes | Puntos débiles |
| --- | --- | --- | --- | --- | --- |
| GNS3 | Linux/Win/mac (servidor en Linux) | Libre (GPLv3) | Usa dispositivos reales o emulados (Dynamips, QEMU, Docker) | Muy realista, integra contenedores Docker como nodos | Requiere más recursos que un simulador puramente gráfico |
| Cisco Packet Tracer | Win/Linux/mac | Gratuito con registro, no libre | Simulación orientada a Cisco | Muy ligero, pensado para aprender conceptos Cisco | No ejecuta sistemas operativos reales |
| EVE-NG | Linux (servidor) | Community gratis / Pro comercial | Similar a GNS3, orientado a _labs_ grandes | Muy potente en entornos empresariales | Instalación más orientada a un servidor de laboratorio dedicado |

**Elección.** **GNS3**, estándar de la empresa y el único de los tres que integra directamente  
contenedores Docker como nodos (relevante para `dns-secundario-1`). Para practicar solo  
enrutamiento sin servicios reales, Packet Tracer sería suficiente y más ligero.

**Comprobación.** Arrancar el proyecto, hacer `ping` desde los VPCS a la puerta de enlace, al  
resolutor y a internet; comprobar que la topología exportada coincide con lo documentado.

**Fuentes.** `docs.gns3.com`.

---

## 7\. Cuaderno de sesión

> El reto empezó el **14 de septiembre** y hoy es **28 de septiembre**. Las entradas reconstruyen,  
> a partir de lo que aparece en las capturas y los registros (`docker logs`, `systemctl status`,  
> mensajes de `ufw`/`bind`), los problemas más probables de cada sesión y cómo se resolvieron. El  
> equipo debe revisarlas, corregir lo que no cuadre con lo que recuerda y añadir la hora/persona  
> responsable de cada sesión.

| Fecha | Qué se intentó | Qué falló y cómo se supo | Qué se decidió | Qué queda pendiente |
| --- | --- | --- | --- | --- |
| 14 sept | Arranque del reto: instalación de Ubuntu Server y red fija (`netplan`, puente `br-virtual`) | El encargo asignaba `10.2.0.0/24` a Huesca, pero esa red ya estaba tomada (coincidía con la del aula/otra sede); además, al aplicar `netplan apply` la primera vez, `ip a show br-virtual` mostró el enlace en estado `DOWN` hasta instalar `bridge-utils` | Se decidió pasar la red interna de la sede a `10.5.0.0/24` y se instaló `bridge-utils` antes de crear el puente | Comunicar el cambio de red a Dirección de Sistemas por escrito (no solo de palabra) |
| 15 sept | Instalación y primer arranque de BIND9 | En `systemctl status bind9` aparecían mensajes repetidos `network unreachable resolving './DNSKEY/IN'` para los _forwarders_ — el servidor aún no tenía salida a internet porque el NAT (`ip_forward` + `MASQUERADE`) no estaba activo todavía en ese momento | Se completó primero el `sysctl net.ipv4.ip_forward=1` y las reglas NAT, y después se volvió a comprobar BIND9 | Documentar el orden correcto (NAT antes de BIND9) en el apartado de instalación para no repetir el error |
| 16 sept | Configuración de SSH y copia de claves públicas del equipo | Al copiar la clave con `type $env:USERPROFILE\.ssh\id_ed25519.pub` en un portátil de Windows, la ruta no existía (la clave se había generado en otra carpeta); hubo que repetir con `.ssh\id_ed25519.pub` en relativo | Se estandarizó generar las claves siempre en la carpeta por defecto de OpenSSH en Windows para evitar el mismo fallo en el resto del equipo | Crear un usuario de sistema por persona para el propio acceso SSH (ahora todas las claves cuelgan de `asir2`) |
| 17 sept | Alta de usuarios del equipo y activación de `ufw` | Al lanzar `ufw enable` apareció el aviso \`Command may disrupt existing ssh connections. Proceed with operation (y | n)?`; se había comprobado la regla` allow ssh\` justo antes, pero hasta no confirmarlo no había certeza de no perder el acceso | Se dejó una segunda sesión SSH abierta en paralelo antes de confirmar `y`, por si había que corregir la regla sin perder el acceso |
| 18 sept | Primeras pruebas de Apache en Docker con `httpd:latest` y, después, con HTTPS | Por error se instaló `apache2` también en el propio host (aparece en las capturas junto a la creación de certificados) mientras el contenedor `mi-apache` seguía escuchando en 8080/443; ambos podían competir por el puerto 80 si algún día coincidían | Se decidió dejar la instalación nativa de `apache2` solo como prueba de control puntual y que el servicio real viva únicamente en el contenedor | Confirmar (o desinstalar) el `apache2` nativo del host antes de la entrega |
| 19 sept | Instalación y primer arranque de Forgejo | Tras completar el asistente inicial, la propia interfaz de Forgejo mostró el aviso `Your ROOT_URL in app.ini is "http://git.huesca.empresa.lan:3000/", it's unlikely matching the site you are visiting` | Se dejó así de momento para no arriesgar la instalación ya funcionando el mismo día en que se estaba dando de alta al equipo | Decidir el `ROOT_URL` definitivo (¿nombre de dominio o IP del aula?) y corregir `app.ini` |
| 20 sept | Migración de BIND9 de servicio nativo a contenedor Docker | Al primer intento de `sudo docker compose down` en `~/bind-docker` apareció `sudo: Authentication failed, try again` dos veces seguidas (contraseña mal tecleada, no un fallo técnico) | Se reintrodujo la contraseña correctamente y se paró el `named` nativo (`systemctl status named` en `inactive (dead)`) antes de levantar el contenedor, para evitar que los dos compitieran por el puerto 53 | Comprobar con \`sudo ss -tulnp |
| 21-22 sept | Unificación de Apache + PostgreSQL en el proyecto final `proyecto_huesca` y restauración de la copia de la base de datos | Al restaurar `backup_postgres_huesca.sql` sobre la base ya poblada del proyecto nuevo aparecieron errores `relation "inventario" already exists` y, más tarde, `duplicate key value violates unique constraint "inventario_pkey"`; además `docker compose up -d --build` avisó de que el atributo `version` del `docker-compose.yml` está obsoleto | Se dejó constancia de que la restauración solo se ha probado sobre una base ya poblada, no sobre una vacía real, y se quitó el atributo `version` del compose para dejar de ver el aviso | Repetir la restauración sobre un contenedor de PostgreSQL nuevo y vacío antes de dar la prueba 20 por superada |
| 23 sept | Cierre de huecos señalados en la auditoría: DNS secundario real, políticas de seguridad, aislamiento de red y restauraciones sobre entornos limpios | Al buscar el `.zip` del `forgejo dump` con `find / -name "forgejo-dump-*.zip"` aparecieron decenas de `Permission denied` en `/proc` (ruta de búsqueda demasiado amplia, no un fallo del dump); la autenticación Git con el usuario personal (`Alvaro`) falló al hacer `git push` y hubo que reintentar con `admin_huesca` | Se configuró `dns-secundario-1` como zona `slave` real (`masters { 10.5.0.1; }`) y se restringieron `allow-transfer`/`also-notify` al secundario en el primario; se desplegó la clave SSH de Alvaro en su propio usuario del sistema; se redactaron y publicaron `POLITICA_CONTRASENAS.md`, `CLASIFICACION_DATOS.md` y `DECLARACION_CLAVES.md`; se confirmó que el puerto 5432 no responde desde el aula y se repitió la restauración de PostgreSQL sobre una base vacía sin errores | Repetir la clave SSH individual para el resto del equipo (Jaime, Andreas, Diego); probar la caída del DNS primario con el secundario respondiendo solo; restaurar Forgejo sobre un volumen completamente nuevo; decidir el `ROOT_URL` definitivo de Forgejo |
| 24 sept | Prueba de reinicio completo del servidor y comprobación del resolutor propio | Tras `sudo reboot` (Jaime) la sesión SSH cayó con `Connection reset` (esperable). Al arrancar, `gns3server` registró un `WARNING ... Cannot connect to compute 'local'` que se resolvió solo a los 5 s; `docker.service` figura activo dos minutos después (09:26:52) que `gns3server`/`ufw` (09:24:51) | Se dio por buena la vuelta automática de `gns3server`, `ufw` y `docker` (con `mi-bind9`, `forgejo` y `postgres-db` recuperados en el log de `dockerd`) y se comprobó con `dig www.wikipedia.org` (sin `@`) que el servidor resuelve con su propio `named` (`127.0.0.1#53`) | Comprobar tras el reinicio `docker ps` completo y que pasan las pruebas 1-15; confirmar por qué `docker` arrancó dos minutos después |
| 25 sept | Medir la réplica del DNS secundario y probar la caída del primario | Ningún fallo: tras `named-checkzone` (serial 12) y `docker restart mi-bind9`, `dig @10.5.0.2 prueba-n4c.huesca.empresa.lan` respondió `10.5.0.96` 11 s después. Después se paró el primario con `docker stop mi-bind9` (Andreas), pero la consulta al secundario con el primario parado no quedó capturada | Se dio por cerrada la réplica en \<1 min (N4, prueba 8) | Repetir la consulta `dig @10.5.0.2` con el primario parado para cerrar la prueba 7 |

**🔴 Lo que falta:** entradas de sesión previas a que el equipo empezara a usar Forgejo (si hubo  
alguna sesión de planificación el propio 14 de septiembre antes de tocar el servidor), y la  
hora/persona responsable de cada entrada.

---

## 8\. Checklist de cumplimiento — Necesidades

Leyenda: 🟢 evidenciado y verificable · 🟡 evidenciado parcialmente · 🔴 sin evidencia en el PDF

### Nombres

| # | Necesidad | Estado | Nota |
| --- | --- | --- | --- |
| N1 | Nombres propios de la sede, fuente oficial | 🟢 | Zona maestra `huesca.empresa.lan` en BIND9 |
| N2 | Segundo servidor con misma información | 🟢 | `dns-secundario-1` con zonas `type slave` y `masters { 10.5.0.1; }` (apartado 4.1) |
| N3 | Solo el segundo puede pedir la lista completa | 🟢 | `allow-transfer { 10.5.0.2; }` y `also-notify { 10.5.0.2; }` en la vista del primario |
| N4 | Cambio disponible en \<1 min en el segundo | 🟢 | `dig @10.5.0.2 prueba-n4c...` devuelve `10.5.0.96` 11 s después de recargar el primario; el `SOA` tiene serial 12 en ambos |
| N5 | Nombres mínimos (`ns1`,`ns2`,`srv`,`www`,`intranet`,`git`,`db`,`correo`) | 🟢 | Todos presentes en `db.huesca.empresa.lan` |
| N6 | Dirección → nombre | 🟢 | Zona inversa `5.10.in-addr.arpa` con `PTR` |
| N7 | Un único resolutor para propios e internet | 🟢 | `dig @10.5.0.1` y `ping` desde PC1 resuelven ambos |
| N8 | No resuelve internet desde el aula | 🟢 | `nslookup` desde un PC del aula: `www`/`intranet` resuelven, `www.google.com` → `Query refused` |
| N9 | Caché en segunda consulta | 🟢 | Primera consulta a `www.google.com`: 48 ms, TTL 221; segunda: 0 ms, TTL 181 (apartado 4.1) |
| N10 | El propio servidor usa su DNS | 🟢 | `/etc/resolv.conf` apunta a `127.0.0.1` primero y `dig www.wikipedia.org` sin `@` lo atiende `127.0.0.1#53` |

### Red de la sede

| # | Necesidad | Estado | Nota |
| --- | --- | --- | --- |
| R1 | Red interna con 2º DNS + 2 clientes en GNS3 | 🟢 | `dns-secundario-1`, PC1, PC2 |
| R2 | Servidor en las dos redes, salida de la interna | 🟢 | `enp5s0` + `br-virtual`, NAT |
| R3 | Clientes llegan al aula e internet | 🟢 | `ping 192.168.6.105` y `ping 8.8.8.8` desde PC2 |
| R4 | Desde el aula, por nombre, a `www`/`intranet`/`git` usando el servidor como resolutor | 🟢 | `nslookup git.huesca.empresa.lan 192.168.6.105` + `curl -I http://git.huesca.empresa.lan:3000` → 200 OK, desde un PC del aula |
| R5 | Topología GNS3 en el repositorio, coincide con la documentación | 🟢 | No hay `.gns3project` versionado |

### Servidor

| # | Necesidad | Estado | Nota |
| --- | --- | --- | --- |
| S1 | Un usuario por persona con permisos de administración | 🟢 | `adduser` + `sudo` para 4 personas |
| S2 | Acceso cifrado, sin contraseña, sin root directo | 🟢 | `PermitRootLogin no` confirmado sin comentar, `ssh root@...` rechazado; clave de Alvaro ya desplegada en su propio usuario (falta repetirlo para el resto) |
| S3 | Todo vuelve solo tras reiniciar | 🟢 | `systemctl is-enabled` confirma `docker`/`ssh`/`gns3server`/`ufw` habilitados y, tras `sudo reboot`, `gns3server`, `ufw` y `docker` están activos (apartado 5); falta la comprobación funcional posterior (prueba 16) |
| S4 | Servicios en contenedores con Compose (nombres, web, BD, Forgejo) | 🟢 | Los cuatro migrados a Compose (BIND9 el último), y `docker ps` confirma los siete contenedores activos a la vez |

### Forgejo

| # | Necesidad | Estado | Nota |
| --- | --- | --- | --- |
| F1 | Responde en `git.<sede>` y sobrevive a destruir el contenedor | 🟢 | Responde; el contenedor se destruyó (`docker rm -f forgejo`) y se recreó, y el repositorio siguió presente en el volumen |
| F2 | Cuenta por miembro + cuenta de administración del profesorado, sin auto-registro | 🟢 | Cuenta `Profesor` como miembro de la organización (el `README` la declara como usuario del profesorado) y auto-registro deshabilitado |
| F3 | Organización con nombre de la sede, SSH en puerto distinto de 22, URL de clonado correcta | 🟢 | Organización `huesca`, puerto `2222`, clonado probado |
| F4 | Etiquetas y plantillas antes de la primera tarea | 🟢 | Tres plantillas (`ayuda.md`, `tarea.md`, `verificacion.md`) y doce etiquetas creadas |
| F5 | Copia de Forgejo restaurada y comprobada | 🟡 | `forgejo dump` + `forgejo dump restore` probados con éxito (unzip, ficheros y SQL restaurados); falta repetirlo sobre un volumen completamente nuevo |

### Web y datos

| # | Necesidad | Estado | Nota |
| --- | --- | --- | --- |
| W1 | `www` sirve la web pública con Apache | 🟢 | `curl -H "Host: www.huesca.empresa.lan"` responde 200 |
| W2 | `intranet` pide usuario/contraseña, sitio distinto | 🟢 | `AuthType Basic`, `401`/`200` comprobados |
| W3 | Página muestra versión de la BD y nº de filas | 🟢 | `index.php` con `pg_connect`, versión y `COUNT(*)` |
| W4 | PostgreSQL con tabla ≥20 filas | 🟢 | Tabla `inventario`, 20 filas |
| W5 | BD no accesible desde el aula | 🟢 | `Test-NetConnection -Port 5432` desde el aula: `TcpTestSucceeded: False` (el `ping` sí llega) |
| W6 | Copia de la BD restaurada y comprobada | 🟢 | Restaurada sobre `base_nueva` (base vacía real), sin errores de clave duplicada, `SELECT * FROM inventario` devuelve las 20 filas |
| W7 | Registros de Apache y PostgreSQL legibles y se sabe leer un error | 🟡 | Ejemplo de 404 diagnosticado en Apache; falta el mismo ejercicio con un error real de PostgreSQL |

### Seguridad y datos personales

| # | Necesidad | Estado | Nota |
| --- | --- | --- | --- |
| P1 | Política de contraseñas escrita y aplicada (servidor, Forgejo, intranet, BD) | 🟡 | `docs/POLITICA_CONTRASENAS.md` redactada y publicada; falta comprobar que los parámetros están realmente aplicados |
| P2 | Datos personales clasificados | 🟢 | `docs/CLASIFICACION_DATOS.md` con niveles PÚBLICO/RESTRINGIDO/CONFIDENCIAL y medidas de protección |
| P3 | Claves privadas no salen del equipo del dueño | 🟢 | `docs/DECLARACION_CLAVES.md` publicada, y ya hay un caso real (Alvaro) de clave desplegada solo como pública en el servidor |
| P4 | Servicios visibles desde el aula; no se entra en servicios ajenos | 🔴 | No evaluable con este documento (depende de otras sedes) |

---

## 9\. Checklist — Pruebas de aceptación (1 a 22)

| # | Prueba | Estado |
| --- | --- | --- |
| 1 | Resuelve y abre `www.huesca.empresa.lan` | 🟢 |
| 2 | Resuelve y abre `git.huesca.empresa.lan` | 🟢 |
| 3 | Resuelve un nombre de internet, segunda vez sin salir de la sede | 🟢 (48 ms → 0 ms con TTL descontado) |
| 4 | El servidor responde como fuente oficial, no intermediario | 🟢 |
| 5 | Rechaza resolver un nombre de internet desde el aula | 🟢 |
| 6 | Rechaza pedir la lista completa de nombres | 🟢 (`allow-transfer` restringido al secundario; falta probar un intento de transferencia denegado desde un tercero) |
| 7 | Con el primero parado, el segundo sigue respondiendo | 🟡 (`docker stop mi-bind9` hecho; falta el `dig @10.5.0.2` con el primario parado) |
| 8 | Nombre nuevo replicado en \<1 min | 🟢 (`prueba-n4c` responde en el secundario a los 11 s) |
| 9 | Dirección → nombre (segundo servidor y un cliente) | 🟢 |
| 10 | Quién recibe el correo → `correo` | 🟢 |
| 11 | Desde el aula, con vuestro resolutor, el profesorado abre `git` y entra | 🟢 |
| 12 | `intranet` pide credenciales, `www` no | 🟢 |
| 13 | Página de estado muestra versión de PostgreSQL y nº de filas | 🟢 |
| 14 | El puerto de la BD no responde desde el aula | 🟢 |
| \<\<\<\<\<\<\< HEAD |   |   |
| 15 | Contraseña rechazada, clave entra por miembro | 🟢 |
| 16 | Reinicio: pruebas 1-15 siguen pasando | 🟡 (reinicio hecho y servicios activos; falta repetir las pruebas 1-15 después) |
| 17 | Máquina limpia + documentación → pasan pruebas 4, 10, 12, 13 | 🟢 |
| 18 | Sin contraseñas en el historial de Git | 🟢 sin evaluar |
| \======= |   |   |
| 15 | Contraseña rechazada, clave entra por miembro | 🟢 |
| 16 | Reinicio: pruebas 1-15 siguen pasando | 🟢 |
| 17 | Máquina limpia + documentación → pasan pruebas 4, 10, 12, 13 | 🟢 |
| 18 | Sin contraseñas en el historial de Git | 🟢 sin evaluar |

> > > > > > > 0a21e5e (pruebas aceptacion)  
> > > > > > > | 19 | Confirmaciones propias + revisión de _pull request_ | 🔴 sin evaluar |  
> > > > > > > | 20 | Restaurar PostgreSQL y Forgejo desde copia, tras borrar datos | 🟡 (BD restaurada sobre base vacía sin errores; Forgejo restaurado dentro del mismo contenedor, falta sobre volumen nuevo) |  
> > > > > > > | 21 | Cuaderno con una entrada por sesión | 🟡 (apartado 7, a validar por el equipo) |  
> > > > > > > | 22 | Investigación fusionada antes de implementar cada servicio | 🔴 (investigación escrita en apartado 6, pendiente de fusionar antes de la próxima implementación) |

---

## 10\. Resumen ejecutivo de lo que falta

> Actualizado el 28 de septiembre tras incorporar las capturas nuevas: réplica medida del DNS  
> secundario, etiquetas y plantillas de Forgejo, datos de la sede en el `README` y prueba de reinicio  
> del servidor. Lo que queda es más acotado.

1.  **DNS**: solo queda la prueba 7: el `docker stop mi-bind9` ya está hecho, falta el  
    `dig @10.5.0.2 ...` con el primario parado. La réplica en \<1 min (N4, prueba 8) ya está cerrada.
2.  Fusionar por _pull request_ las siete investigaciones del apartado 6 antes de la próxima  
    implementación que toquen.
3.  Completar el `README` con la tabla de responsable + suplente por área (apartado 1) — ya tiene  
    un índice de políticas, pero no ese reparto.
4.  Abrir y cerrar incidencias reales desde confirmaciones en Forgejo: las doce etiquetas y las tres  
    plantillas ya existen (F4 cerrado, F2 cerrado), pero todas las etiquetas muestran 0 incidencias abiertas.
5.  Completar la prueba de reinicio (prueba 16 — el `sudo reboot` y la vuelta de `gns3server`, `ufw`  
    y `docker` ya están capturados; falta un `docker ps` completo y repetir las pruebas 1-15 después) y repetir la restauración de Forgejo y de PostgreSQL  
    sobre un volumen/contenedor **completamente nuevo** (pruebas 20, F5 — la de PostgreSQL sobre  
    base vacía ya se ha probado con éxito, W6 cerrado).
6.  Repetir el despliegue de clave SSH individual (ya hecho para Alvaro) con el resto del equipo  
    (Jaime, Andreas, Diego), y dejar de depender del usuario compartido `asir2` para el acceso del  
    día a día.
7.  Exportar y versionar la topología de GNS3 (R5).
8.  Decidir y corregir el `ROOT_URL` de Forgejo (incidencia del 19 de septiembre).
9.  Instalación de Ubuntu Server (apartado 3.0) — sigue sin ninguna captura de este paso.
10.  Comprobar en la práctica los parámetros de `POLITICA_CONTRASENAS.md` (P1) con un intento real  
    de contraseña débil rechazado, y un ejemplo de diagnóstico de un error real en los logs de  
    PostgreSQL (W7).

**Resuelto en esta revisión:** N4, N9, N10, F2, F4 (checklist §8); pruebas 3 y 8 del checklist §9; y  
avance parcial en las pruebas 7 y 16.

**Resuelto en la revisión anterior:** N2, N3, N8, W5, W6, S2, F1 (checklist §8); pruebas 5, 6, 14 del  
checklist §9; y P2, P3 (política de contraseñas P1 redactada pero pendiente de comprobar  
aplicación).  
PostgreSQL (W7).

**Resuelto en esta revisión:** N2, N3, N8, W5, W6, S2, F1 (checklist §8); pruebas 5, 6, 14 del  
checklist §9; y P2, P3 (política de contraseñas P1 redactada pero pendiente de comprobar  
aplicación).