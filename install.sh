#!/usr/bin/env bash
# One-time privileged setup for the Internet Hotspot plugin.
# Installs the backend CLI + a polkit policy so the bar widget can
# start/stop the hotspot with a proper auth prompt (no terminal needed).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "This will install:"
echo "  - $DIR/bin/share-internet -> /usr/local/bin/share-internet"
echo "  - $DIR/io.github.imargorsi.hotspot.policy -> /usr/share/polkit-1/actions/"
echo

if ! command -v dnsmasq >/dev/null 2>&1; then
    echo "dnsmasq is required (NetworkManager's optional dependency for Wi-Fi"
    echo "hotspot sharing) and is not installed."
    read -r -p "Install it now with pacman? [y/N] " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        sudo pacman -S --needed dnsmasq
    else
        echo "Skipping. The hotspot will fail to start without it." >&2
    fi
fi

sudo install -m 755 "$DIR/bin/share-internet" /usr/local/bin/share-internet
sudo install -m 644 "$DIR/io.github.imargorsi.hotspot.policy" \
    /usr/share/polkit-1/actions/io.github.imargorsi.hotspot.policy
# Older versions put the Wi-Fi password in this world-readable snapshot;
# drop any leftover copy (the helper recreates it, without the password).
sudo rm -f /run/share-internet-status.json

echo
echo "Done. Reload the plugin (omarchy-shell shell rescanPlugins, or just"
echo "reopen the bar widget) — it should now show as installed."
