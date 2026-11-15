import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar entry point for OmaFolder: a folder icon carrying the number of widgets
// folded behind it, plus the popup lifecycle Quattro routes clicks and IPC
// through. The drawer itself lives in Drawer.qml.
BarWidget {
  id: root
  moduleName: "io.github.shayanshahravi.omafolder"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property int itemCount: panelLoader.item ? panelLoader.item.itemCount : 0

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight




  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Drawer.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.shayanshahravi.omafolder"

    function refresh(): void { root.broadcast("reload") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf07b"
    tooltipText: root.itemCount > 0
      ? "OmaFolder · " + root.itemCount + (root.itemCount === 1 ? " folded widget" : " folded widgets")
      : "OmaFolder · empty"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  Rectangle {
    id: badge
    visible: root.itemCount > 0
    anchors.top: button.top
    anchors.right: button.right
    z: 10

    readonly property string countText: root.itemCount > 9 ? "9+" : String(root.itemCount)

    implicitWidth: Math.max(Style.space(13), badgeLabel.implicitWidth + Style.space(6))
    implicitHeight: Style.space(13)
    radius: height / 2
    color: Color.accent
    border.width: 1
    border.color: root.bar ? root.bar.background : "transparent"

    Text {
      id: badgeLabel
      anchors.centerIn: parent
      text: badge.countText
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.round(Style.font.caption * 0.85)
      font.bold: true
    }
  }
}
