import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The popup: status, start/stop, editable SSID/password, connected devices.
// Built from the same qs.Ui primitives as the first-party bar panels, so it
// inherits the active Omarchy theme and has no colors of its own.
Panel {
  id: root
  moduleName: "io.github.imargorsi.hotspot"
  ipcTarget: "io.github.imargorsi.hotspot"
  manageIpc: false

  // Injected by BarWidget.injectPanel().
  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool passwordRevealed: false
  property string draftSsid: ""
  property string draftPassword: ""
  property bool dirty: false
  property bool _syncing: false

  function _syncDraftFromService() {
    if (!service) return
    if (!dirty) {
      _syncing = true
      draftSsid = service.ssid
      draftPassword = service.password
      _syncing = false
    }
  }

  Connections {
    target: service
    function onSsidChanged() { root._syncDraftFromService() }
    function onPasswordChanged() { root._syncDraftFromService() }
  }

  function open() {
    if (service) { service.panelOpen = true; service.checkInstalled(); service.refreshStatus() }
    _syncDraftFromService()
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    Qt.callLater(function () { if (root.opened) setCenterHoverRevealSuppressed(true) })
  }

  function close() {
    if (service) service.panelOpen = false
    // Discard unsaved edits so reopening shows the real, saved state.
    dirty = false
    _syncDraftFromService()
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() { root.opened ? root.close() : root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  onOpenedChanged: if (opened) Qt.callLater(function () { keyCatcher.forceActiveFocus() })

  function saveCredentials() {
    if (!service) return
    dirty = false
    service.configure(draftSsid, draftPassword)
  }

  function deviceLabel(c) {
    if (c.hostname && c.hostname !== "") return c.hostname
    return "Unknown device"
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(12)

          PanelSectionHeader { text: "Internet Hotspot" }

          // ---- not-installed notice --------------------------------------
          Text {
            visible: service && !service.installed
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "Backend not installed yet. Run install.sh once from the plugin folder (see README), then reopen this panel."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // ---- status row -------------------------------------------------
          Item {
            width: parent.width
            height: Math.max(statusDot.height, statusText.height, statusToggle.height)
            visible: service && service.installed

            Rectangle {
              id: statusDot
              width: Style.space(10); height: Style.space(10); radius: width / 2
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              color: service && service.running ? Color.accent : root.muted
            }

            Text {
              id: statusText
              anchors.left: statusDot.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: service
                ? (service.busy ? "Working…" : (service.running ? "Running" : "Stopped"))
                : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            ToggleSwitch {
              id: statusToggle
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: service ? service.running : false
              busy: service ? service.busy : false
              onToggled: if (service) service.toggle()
            }
          }

          Text {
            visible: service && service.running
            width: parent.width
            textFormat: Text.PlainText
            text: (service ? service.wifiIf : "") + " ← shares → " + (service ? service.ethIf : "")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: service && service.lastError !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: service ? service.lastError : ""
            color: Color.danger || "#e05555"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator { foreground: root.foreground }

          // ---- SSID / password editor -------------------------------------
          PanelSectionHeader { text: "Network name & password" }

          TextField {
            id: ssidField
            width: parent.width
            foreground: root.foreground
            placeholderText: "SSID"
            text: root.draftSsid
            onTextChanged: { root.draftSsid = text; if (!root._syncing) root.dirty = true }
            Keys.onEscapePressed: function (event) { keyCatcher.forceActiveFocus(); event.accepted = true }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: passwordField
              width: parent.width - copyBtn.width - revealBtn.width - Style.space(16)
              foreground: root.foreground
              password: !root.passwordRevealed
              placeholderText: "Password (min. 8 characters)"
              text: root.draftPassword
              onTextChanged: { root.draftPassword = text; if (!root._syncing) root.dirty = true }
              Keys.onEscapePressed: function (event) { keyCatcher.forceActiveFocus(); event.accepted = true }
            }

            PanelActionButton {
              id: revealBtn
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.passwordRevealed ? "\uf070" : "\uf06e"
              tooltipText: root.passwordRevealed ? "Hide password" : "Show password"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.passwordRevealed = !root.passwordRevealed
            }

            PanelActionButton {
              id: copyBtn
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\uf0c5"
              tooltipText: "Copy password"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: Quickshell.execDetached(["wl-copy", "--", root.draftPassword])
            }
          }

          Button {
            width: parent.width
            text: "Save"
            bordered: true
            enabled: root.dirty && service && !service.busy
            foreground: root.foreground
            onClicked: root.saveCredentials()
          }

          PanelSeparator { foreground: root.foreground }

          // ---- connected devices -------------------------------------------
          PanelSectionHeader {
            text: "Connected devices" + (service && service.running ? " (" + service.clientCount + ")" : "")
          }

          Text {
            visible: !service || !service.running || service.clientCount === 0
            width: parent.width
            textFormat: Text.PlainText
            text: service && service.running ? "No devices connected yet." : "Start the hotspot to see connected devices."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: service && service.running && service.clientCount > 0

            Repeater {
              model: service ? service.clients : []
              delegate: Column {
                width: column.width
                spacing: 2
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.deviceLabel(modelData)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: (modelData.ip || "") + "  ·  " + (modelData.mac || "")
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }
  }
}
