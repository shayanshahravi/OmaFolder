import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One row of the drawer.
// Left click opens that widget's own panel, right click opens its action menu
// right where the pointer is, hovering for 1500 ms explains what it is.

Item {
  id: root

  property var item: null
  property string origin: "folder" // "folder" or "bar"
  property int position: 0
  property color displayColor: Color.foreground
  property color accentColor: Color.accent
  property bool hasCursor: false
  // List rows show the widget name next to the icon; the strip stays icons.
  property bool showLabel: false
  property bool hovering: false

  readonly property bool active: item ? item.active === true : false
  readonly property string itemId: item ? String(item.id || "") : ""
  readonly property string title: Model.title(item)
  readonly property string subtitle: Model.subtitle(item)
  readonly property string glyph: item ? Model.iconFor(item.id) : ""
  readonly property bool hasGlyph: glyph !== ""
  readonly property color rowColor: active ? displayColor : Util.alpha(displayColor, 0.4)
  // Read-only views of the hover tooltip, used by the tests.
  readonly property bool tooltipVisible: tooltip.visible
  readonly property string tooltipText: tooltip.text

  signal summonRequested()
  // The click point travels with the request, relative to this row, so the menu
  // can be drawn at the pointer without any scene-coordinate juggling.
  signal menuRequested(var row, real localX, real localY)

  implicitHeight: Style.space(32)
  implicitWidth: Style.space(32)

  Rectangle {
    id: highlight
    anchors.fill: parent
    radius: Style.cornerRadius
    color: {
      if (mouse.containsMouse || root.hasCursor) return Util.alpha(root.displayColor, Style.hoverFillAlpha)
      return "transparent"
    }
    border.width: root.hasCursor ? Style.focusBorderWidth : 0
    border.color: Util.alpha(root.accentColor, 0.55)
    scale: root.hasCursor ? 0.94 : 1

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }

  Text {
    id: icon
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: root.showLabel ? undefined : parent.horizontalCenter
    anchors.left: root.showLabel ? parent.left : undefined
    anchors.leftMargin: root.showLabel ? Style.spacing.xs : 0
    text: root.hasGlyph ? root.glyph : Model.initialFor(root.item)
    color: root.rowColor
    font.family: Style.font.family
    font.pixelSize: root.hasGlyph ? Style.bar.iconFont : Style.font.bodySmall
    font.bold: !root.hasGlyph
    opacity: root.active ? 1 : 0.4

    Behavior on opacity { NumberAnimation { duration: 140 } }
  }

  Text {
    visible: root.showLabel
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: icon.right
    anchors.leftMargin: Style.spacing.xs
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.xs
    text: root.title
    color: Util.alpha(root.displayColor, 0.85)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  Timer {
    id: hoverTimer
    interval: 1500
    repeat: false
    onTriggered: if (root.hovering) tooltip.visible = true
  }

  PanelToolTip {
    id: tooltip
    delay: 0
    visible: false
    text: root.title + "\n" + root.subtitle
    panelForeground: Color.tooltip.text
    panelBackground: Color.tooltip.background
    panelBorder: Color.tooltip.border
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onEntered: {
      root.hovering = true
      hoverTimer.restart()
    }

    onExited: {
      root.hovering = false
      hoverTimer.stop()
      tooltip.visible = false
    }

    onPressed: tooltip.visible = false

    onReleased: function(event) {
      if (event.button === Qt.RightButton) {
        root.menuRequested(root, mouse.x, mouse.y)
      } else if (event.button === Qt.LeftButton) {
        root.summonRequested()
      }
    }

    onCanceled: tooltip.visible = false
  }
}
