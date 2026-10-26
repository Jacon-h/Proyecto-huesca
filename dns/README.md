# dns/ · SRI

Servidor DNS de la sede (`huesca.empresa.lan`): BIND9 en el contenedor `mi-bind9`, con **dos vistas** y un secundario.

## Cómo se instala

```bash
sudo ./instalar.sh dns
```

La fase `dns` hace esto, en orden:

1. Libera el puerto 53 si lo ocupa `systemd-resolved`.
2. Genera la configuración en `generado/dns/` a partir de las plantillas `*.tpl` y de `sede.env` (no va en Git).
3. La **valida** con `named-checkconf -z`. Si falla, aborta sin tocar el DNS que ya estaba funcionando.
4. Recrea el contenedor `mi-bind9` con esa configuración montada en `/etc/bind`.

Cada ejecución sube el *serial* de las zonas, así el secundario se entera siempre de los cambios.

## Qué hay en la carpeta

| Fichero | Para qué |
|---|---|
| `named.conf`, `named.conf.options` | Fijos. Recursión desactivada por defecto y `allow-transfer { none; }`. |
| `named.conf.local.tpl` | ACL y las dos vistas (`interna` y `aula`) con sus zonas. |
| `interna/db.directa.tpl` | Zona directa para la red interna (todo apunta a `IP_INTERNA`). |
| `interna/db.inversa.tpl` | Zona inversa (`2.10.in-addr.arpa`) para la red interna. |
| `aula/db.directa.tpl` | Zona directa para el aula (todo apunta a `IP_AULA`). |
| `secundario/named.conf.local.tpl` | Zonas `slave` para el DNS secundario (nodo de GNS3). |

## Las dos vistas

| Vista | Quién la ve | Qué responde |
|---|---|---|
| `interna` | `RED_INTERNA` y el propio servidor (127.0.0.1) | Las IP internas, con recursión (reenvía a 8.8.8.8 y 1.1.1.1) y transferencia al secundario. |
| `aula` | Las redes de `REDES_AULA` | Las IP del aula, **sin recursión** y sin transferencias. |

## Datos que salen de `sede.env`

`DOMINIO`, `IP_INTERNA`, `RED_INTERNA`, `IP_AULA`, `REDES_AULA`, `IP_DNS_SECUNDARIO`.
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

La fase `verificar` ya comprueba las dos primeras.

## Secundario (`dns-secundario-1`, 10.2.0.2)

Vive en GNS3, no en este servidor. Su IP la fija el proyecto (`gns3/`) y tiene que coincidir con `IP_DNS_SECUNDARIO`.
La fase `dns` genera `generado/dns-secundario/named.conf.local` con las zonas `slave` y el primario como `masters`.
Se carga dentro del contenedor (consola del nodo en GNS3, o copiándolo con `docker cp`) en `/etc/bind/named.conf.local`
y se reinicia BIND allí. Después, desde el servidor: `dig +short @10.2.0.2 www.huesca.empresa.lan`.
