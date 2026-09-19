#!/usr/bin/env bash
# One-time privileged setup for the Internet Hotspot plugin.
# Installs the backend CLI + a polkit policy so the bar widget can
# start/stop the hotspot with a proper auth prompt (no terminal needed).
#
# Security model: root never opens a file from this (user-writable) checkout.
# Each file is read ONCE, into memory, before sudo is invoked. Those exact
# bytes are handed to a single `sudo` command, and the root-side code
#   1. writes them into a fresh root-only (0700) staging directory,
#   2. checks them against the SHA-256 pinned below (the pin travels in the
#      sudo command line, so it cannot change once sudo has started), and
#   3. installs from that staging directory, atomically, as root:root.
# So replacing bin/share-internet or the policy while the sudo password prompt
# is open has no effect on what gets installed.
#
# Changing bin/share-internet or the .policy file? Update the pins below:
#   sha256sum bin/share-internet io.github.imargorsi.hotspot.policy
set -euo pipefail

HELPER_SHA256="fb8bc9a5e37ffdec17027a7899fbd9318da0c65e072aba5f8ef12bde291ff677"
POLICY_SHA256="38f29279d351244eab33f40f2fc7750f1d80bd8a030e32ad77547f104dba5f14"

# Runs as root. Receives everything as arguments: it must not read anything
# owned by, or writable by, an unprivileged user.
# $1/$2 = helper (base64, expected sha256)   $3/$4 = polkit policy (same)
IFS= read -r -d '' ROOT_INSTALLER <<'ROOT_EOF' || true
set -euo pipefail
umask 022
export PATH=/usr/bin:/bin

helper_dst=/usr/local/bin/share-internet
policy_dst=/usr/share/polkit-1/actions/io.github.imargorsi.hotspot.policy
status_file=/run/share-internet-status.json

[[ $# -eq 4 ]] || { echo "install: bad arguments" >&2; exit 1; }

# mktemp -d creates the directory 0700 and owned by root, in a root-owned parent.
stage=$(mktemp -d /run/share-internet-install.XXXXXX)
trap 'rm -rf -- "$stage"' EXIT

verify() {  # verify <base64> <expected-sha256> <stage-file>
    printf '%s' "$1" | base64 -d > "$3"
    local actual
    actual=$(sha256sum < "$3")
    actual=${actual%% *}
    if [[ "$actual" != "$2" ]]; then
        echo "install: checksum mismatch for $(basename -- "$3"): expected $2, got $actual" >&2
        exit 1
    fi
}

verify "$1" "$2" "$stage/helper"
verify "$3" "$4" "$stage/policy"

# Install each file next to its destination, then rename over it, so a reader
# (or a failure half way) never sees a partial file.
put() {  # put <mode> <staged-file> <destination>
    local tmp
    install -d -m 755 -o root -g root -- "$(dirname -- "$3")"
    tmp=$(mktemp "$(dirname -- "$3")/.install.XXXXXX")
    install -m "$1" -o root -g root -- "$2" "$tmp"
    mv -f -- "$tmp" "$3"
}

put 755 "$stage/helper" "$helper_dst"
put 644 "$stage/policy" "$policy_dst"

# Older versions put the Wi-Fi password in this world-readable snapshot;
# drop any leftover copy (the helper recreates it, without the password).
rm -f -- "$status_file"
ROOT_EOF

main() {
    if [[ $EUID -eq 0 ]]; then
        echo "Run this as your normal user (it asks for sudo itself)." >&2
        exit 1
    fi

    local dir helper_file policy_file
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    helper_file="$dir/bin/share-internet"
    policy_file="$dir/io.github.imargorsi.hotspot.policy"

    echo "This will install (as root, from a verified in-memory copy):"
    echo "  - bin/share-internet -> /usr/local/bin/share-internet"
    echo "  - io.github.imargorsi.hotspot.policy -> /usr/share/polkit-1/actions/"
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

    # Snapshot: each file is read exactly once. Everything below (the check
    # here, and what root installs) works on these copies, never on the paths.
    local helper_b64 policy_b64
    helper_b64=$(base64 -w0 < "$helper_file")
    policy_b64=$(base64 -w0 < "$policy_file")

    # Fail early, with a readable message, if the files aren't the pinned ones.
    # (Root repeats this check on the same bytes; this one is only for UX.)
    local got
    got=$(base64 -d <<<"$helper_b64" | sha256sum); got=${got%% *}
    if [[ "$got" != "$HELPER_SHA256" ]]; then
        echo "bin/share-internet does not match the checksum pinned in install.sh." >&2
        echo "  pinned:  $HELPER_SHA256" >&2
        echo "  actual:  $got" >&2
        echo "Refusing to install. If you edited it on purpose, update HELPER_SHA256." >&2
        exit 1
    fi
    got=$(base64 -d <<<"$policy_b64" | sha256sum); got=${got%% *}
    if [[ "$got" != "$POLICY_SHA256" ]]; then
        echo "The polkit policy does not match the checksum pinned in install.sh." >&2
        echo "  pinned:  $POLICY_SHA256" >&2
        echo "  actual:  $got" >&2
        echo "Refusing to install. If you edited it on purpose, update POLICY_SHA256." >&2
        exit 1
    fi
    echo "Verified: share-internet   sha256 $HELPER_SHA256"
    echo "Verified: polkit policy    sha256 $POLICY_SHA256"
    echo

    # One privileged call, so there is a single auth prompt and nothing else
    # for root to open. `--` stops sudo parsing our arguments as options.
    sudo -- /bin/bash -c "$ROOT_INSTALLER" share-internet-install \
        "$helper_b64" "$HELPER_SHA256" "$policy_b64" "$POLICY_SHA256"

    echo
    echo "Done. Reload the plugin (omarchy-shell shell rescanPlugins, or just"
    echo "reopen the bar widget) — it should now show as installed."
}

# `main` and `exit` share one line, so bash has read the last command it will
# ever read from this file before main starts: editing install.sh while it
# runs can't change what this process does next.
main "$@"; exit
