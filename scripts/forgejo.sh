# shellcheck shell=bash
# scripts/forgejo.sh · Fase "forgejo": restaura los datos de otro Forgejo y activa su SSH.
# No se ejecuta solo: lo carga instalar.sh.
#   sudo ./instalar.sh forgejo
FORGEJO_DATOS=forgejo-docker
FORGEJO_DUMP=restauracion/forgejo-dump.zip
FORGEJO_SSH_ORIGEN=restauracion/forgejo-ssh
FORGEJO_UID=1000

forgejo_entorno() {
    export DOMINIO
    if [ -f "$FORGEJO_DATOS/gitea/gitea.db" ]; then 
        FORGEJO_INSTALL_LOCK=true
    else 
        FORGEJO_INSTALL_LOCK=false
    fi
    export FORGEJO_INSTALL_LOCK
}

forgejo_restaurar() {
    if [ -f "$FORGEJO_DUMP" ]; then
        local num_usuarios=0
        if [ -f "$FORGEJO_DATOS/gitea/gitea.db" ]; then
            num_usuarios=$(sqlite3 "$FORGEJO_DATOS/gitea/gitea.db" "SELECT COUNT(*) FROM user;" 2>/dev/null || echo 0)
        fi

        if [ "$num_usuarios" -eq 0 ]; then
            echo "     Base de datos vacía o no existente. Restaurando desde $FORGEJO_DUMP..."
            apt-get install -y unzip sqlite3 >/dev/null 2>&1 || true
            docker rm -f forgejo 2>/dev/null || true

            local tmp; tmp=$(mktemp -d)
            unzip -q "$FORGEJO_DUMP" -d "$tmp"

            mkdir -p "$FORGEJO_DATOS/gitea/conf" "$FORGEJO_DATOS/git/repositories"
            if [ -f "$tmp/app.ini" ]; then cp "$tmp/app.ini" "$FORGEJO_DATOS/gitea/conf/app.ini"; fi
            if [ -d "$tmp/data" ];  then cp -a "$tmp/data/."  "$FORGEJO_DATOS/gitea/"; fi
            if [ -d "$tmp/repos" ]; then cp -a "$tmp/repos/." "$FORGEJO_DATOS/git/repositories/"; fi

            local sql; sql=$(ls "$tmp"/*-db.sql 2>/dev/null | head -1 || true)
            if [ -n "$sql" ]; then
                rm -f "$FORGEJO_DATOS/gitea/gitea.db"
                sqlite3 "$FORGEJO_DATOS/gitea/gitea.db" < "$sql"
            fi
            rm -rf "$tmp"

            if [ -f "$FORGEJO_DATOS/gitea/conf/app.ini" ]; then
                if grep -q "INSTALL_LOCK" "$FORGEJO_DATOS/gitea/conf/app.ini"; then
                    sed -i 's/INSTALL_LOCK.*/INSTALL_LOCK = true/' "$FORGEJO_DATOS/gitea/conf/app.ini"
                else
                    echo -e "\n[security]\nINSTALL_LOCK = true" >> "$FORGEJO_DATOS/gitea/conf/app.ini"
                fi
            fi

            chown -R "$FORGEJO_UID:$FORGEJO_UID" "$FORGEJO_DATOS"
            echo "     Datos de Forgejo restaurados correctamente."
        else
            echo "     Forgejo ya cuenta con usuarios en la BBDD: omitiendo restauración."
        fi
    fi
}

forgejo_ssh_preparar() {
    mkdir -p "$FORGEJO_DATOS/ssh" "$FORGEJO_DATOS/git/.ssh"
    if [ -d "$FORGEJO_SSH_ORIGEN" ] && ! ls "$FORGEJO_DATOS"/ssh/ssh_host_*_key &>/dev/null; then
        cp -a "$FORGEJO_SSH_ORIGEN"/ssh_host_* "$FORGEJO_DATOS/ssh/"
    fi
    chown -R "$FORGEJO_UID:$FORGEJO_UID" "$FORGEJO_DATOS"
    chmod 755 "$FORGEJO_DATOS/git"
    chmod 700 "$FORGEJO_DATOS/git/.ssh"
    [ ! -f "$FORGEJO_DATOS/git/.ssh/authorized_keys" ] || chmod 600 "$FORGEJO_DATOS/git/.ssh/authorized_keys"
    chmod 600 "$FORGEJO_DATOS"/ssh/ssh_host_*_key 2>/dev/null || true
    chmod 644 "$FORGEJO_DATOS"/ssh/ssh_host_*_key.pub 2>/dev/null || true
}

forgejo_ssh_activar() {
    docker compose up -d git
    for _ in $(seq 1 60); do
        curl -fs http://127.0.0.1:3000/api/healthz >/dev/null 2>&1 && break
        sleep 1
    done
    docker exec -u "$FORGEJO_UID" forgejo forgejo admin regenerate hooks \
        || echo "AVISO: no he podido regenerar los hooks de Forgejo"
    docker exec -u "$FORGEJO_UID" forgejo forgejo admin regenerate keys \
        || echo "AVISO: no he podido regenerar authorized_keys: el SSH de Forgejo no funcionará"
}

forgejo() {
    echo "== Forgejo (datos de otro Forgejo y SSH)"
    forgejo_restaurar
    forgejo_ssh_preparar
    forgejo_entorno
    if [ -f "$FORGEJO_DATOS/gitea/gitea.db" ]; then forgejo_ssh_activar; fi
}
