import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One row of the drawer.
//
// Left click toggles the folded widget's active state, right click asks the
// shell to open that widget's own panel, a 3000 ms hold ejects it back onto the
// bar, hovering for 1500 ms shows a themed card with the widget's name and
// state, and dragging reorders the drawer or drops the row out of the folder.
Item {
  id: root

  property var item: null
  property string origin: "folder" // "folder" or "bar"
  property int position: 0
  property color displayColor: Color.foreground
  property color accentColor: Color.accent
  property bool hasCursor: false

  // 0..1 while the eject hold is running.
  property real holdProgress: 0
  property bool holdCompleted: false
  property bool dragging: false
  property bool dropTarget: false

  readonly property bool active: item ? item.active === true : false
  readonly property string itemId: item ? String(item.id || "") : ""
  readonly property string title: Model.title(item)
  readonly property string subtitle: Model.subtitle(item)
  readonly property string glyph: item ? Model.iconFor(item.id) : ""
  readonly property bool hasGlyph: glyph !== ""
  readonly property bool summonable: item ? item.summonable === true : false
  readonly property color rowColor: active ? displayColor : Util.alpha(displayColor, 0.4)

  signal activateRequested()
  signal summonRequested()
  signal ejectRequested()
  signal dragStarted()
  signal dragFinished()
  signal dropped(var source, int index)

  implicitHeight: Style.space(40)
  implicitWidth: Style.space(44)

  Rectangle {
    id: highlight
    anchors.fill: parent
    anchors.margins: Style.space(1)
    radius: Style.cornerRadius
    color: {
      if (root.dropTarget) return Util.alpha(root.accentColor, Style.selectedFillAlpha)
      if (root.dragging) return "transparent"
      if (mouse.containsMouse || root.hasCursor) return Util.alpha(root.displayColor, Style.hoverFillAlpha)
      return "transparent"
    }
    border.width: root.hasCursor ? Style.focusBorderWidth : 0
    border.color: Util.alpha(root.accentColor, 0.55)

    Behavior on color {
      ColorAnimation { duration: 120 }
    }
  }

  // Target line shown on the row a dragged item would be inserted at.
  Rectangle {
    visible: root.dropTarget
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(1, Style.space(2))
    radius: height / 2
    color: root.accentColor
  }

  // Known bar widgets draw their icon; everything else draws its initial, which
  // cannot end up as a missing-glyph box in any theme font.
  Text {
    anchors.centerIn: parent
    text: root.hasGlyph ? root.glyph : Model.initialFor(root.item)
    color: root.rowColor
    font.family: Style.font.family
    font.pixelSize: root.hasGlyph ? Style.bar.iconFont : Style.font.bodySmall
    font.bold: !root.hasGlyph
    opacity: root.active ? 1 : 0.4
    textFormat: Text.PlainText

    Behavior on opacity {
      NumberAnimation { duration: 140 }
    }
  }

  // Hold-to-eject progress ring. QML has no CSS filters, so "deactivated" is
  // expressed with dimming rather than grayscale.
  Canvas {
    id: ring
    anchors.fill: parent
    visible: root.holdProgress > 0.001
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var radius = Math.min(width, height) / 2 - Style.space(3)
      var centerX = width / 2
      var centerY = height / 2
      ctx.beginPath()
      ctx.arc(centerX, centerY, radius, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * root.holdProgress, false)
      ctx.lineWidth = Math.max(1.5, Style.space(2))
      ctx.strokeStyle = root.accentColor
      ctx.stroke()
    }

    Connections {
      target: root
      function onHoldProgressChanged() { ring.requestPaint() }
    }
  }

  Timer {
    id: holdTimer
    interval: 3000
    repeat: false
    onTriggered: {
      root.holdProgress = 1
      root.holdCompleted = true
      root.ejectRequested()
    }
  }

  Timer {
    id: holdProgress
    interval: 40
    repeat: true
    running: holdTimer.running
    onTriggered: root.holdProgress = Math.min(1, root.holdProgress + interval / 3000)
  }

  Timer {
    id: hoverTimer
    interval: 1500
    repeat: false
    onTriggered: if (!root.dragging) tooltip.visible = true
  }

  function cancelHold() {
    holdTimer.stop()
    holdProgress.stop()
    root.holdProgress = 0
  }

  function stopHover() {
    hoverTimer.stop()
    tooltip.visible = false
  }

  PanelToolTip {
    id: tooltip
    delay: 0
    visible: false
    text: root.title + "\n" + root.subtitle + (root.summonable ? "" : "\nRight click needs a panel")
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
    property bool pressed: false

    onEntered: hoverTimer.restart()
    onExited: {
      root.stopHover()
      if (root.pressed) root.cancelHold()
    }
    onPressed: function(event) {
      if (event.button !== Qt.LeftButton) return
      mouse.pressed = true
      mouse.pressPoint = Qt.point(mouse.x, mouse.y)
      root.holdCompleted = false
      root.holdProgress = 0
      holdTimer.restart()
    }
    onPositionChanged: {
      if (!mouse.pressed || root.dragging) return
      var dx = mouse.x - mouse.pressPoint.x
      var dy = mouse.y - mouse.pressPoint.y
      if (Math.sqrt(dx * dx + dy * dy) < 8) return
      root.cancelHold()
      root.stopHover()
      root.dragging = true
      root.dragStarted()
    }
    onReleased: function(event) {
      var wasDragging = root.dragging
      root.cancelHold()
      mouse.pressed = false
      if (root.dragging) {
        // Drag.active flips false here; dragFinished() below reports whether a
        // DropArea took it.
        return
      }
      if (root.holdCompleted) {
        root.holdCompleted = false
        return
      }
      if (event.button === Qt.RightButton) root.summonRequested()
      else root.activateRequested()
    }
    onCanceled: {
      root.cancelHold()
      mouse.pressed = false
    }
  }

  Drag.active: root.dragging
  Drag.source: root
  Drag.dragType: Drag.Internal
  Drag.hotSpot: Qt.point(width / 2, height / 2)
  Drag.mimeData: ({ "text/omafolder-id": root.itemId })
  Drag.onDragFinished: function(dropAction) {
    var wasDragging = root.dragging
    root.dragging = false
    root.cancelHold()
    if (wasDragging) root.dragFinished()
  }

  // A row is both a drag source and a drop target: dropping another row here
  // inserts before this one.
  DropArea {
    anchors.fill: parent
    onEntered: function(drag) {
      if (!drag.source || drag.source === root) return
      root.dropTarget = true
    }
    onExited: root.dropTarget = false
    onDropped: function(drop) {
      root.dropTarget = false
      if (!drop.source || drop.source === root) return
      drop.accept(Qt.MoveAction)
      root.dropped(drop.source, root.position)
    }
  }
}
