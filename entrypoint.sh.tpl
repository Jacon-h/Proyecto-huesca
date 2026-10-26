#!/bin/bash
# Arranque del DNS secundario. Los valores salen de sede.env (instalar.sh gns3 los sustituye).
# GNS3 ya pone la IP con /etc/network/interfaces; estas líneas son por si no lo hiciera
# (si ya está puesta, "ip" protesta y se ignora).
ip link set eth0 up                                    2>/dev/null || true
ip addr add ${IP_DNS_SECUNDARIO}/${PREFIJO_INTERNA} dev eth0 2>/dev/null || true
ip route add default via ${IP_INTERNA_SOLO}            2>/dev/null || true

mkdir -p /run/named /var/cache/bind
chown bind:bind /run/named /var/cache/bind
exec named -g -u bind
