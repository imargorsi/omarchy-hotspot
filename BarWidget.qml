import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Manifest entry point. Owns the bar icon + the Service (backend state);
// loads Panel.qml for the popup. Structure follows Omarchy's built-in
// widgets and the quran-verse plugin.
BarWidget {
  id: root
  moduleName: "io.github.imargorsi.hotspot"

  Service { id: service }

  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color barIconColor: service.running
    ? Color.accent
    : root.barForeground

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = service
  }

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    service.pollIntervalSec = Number(root.setting("pollIntervalSec", 5)) || 5
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.imargorsi.hotspot"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function startHotspot(): void { service.start() }
    function stopHotspot(): void { service.stop() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-fa-wifi (U+F1EB). A font glyph, not an image asset.
    text: "\uf1eb"
    foreground: root.barIconColor
    tooltipText: service.running
      ? ("Hotspot on · " + service.ssid + " · " + service.clientCount + " connected")
      : "Internet Hotspot (off)"
    onPressed: function (b) { root.togglePanel() }
  }
}
