# Internet Hotspot — Omarchy plugin

<img src="preview.png" alt="The Internet Hotspot panel open in the Omarchy bar, showing the running toggle, SSID/password fields, and a connected device" width="720">

Turns your laptop into a Wi-Fi hotspot that shares its Ethernet internet
connection, from a bar widget. No terminal needed after install.

## Requirements

- Omarchy 4.0+ (Quickshell-based shell plugin system)
- NetworkManager with a Wi-Fi adapter that supports AP mode (most laptops)
- UFW as the active firewall (Omarchy's default)
- `dnsmasq` — NetworkManager's own optional dependency for Wi-Fi hotspot
  sharing; `install.sh` offers to install it via `pacman` if missing
- `polkit` (already part of Omarchy) — used for the GUI's auth prompt

## Install

1. Clone this repo into `~/.config/omarchy/plugins/`:
   ```bash
   omarchy plugin add https://github.com/imargorsi/omarchy-hotspot.git
   ```
   (or `git clone https://github.com/imargorsi/omarchy-hotspot ~/.config/omarchy/plugins/io.github.imargorsi.hotspot`)
2. **Required one-time setup** — the widget cannot start/stop the hotspot
   until this runs; it installs the backend CLI to `/usr/local/bin/` and a
   polkit policy so the GUI can prompt for auth like a normal desktop app
   instead of needing a terminal:
   ```bash
   ~/.config/omarchy/plugins/io.github.imargorsi.hotspot/install.sh
   ```
3. Add the widget to your bar (`omarchy bar put io.github.imargorsi.hotspot`,
   or edit `~/.config/omarchy/shell.json` — see Omarchy's plugin docs), then
   reload plugins: `omarchy-shell shell rescanPlugins`.

## Using it

- Click the Wi-Fi icon in the bar to open the panel.
- Toggle switch starts/stops the hotspot. First click of a session prompts
  for your password (a normal polkit dialog); further clicks for a while
  are not re-prompted (cached).
- Edit the SSID/password fields and hit **Save** — applies immediately if
  the hotspot is already running.
- Connected devices (hostname/IP/MAC) show live while the panel is open.

## How it works / architecture

- `bin/share-internet` — the actual logic (bash): detects your Ethernet +
  Wi-Fi interfaces, configures a NetworkManager AP (`ipv4.method=shared`),
  opens the minimum UFW firewall rules needed (forwarding + DHCP/DNS input),
  and manages its own NAT table. Installed to `/usr/local/bin/share-internet`
  by `install.sh`. Also fully usable directly from a terminal:
  `share-internet [start|stop|restart|status|configure <ssid> <password>]`.
- `io.github.imargorsi.hotspot.policy` — a polkit policy naming that exact
  script, installed to `/usr/share/polkit-1/actions/`. This is what lets the
  bar widget call `pkexec /usr/local/bin/share-internet ...` and get a
  proper graphical auth prompt (via omarchy-shell's own polkit agent)
  instead of failing the way a plain `sudo` would from a GUI context.
- The backend writes a **world-readable** status snapshot to
  `/run/share-internet-status.json` on every start/stop/status call
  (SSID, running state, connected clients — nothing that needs root to
  read). `Service.qml` watches that file, so the bar/panel update live
  without needing a password prompt for every refresh. Only actions that
  change something (start/stop/configure) go through `pkexec`.
- `Service.qml` / `BarWidget.qml` / `Panel.qml` — the QML side: bar icon,
  popup panel, editable SSID/password, connected-devices list.

## Making changes

- **UI tweaks**: edit `BarWidget.qml` / `Panel.qml` directly; Quickshell
  hot-reloads on save (see Omarchy's plugin docs — save anywhere under
  `~/.config/omarchy/plugins/` reloads automatically).
- **Backend/firewall logic**: edit `bin/share-internet`, then re-run
  `install.sh` to push the updated copy to `/usr/local/bin/`.
- **Uninstall everything this plugin set up**: `./uninstall.sh`.

## Security notes

This is designed for a personal, single-user laptop, not a shared/multi-user
machine. Trade-offs made deliberately for a simple, no-daemon design:

- `/run/share-internet-status.json` is world-readable (0644) and includes the
  current hotspot password in plaintext, so the bar widget can poll status
  without a password prompt on every refresh. Any other local user on the
  same machine could read it.
- `/etc/share-internet/config` (the persisted SSID/password) is root-only
  (0600).
- `configure <ssid> <password>` passes the new password as a CLI argument to
  the privileged helper, which is briefly visible to other local users via
  `ps`/`/proc/<pid>/cmdline`.

If you're adapting this for a shared machine, don't — or at least tighten
these before you do.

### Known gotchas (found the hard way — see git history / commit messages
if publishing, or just keep this list updated)

- UFW forwarding rules must go through the real `ufw` CLI
  (`ufw route allow ...` + `ufw reload`) — hand-editing
  `/etc/ufw/user.rules` does not reliably apply live.
- NetworkManager's internal `dnsmasq` (used for `ipv4.method=shared`) binds
  normal UDP sockets for DHCP (67) and DNS (53) — not raw sockets — so
  UFW's default `deny (incoming)` silently blocks them unless you add
  explicit `ufw allow in on <wifi> to any port 67/53 ...` rules. Symptom if
  you skip this: client associates fine, gets a `169.254.x.x` APIPA address
  instead of a real DHCP lease, and reports "no internet."
- `dnsmasq` itself must be installed (`pacman -Qi networkmanager` lists it
  as an optional dep for connection sharing) — without it NM hotspot
  activation fails with "IP configuration could not be reserved."

## Publishing this as a public plugin

This was built and tested locally first. To publish:

```bash
cd ~/.config/omarchy/plugins/io.github.imargorsi.hotspot
git init && git add -A && git commit -m "Initial release"
gh repo create imargorsi/omarchy-hotspot --public --source=. --push
```

Then update `homepage` in `manifest.json` and `vendor_url` in the `.policy`
file if the repo name differs from the placeholder used here.

## License

MIT
