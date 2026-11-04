# dns/ · SRI

Servidor DNS de la sede (`huesca.empresa.lan`): BIND9 en el contenedor `mi-bind9`, con **dos vistas** y un secundario.

## Cómo se instala

```bash
sudo ./instalar.sh dns
```

La fase `dns` hace esto, en orden:

1. Libera el puerto 53 si lo ocupa `systemd-resolved`.
2. Genera la configuración en `generado/dns/` a partir de las plantillas `*.tpl` y de `sede.env` (no va en Git) y crea, una sola vez, la clave TSIG de las transferencias (`generado/tsig.conf`).
3. La **valida** con `named-checkconf -z`. Si falla, aborta sin tocar el DNS que ya estaba funcionando.
4. Recrea el contenedor `mi-bind9` con esa configuración montada en `/etc/bind`.

Cada ejecución sube el *serial* de las zonas, así el secundario se entera siempre de los cambios.

## Qué hay en la carpeta

| Fichero | Para qué |
|---|---|
| `named.conf`, `named.conf.options` | Fijos. `named.conf` carga la clave TSIG; las opciones dejan la recursión desactivada por defecto y `allow-transfer { none; }`. |
| `named.conf.local.tpl` | ACL y las dos vistas (`interna` y `aula`) con sus zonas. |
| `interna/db.directa.tpl` | Zona directa para la red interna (todo apunta a `IP_INTERNA`). |
| `interna/db.inversa.tpl` | Zona inversa (`2.10.in-addr.arpa`) para la red interna. |
| `aula/db.directa.tpl` | Zona directa para el aula (todo apunta a `IP_AULA`). |
| `secundario/named.conf.local.tpl` | Zonas `slave` para el DNS secundario (nodo de GNS3). |

## Las dos vistas

| Vista | Quién la ve | Qué responde |
|---|---|---|
| `interna` | `RED_INTERNA` y el propio servidor (127.0.0.1) | Las IP internas, con recursión (reenvía a 8.8.8.8 y 1.1.1.1) y transferencia solo a quien firme con la clave TSIG. |
| `aula` | Las redes de `REDES_AULA` | Las IP del aula, **con recursión** (también resuelve nombres externos; reenvía a 8.8.8.8 y 1.1.1.1) y sin transferencias. |

## De dónde sale cada variable de las plantillas

El DNS no usa `.env` (ahí solo van los secretos de la base de datos y la intranet). Todo sale de `sede.env`:

| Variable en las plantillas | Origen |
|---|---|
| `DOMINIO`, `RED_INTERNA`, `IP_DNS_SECUNDARIO` | Directamente de `sede.env` |
| `IP_INTERNA_SOLO` | `IP_INTERNA` sin la máscara |
| `IP_AULA_SOLO` | `IP_AULA` sin la máscara |
| `ACL_AULA` | `REDES_AULA` convertido en lista de BIND |
| `ZONA_INVERSA`, `PTR_SERVIDOR` | Calculadas desde `RED_INTERNA` e `IP_INTERNA` |
| `SERIAL` | Fecha y hora; sube en cada instalación |

Para otra sede o máquina se cambia solo `sede.env`; las plantillas no se tocan.

> La zona inversa se calcula como `/16` (`<b>.<a>.in-addr.arpa`, aquí `2.10.in-addr.arpa`) a partir de `RED_INTERNA`.
> El secundario tiene que cargar esa misma zona como `slave`.

## Pruebas rápidas

```bash
dig +short @127.0.0.1 www.huesca.empresa.lan                  # vista interna  -> 10.2.0.1
dig +short -b 192.168.6.105 @192.168.6.105 www.huesca.empresa.lan   # vista aula -> 192.168.6.105
dig +short -x 10.2.0.1 @127.0.0.1                             # inversa
dig +short @10.2.0.2 www.huesca.empresa.lan                   # secundario
```

La fase `verificar` ya comprueba estas, la recursión del aula y la transferencia con y sin clave TSIG.

## Transferencias firmadas con TSIG

Solo recibe la zona quien demuestre que tiene la clave `clave-transferencia` (HMAC-SHA256):

- La crea `instalar.sh dns` la primera vez y la guarda en `generado/tsig.conf` (carpeta con permisos `700`, fuera de Git).
  No se vuelve a crear: si cambiara, el secundario dejaría de recibir las zonas.
- El primario la carga desde `named.conf` y la exige en `allow-transfer { key clave-transferencia; }`.
- El secundario la lleva dentro de su imagen (`gns3/dns-secundario/Dockerfile`) y la usa en `masters { 10.2.0.1 key clave-transferencia; }`.

```bash
dig @127.0.0.1 AXFR huesca.empresa.lan                                # sin clave -> ; Transfer failed.
dig @127.0.0.1 AXFR huesca.empresa.lan -k generado/dns/tsig.conf      # con clave -> ;; XFR size: N records
```

## Secundario (`dns-secundario-1`, 10.2.0.2)

Vive en GNS3, no en este servidor. Su IP la fija el proyecto (`gns3/`) y tiene que coincidir con `IP_DNS_SECUNDARIO`.
La fase `gns3` construye su imagen `dns-secundario:1.0` con las zonas `slave` (`generado/dns-secundario/named.conf.local`)
y la clave TSIG, y si la imagen cambia vuelve a crear el proyecto para que el nodo use la nueva.
Después, desde el servidor: `dig +short @10.2.0.2 www.huesca.empresa.lan`.
