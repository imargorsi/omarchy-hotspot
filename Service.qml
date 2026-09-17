import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Talks to the `share-internet` CLI backend (installed separately, once, via
// install.sh — see README). All state-changing calls go through `pkexec`
// (a polkit policy names the exact helper + shows a proper auth prompt via
// omarchy-shell's own polkit agent, with `auth_admin_keep` caching so the
// user isn't re-prompted on every click). Read-only status comes from a
// world-readable JSON snapshot the backend writes on every run, watched here
// via FileView so the UI updates the instant the file changes.
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

  function _applyStatusJson(txt) {
    if (!txt || txt === "") return
    try {
      var s = JSON.parse(txt)
      root.running = !!s.running
      root.ssid = String(s.ssid || "")
      root.password = String(s.password || "")
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
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function (exitCode) {
      root.busy = false
      if (exitCode !== 0) {
        var err = String(actionStderr.text || "").trim()
        root.lastError = err !== "" ? err : "Command failed (exit " + exitCode + ")"
      } else {
        root.lastError = ""
      }
      statusFile.reload()
      root.checkInstalled()
    }
  }

  function _runPkexec(args) {
    if (busy) return
    if (!installed) {
      lastError = "Not installed yet — run install.sh once (see README)."
      return
    }
    busy = true
    lastError = ""
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
    _runPkexec(["configure", s, p])
  }

  // Refresh (as root, so the client list / live state is current) only
  // while the panel is actually open — no background password prompts.
  Process {
    id: refreshProcess
    running: false
    command: []
    onExited: function () { statusFile.reload() }
  }

  function refreshStatus() {
    if (!installed || busy || refreshProcess.running) return
    refreshProcess.command = ["pkexec", helperPath, "status"]
    refreshProcess.running = true
  }

  Timer {
    interval: Math.max(2, root.pollIntervalSec) * 1000
    repeat: true
    running: root.panelOpen && root.installed
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Component.onCompleted: {
    checkInstalled()
    statusFile.reload()
  }
}
