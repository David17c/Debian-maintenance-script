#!/usr/bin/env bash

set -Eeuo pipefail

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
NC="\e[0m"

trap 'echo -e "${RED}Error: command failed on line $LINENO.${NC}" >&2' ERR

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Please run this script as root.${NC}" >&2
    exit 1
fi

# Check for internet connection
if ! getent hosts deb.debian.org >/dev/null 2>&1; then
    echo -e "${RED}No internet connection or cannot resolve repositories.${NC}" >&2
    exit 1
fi

echo -e "${GREEN}Starting system maintenance...${NC}"

# Store initial available disk space in KB
before_space=$(df --output=avail / | tail -1)

# System Updates and apt cleanup
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -y full-upgrade
apt-get -y autoremove --purge
apt-get -y autoclean
apt-get clean

# Remove leftover package configurations
dpkg -l | awk '/^rc/ {print $2}' | xargs -r apt-get -y purge

# Snap update (if installed)
if command -v snap >/dev/null 2>&1; then
    snap refresh
fi

# Update Flatpaks and clean up unused runtimes
if command -v flatpak >/dev/null 2>&1; then
    flatpak update -y
    flatpak uninstall --unused -y
fi

# Remove logs older than 14 days
journalctl --vacuum-time=14d

# Empty trash for all users
for home in /home/* /root; do
    trash="$home/.local/share/Trash"
    if [[ -d "$trash" ]]; then
        rm -rf "${trash:?}/files"/* "${trash:?}/info"/* 2>/dev/null || true
    fi
done

# Calculate and print disk space change
after_space=$(df --output=avail / | tail -1)
diff_mb=$(( (after_space - before_space) / 1024 ))

if (( diff_mb > 0 )); then
    echo -e "${GREEN}Maintenance complete! Freed approximately ${diff_mb} MB of disk space.${NC}"
elif (( diff_mb < 0 )); then
    echo -e "${YELLOW}Maintenance complete. Disk usage increased by approximately $((-diff_mb)) MB (likely due to package updates).${NC}"
else
    echo -e "${GREEN}Maintenance complete! No significant change in disk space.${NC}"
fi

# Notify if reboot is needed
if [[ -f /var/run/reboot-required ]]; then
    echo -e "${YELLOW}A system reboot is required.${NC}"
fi

exit 0