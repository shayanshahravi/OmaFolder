import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One row of the drawer.
//
// Left click opens that widget's own panel, right click opens its action menu,
// hovering for 1500 ms explains what it is, and holding the button while moving
// drags the row: inside the strip it reorders, out of the strip it ejects.
//
// Dragging is done by hand rather than with Qt's Drag/DropArea objects: an
// internal Qt drag never starts reliably inside a layer-shell surface, while
// pointer tracking through one MouseArea behaves the same on every compositor
// and can be driven by synthetic events in tests.
Item {
  id: root

  property var item: null
  property string origin: "folder" // "folder" or "bar"
  property int position: 0
  property color displayColor: Color.foreground
  property color accentColor: Color.accent
  property bool hasCursor: false
  property bool dragging: false
  property bool dropTarget: false
  // Manage rows show the widget name next to the icon; the strip stays icons.
  property bool showLabel: false
  // Item the pointer position is reported in, so the drawer can test it
  // against the card bounds without guessing.
  property Item dragLayer: null

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
  signal menuRequested(var row)
  signal dragBegan()
  signal dragMoved(real x, real y)
  signal dragEnded(real x, real y)

  implicitHeight: Style.space(32)
  implicitWidth: Style.space(32)

  Rectangle {
    id: highlight
    anchors.fill: parent
    radius: Style.cornerRadius
    color: {
      if (root.dragging) return Util.alpha(root.accentColor, 0.22)
      if (mouse.containsMouse || root.hasCursor) return Util.alpha(root.displayColor, Style.hoverFillAlpha)
      return "transparent"
    }
    border.width: root.hasCursor ? Style.focusBorderWidth : 0
    border.color: Util.alpha(root.accentColor, 0.55)
    scale: root.dragging ? 0.94 : 1

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }

  // Insertion marker: the row the dragged item would land on.
  Rectangle {
    visible: root.dropTarget
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.top
    width: parent.width
    height: Math.max(1, Style.space(2))
    radius: height / 2
    color: root.accentColor
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
    textFormat: Text.PlainText

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
    onTriggered: if (!root.dragging) tooltip.visible = true
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

    property point pressPoint
    property bool held: false

    function pointIn(x, y) {
      var layer = root.dragLayer || root.parent
      return root.mapToItem(layer, x, y)
    }

    onEntered: hoverTimer.restart()
    onExited: {
      hoverTimer.stop()
      tooltip.visible = false
    }

    onPressed: function(event) {
      hoverTimer.stop()
      tooltip.visible = false
      if (event.button !== Qt.LeftButton) return
      held = true
      pressPoint = Qt.point(mouse.x, mouse.y)
    }

    onPositionChanged: {
      if (!mouse.held) return
      var dx = mouse.x - mouse.pressPoint.x
      var dy = mouse.y - mouse.pressPoint.y
      if (!root.dragging) {
        if (Math.sqrt(dx * dx + dy * dy) < 7) return
        root.dragging = true
        root.dragBegan()
      }
      var point = pointIn(mouse.x, mouse.y)
      root.dragMoved(point.x, point.y)
    }

    onReleased: function(event) {
      var wasDragging = root.dragging
      mouse.held = false
      if (wasDragging) {
        var point = pointIn(mouse.x, mouse.y)
        root.dragging = false
        root.dragEnded(point.x, point.y)
        return
      }
      if (event.button === Qt.RightButton) root.menuRequested(root)
      else if (event.button === Qt.LeftButton) root.summonRequested()
    }

    onCanceled: {
      mouse.held = false
      if (root.dragging) {
        root.dragging = false
        var point = pointIn(mouse.x, mouse.y)
        root.dragEnded(point.x, point.y)
      }
    }
  }
}
