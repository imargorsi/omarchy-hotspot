import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Talks to the `share-internet` CLI backend (installed separately, once, via
// install.sh — see README). All state-changing calls go through `pkexec`
// (a polkit policy names the exact helper + shows a proper auth prompt via
// omarchy-shell's own polkit agent, with `auth_admin_keep` caching so the
// user isn't re-prompted on every click). Read-only status comes from a
// owner-only (0600) JSON snapshot the backend writes on every run, watched
// here via FileView so the UI updates the instant the file changes. That
// snapshot deliberately holds no secrets: the Wi-Fi password is fetched separately
// (`credentials`, over the pkexec pipe's stdout) and a new one is sent to the
// helper on stdin -- never argv, which any local user can read via ps.
Item {
  id: root

  readonly property string helperPath: "/usr/local/bin/share-internet"
  readonly property string statusPath: "/run/share-internet-status.json"

  property bool installed: false
  property bool running: false
  property string ssid: ""
  property string password: ""
  property string wifiIf: ""
  property string ethIf: ""
  property int clientCount: 0
  property var clients: []
  property bool busy: false
  property string lastError: ""
  property bool panelOpen: false
  property int pollIntervalSec: 5
  // Set when the user dismisses or fails the auth prompt, so polling stops
  // instead of re-showing the dialog every few seconds. Cleared on the next
  // deliberate action (opening the panel, start/stop/save).
  property bool authDeclined: false

  function _applyStatusJson(txt) {
    if (!txt || txt === "") return
    try {
      var s = JSON.parse(txt)
      root.running = !!s.running
      root.ssid = String(s.ssid || "")
      root.wifiIf = String(s.wifiIf || "")
      root.ethIf = String(s.ethIf || "")
      root.clientCount = s.clientCount || 0
      root.clients = s.clients || []
    } catch (e) {
      // Stale/partial write mid-read; keep last-known-good state.
    }
  }

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onLoaded: root._applyStatusJson(text())
    onFileChanged: reload()
  }

  Process {
    id: checkInstalledProcess
    running: false
    command: ["test", "-x", root.helperPath]
    onExited: function (exitCode) { root.installed = exitCode === 0 }
  }

  function checkInstalled() {
    if (checkInstalledProcess.running) return
    checkInstalledProcess.running = true
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdinEnabled: true
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onStarted: {
      if (root._stdinPayload !== "") write(root._stdinPayload)
      root._stdinPayload = ""
    }
    onExited: function (exitCode) {
      root.busy = false
      root._stdinPayload = ""
      if (exitCode !== 0) {
        var err = String(actionStderr.text || "").trim()
        if (exitCode === 126 || exitCode === 127) {
          root.lastError = "Authentication was cancelled or denied."
        } else {
          root.lastError = err !== "" ? err : "Command failed (exit " + exitCode + ")"
        }
      } else {
        root.lastError = ""
        // Only while the panel is open: no background password prompts.
        if (root.panelOpen) root.refreshCredentials()
      }
      statusFile.reload()
      root.checkInstalled()
    }
  }

  // Data to feed the next action's stdin (the new Wi-Fi password).
  property string _stdinPayload: ""

  function _runPkexec(args, stdinData) {
    if (busy) return
    if (!installed) {
      lastError = "Not installed yet — run install.sh once (see README)."
      return
    }
    busy = true
    lastError = ""
    authDeclined = false
    _stdinPayload = stdinData || ""
    actionProcess.command = ["pkexec", helperPath].concat(args)
    actionProcess.running = true
  }

  function start() { _runPkexec(["start"]) }
  function stop() { _runPkexec(["stop"]) }
  function restart() { _runPkexec(["restart"]) }
  function toggle() { running ? stop() : start() }

  function configure(newSsid, newPassword) {
    var s = String(newSsid || "").trim()
    var p = String(newPassword || "")
    if (s === "") { lastError = "SSID can't be empty."; return }
    if (p.length < 8) { lastError = "Password must be at least 8 characters."; return }
    if (p.indexOf("\n") !== -1) { lastError = "Password can't contain a line break."; return }
    _runPkexec(["configure", s], p + "\n")
  }

  // Copies text to the Wayland clipboard. wl-copy stays alive holding the
  // selection, so the text must not be on its command line (visible to every
  // local user via ps): it goes in through the environment (owner-only in
  // /proc) and is piped to wl-copy's stdin, with the variable unset first.
  Process {
    id: copyProcess
    running: false
    command: ["sh", "-c", 'pw=$HOTSPOT_COPY_TEXT; unset HOTSPOT_COPY_TEXT; printf %s "$pw" | wl-copy']
  }

  function copyToClipboard(text) {
    if (copyProcess.running || !text) return
    copyProcess.environment = { HOTSPOT_COPY_TEXT: String(text) }
    copyProcess.running = true
  }

  // Refresh (as root, so the client list / live state is current) only
  // while the panel is actually open — no background password prompts.
  Process {
    id: refreshProcess
    running: false
    command: []
    onExited: function (exitCode) {
      if (exitCode === 126 || exitCode === 127) root.authDeclined = true
      statusFile.reload()
      root._pumpCredentials()
    }
  }

  function refreshStatus() {
    if (!installed || busy || authDeclined || refreshProcess.running || credentialsProcess.running || _credentialsPending) return
    refreshProcess.command = ["pkexec", helperPath, "status"]
    refreshProcess.running = true
  }

  // The current password, fetched from the root helper on stdout. It lives
  // only in this process's memory. Status polling and this fetch never run
  // at the same time, so the first auth prompt isn't shown twice.
  property bool _credentialsPending: false

  Process {
    id: credentialsProcess
    running: false
    command: []
    stdout: StdioCollector { id: credentialsStdout; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        try {
          var c = JSON.parse(String(credentialsStdout.text || ""))
          root.password = String(c.password || "")
        } catch (e) {}
      } else if (exitCode === 126 || exitCode === 127) {
        root.authDeclined = true
      }
      root.refreshStatus()
    }
  }

  function refreshCredentials() {
    authDeclined = false
    _credentialsPending = true
    _pumpCredentials()
  }

  // Drops the fetched password so it only lives in memory while the panel is open.
  function clearCredentials() {
    _credentialsPending = false
    password = ""
  }

  function _pumpCredentials() {
    if (!_credentialsPending || !installed || busy || refreshProcess.running || credentialsProcess.running) return
    _credentialsPending = false
    credentialsProcess.command = ["pkexec", helperPath, "credentials"]
    credentialsProcess.running = true
  }

  onInstalledChanged: if (installed && panelOpen) refreshCredentials()

  Timer {
    interval: Math.max(2, root.pollIntervalSec) * 1000
    repeat: true
    running: root.panelOpen && root.installed && !root.authDeclined
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Component.onCompleted: {
    checkInstalled()
    statusFile.reload()
  }
}
