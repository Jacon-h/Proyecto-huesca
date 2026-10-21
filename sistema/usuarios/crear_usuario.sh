#!/bin/bash
DIR_USUARIOS=$(dirname "$0")

for ARCHIVO_PUB in "$DIR_USUARIOS"/*.pub; do
    [ -e "$ARCHIVO_PUB" ] || continue
    USUARIO=$(basename "$ARCHIVO_PUB" .pub)
    CLAVE_SSH=$(cat "$ARCHIVO_PUB")

    echo "Procesando: $USUARIO"
    if ! id "$USUARIO" &>/dev/null; then
        sudo useradd -m -s /bin/bash "$USUARIO"
        sudo usermod -aG sudo "$USUARIO"
    fi

    DIR_SSH="/home/$USUARIO/.ssh"
    sudo mkdir -p "$DIR_SSH"
    echo "$CLAVE_SSH" | sudo tee "$DIR_SSH/authorized_keys" > /dev/null
    sudo chmod 700 "$DIR_SSH"
    sudo chmod 600 "$DIR_SSH/authorized_keys"
    sudo chown -R "$USUARIO:$USUARIO" "$DIR_SSH"
done