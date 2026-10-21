# sistema/ · ASO

Usuarios del servidor y acceso por SSH.

- `usuarios/<nombre>.pub`: una clave pública por persona que entra al servidor, profesorado incluido.
- La configuración de `sshd` que cambiéis, como fichero.

# Módulo de Sistema y Usuarios - Sede Huesca

Contiene el despliegue del cortafuegos UFW, la red de Docker, el servicio Forgejo y las claves públicas SSH del equipo y del profesorado.

## 📁 Estructura
- `config_red_ufw.sh`: Script de configuración de red y UFW.
- `usuarios/<nombre>.pub`: Clave pública SSH de cada persona que accede al servidor (profesorado incluido).
- `usuarios/sshd_seguridad.conf`: Fichero de configuración de `sshd` para deshabilitar acceso por contraseña.
- `usuarios/crear_usuario.sh`: Script para dar de alta usuarios leyendo los ficheros `.pub`.

## 🚀 Despliegue
```bash
chmod +x config_red_ufw.sh usuarios/crear_usuario.sh
./config_red_ufw.sh
cd usuarios && ./crear_usuario.sh
sudo cp sshd_seguridad.conf /etc/ssh/sshd_config.d/seguridad.conf
sudo systemctl restart ssh
