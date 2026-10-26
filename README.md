# gns3/ · SRI

Proyecto de GNS3 de la red interna y la configuración de sus nodos.

Plantilla: borrad esta línea y explicad cómo se abre el proyecto y qué hay que tener antes.
# gns3/ · SRI

Proyecto de GNS3 de la red interna de la sede Huesca (`red_huesca.gns3project`) y la configuración de sus nodos.

## Instalación automática

No hay que hacer nada a mano: `sudo ./instalar.sh` ejecuta la fase `gns3` (después de `red` y `dns`, antes de `web`).
También se puede lanzar sola con `sudo ./instalar.sh gns3`; se puede repetir sin romper nada. Qué hace:

1. Crea el usuario de sistema `gns3` (grupos `docker`, `kvm` y `ubridge` si existen).
2. Instala `gns3-server`, `ubridge`, `dynamips` y `vpcs` desde el PPA oficial (`ppa:gns3/ppa`).
   Si el PPA no sirve para esta versión de Ubuntu, instala `gns3-server` 2.2.61 con `pip` y compila `ubridge` y `vpcs`
   del código oficial. El detalle queda en `/var/log/instalar-gns3.log`.
3. Da a `ubridge` las capacidades de red (`setcap cap_net_admin,cap_net_raw=ep`).
4. Construye la imagen Docker `dns-secundario:1.0` (`gns3/dns-secundario/`) con las zonas `slave` que genera la fase `dns`.
5. Crea y arranca la unidad `gns3server` (systemd): escucha en `0.0.0.0:3080`, arranca después de Docker y se activa en cada arranque.
   Abre en UFW el puerto 3080 **solo** para las redes de Docker (Apache llega a GNS3 por ahí).
6. Importa `red_huesca.gns3project` por la API, lo marca para abrirse y arrancar los nodos con el servidor
   (`auto_open` y `auto_start`, así sobrevive a un reinicio), lo abre y arranca todos los nodos.

Dónde se ve: `http://gns3.huesca.empresa.lan` (por Apache) o `http://IP_DEL_SERVIDOR:3080` (en el servidor).
La fase `verificar` comprueba que el servidor responde, que Apache lo alcanza y que todos los nodos están arrancados.

Requisitos que ya cubre `instalar.sh`: el puente `br-virtual` (fase `red`), que es al que se conecta Cloud1, y Docker.
Sin `br-virtual` el servidor GNS3 se instala igual, pero Cloud1 no arranca: ejecuta `sudo ./instalar.sh red` y después `sudo ./instalar.sh gns3`.

## Topología

```
Cloud1 (br-virtual) ── Switch1 ─┬─ PC1
                                ├─ PC2
                                └─ dns-secundario-1
```

| Nodo | Tipo | Dirección | Puerto de Switch1 |
|---|---|---|---|
| Cloud1 | Cloud → `br-virtual` | 10.2.0.1 (el servidor) | Ethernet0 |
| PC2 | VPCS | 10.2.0.21/24, puerta 10.2.0.1, DNS 10.2.0.1 | Ethernet1 |
| PC1 | VPCS | 10.2.0.20/24, puerta 10.2.0.1, DNS 10.2.0.1 | Ethernet2 |
| dns-secundario-1 | Docker `dns-secundario:1.0` | 10.2.0.2/24, puerta 10.2.0.1, DNS 10.2.0.1 | Ethernet3 |

Los datos de red coinciden con `sede.env` (`RED_INTERNA=10.2.0.0/24`, `IP_INTERNA=10.2.0.1/24`).
La configuración de los PC está en `project-files/vpcs/*/startup.vpc` y la del secundario en
`project-files/docker/<id>/etc/network/interfaces`, dentro del proyecto.

El BIND del secundario (zonas `slave`) se carga con el fichero que genera `sudo ./instalar.sh dns` en
`generado/dns-secundario/named.conf.local`; ver `dns/README.md`.

## Pruebas

Desde la consola de PC1 o PC2:

```
ping 10.2.0.1        # llega al servidor
ping 8.8.8.8         # sale por el NAT de la fase red
ping google.com      # resuelve con el DNS
```

## Si no responde

- `ip -br addr show br-virtual` en el servidor: debe tener `10.2.0.1/24` y estar `UP`.
- `sudo iptables -S DOCKER-USER`: deben estar las reglas de la fase `red`.
- Comprobad que los nodos están arrancados y que el enlace Cloud1 → Switch1 es verde.