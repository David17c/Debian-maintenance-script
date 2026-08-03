#!/usr/bin/env bash

set -Eeuo pipefail

trap 'echo "Error: command failed on line $LINENO." >&2' ERR

if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root." >&2
    exit 1
fi

if ! getent hosts deb.debian.org >/dev/null 2>&1; then
    echo "No internet connection or cannot resolve repositories." >&2
    exit 1
fi

before_space=$(df --output=avail / | tail -1 | tr -d ' ')

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y full-upgrade
apt-get -y autoremove --purge
apt-get -y autoclean

dpkg -l | awk '/^rc/ {print $2}' | xargs -r apt-get -y -qq purge

if command -v snap >/dev/null 2>&1; then
    snap refresh
fi

if command -v flatpak >/dev/null 2>&1; then
    flatpak update -y --noninteractive
    flatpak uninstall --unused -y --noninteractive
fi

if command -v docker >/dev/null 2>&1; then
    docker system prune -af --volumes >/dev/null 2>&1
fi

if command -v podman >/dev/null 2>&1; then
    podman system prune -a --force >/dev/null 2>&1
fi

journalctl --vacuum-time=14d

find /tmp -type f -atime +7 -delete 2>/dev/null || true

shopt -s nullglob

for home in /home/* /root; do
    trash="$home/.local/share/Trash"

    if [[ -d "$trash" ]]; then
        rm -rf "${trash:?}/files"/* "${trash:?}/info"/* 2>/dev/null || true
    fi

    rm -rf "$home/.cache/thumbnails/"* 2>/dev/null || true
done

shopt -u nullglob

after_space=$(df --output=avail / | tail -1 | tr -d ' ')
diff_mb=$(((after_space - before_space) / 1024))

if (( diff_mb > 0 )); then
    echo "Freed approximately ${diff_mb} MB."
elif (( diff_mb < 0 )); then
    echo "Disk usage increased by approximately $((-diff_mb)) MB."
else
    echo "No significant disk space change."
fi

[[ -f /var/run/reboot-required ]] && echo "Reboot required."

exit 0