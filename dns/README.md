# dns/ · SRI

BIND: configuración, zonas directa e inversa, primario y secundario.

# Servidor DNS - Sede Huesca (`huesca.empresa.lan`)

Este directorio contiene la configuración y los ficheros de zona para el servidor DNS basado en **BIND9** dentro de un contenedor Docker (`mi-bind9`), correspondiente a la Sede Huesca.

---

## 📁 Estructura de la carpeta `dns/`

Para que el servidor DNS arranque en un solo comando, la carpeta `dns/` debe contener los siguientes archivos:

- `named.conf.options`: Opciones generales de BIND9 (reenviadores DNS y permisos de consulta).
- `named.conf.local`: Declaración de la zona directa (`huesca.empresa.lan`) y la zona inversa (`0.5.10.in-addr.arpa`).
- `db.huesca.empresa.lan`: Fichero de la zona directa con los registros A y CNAME.
- `db.10.5.0`: Fichero de la zona inversa para la red local.

---

## 🚀 Arranque del Servidor en un solo comando

Para levantar el servicio DNS con toda la configuración cargada directamente desde las carpetas locales, ejecuta desde la raíz del repositorio:

```bash
sudo ./instalar.sh dns
```
