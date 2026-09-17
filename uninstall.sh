#!/usr/bin/env bash
# Removes everything install.sh set up (but leaves this plugin folder and
# dnsmasq alone — remove dnsmasq yourself with `sudo pacman -R dnsmasq` if
# you don't want it).
set -euo pipefail

if [[ -x /usr/local/bin/share-internet ]]; then
    /usr/local/bin/share-internet stop || true
fi

sudo rm -f /usr/local/bin/share-internet
sudo rm -f /usr/share/polkit-1/actions/io.github.imargorsi.hotspot.policy
sudo rm -rf /etc/share-internet
sudo rm -f /run/share-internet-status.json

echo "Backend removed. Remove ~/.config/omarchy/plugins/io.github.imargorsi.hotspot to remove the plugin itself."
