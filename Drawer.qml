import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The vertical drawer behind the folder icon.
//
// It owns no state of its own beyond the list it renders: every mutation goes
// through bin/omafolder-state, which rewrites state.json and the bar layout in
// shell.json and then asks the shell to reload. That keeps the drawer, the bar
// and a shell restart in agreement.
Panel {
  id: root
  moduleName: "io.github.shayanshahravi.omafolder"
  manageIpc: false
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // The helper ships inside the plugin folder, so resolve it relative to this
  // file instead of hardcoding a path under ~/.config/omarchy/plugins.
  readonly property string engine: {
    var url = Qt.resolvedUrl("bin/omafolder-state").toString()
    return url.replace(/^file:\/\//, "")
  }

  readonly property color contentColor: bar && bar.foreground !== undefined ? bar.foreground : Color.foreground
  readonly property string contentFont: bar && bar.fontFamily ? bar.fontFamily : Style.font.family
  readonly property bool empty: items.length === 0

  // Width of the visible strip/manage column. The popup card adds its own
  // padding and border around this, so the width handed to KeyboardPanel has
  // to include those or the rows get squeezed into a few pixels.
  readonly property int stripWidth: Style.space(46)
  readonly property int manageWidth: Style.space(226)
  readonly property int cardWidth: (manageOpen ? manageWidth : stripWidth) + panel.padding * 2 + Style.space(2)

  property var items: []
  property var barModules: []
  property bool manageOpen: false
  property bool loading: true
  property bool busy: false
  property string notice: ""
  property int cursorIndex: -1

  property bool dragActive: false
  property bool dropHandled: false
  property string draggingId: ""
  property string draggingOrigin: ""
  property int draggingPosition: -1

  readonly property int itemCount: items.length

  function reload() {
    if (!summaryProcess.running) summaryProcess.running = true
  }


  function reloadModules() {
    if (!modulesProcess.running) modulesProcess.running = true
  }

  function showNotice(text) {
    root.notice = String(text || "")
    noticeTimer.restart()
  }

  function applySummary(code, text) {
    root.loading = false
    var payload = null
    try { payload = JSON.parse(String(text || "")) } catch (error) { payload = null }
    if (code !== 0 || !payload || payload.ok === false) {
      root.items = []
      root.showNotice(payload && payload.error ? payload.error : "OmaFolder state could not be read")
      return
    }
    root.items = payload.items || []
    if (root.cursorIndex >= root.items.length) root.cursorIndex = root.items.length - 1
  }

  function applyModules(code, text) {
    var payload = null
    try { payload = JSON.parse(String(text || "")) } catch (error) { payload = null }
    root.barModules = (code === 0 && payload && payload.ok !== false) ? (payload.modules || []) : []
  }

  function runEngine(args) {
    if (root.busy) return
    root.busy = true
    engineProcess.command = [root.engine].concat(args)
    engineProcess.running = true
  }

  function toggleManage() {
    root.manageOpen = !root.manageOpen
    if (root.manageOpen) root.reloadModules()
  }

  function toggleItem(index) {
    var entry = root.items[index]
    if (!entry) return
    root.cursorIndex = index
    root.runEngine(["toggle", String(entry.id)])
    if (entry.active === true) summonHide(entry.id)
  }

  function eject(index) {
    var entry = root.items[index]
    if (!entry) return
    root.runEngine(["eject", String(entry.id)])
  }

  function fold(id) {
    root.runEngine(["fold", String(id)])
  }

  function summon(index) {
    var entry = root.items[index]
    if (!entry) return
    summonProcess.command = ["omarchy-shell", "shell", "toggle", String(entry.id), "{}"]
    summonProcess.running = true
  }

  function summonHide(id) {
    hideProcess.command = ["omarchy-shell", "-q", "shell", "hide", String(id)]
    hideProcess.running = true
  }

  function moveCursor(dx, dy) {
    if (root.manageOpen && dy !== 0) return
    if (root.items.length === 0) return
    var next = root.cursorIndex < 0 ? 0 : root.cursorIndex + dy
    root.cursorIndex = Model.clampIndex(next, root.items.length)
  }

  function activateCursor() {
    if (root.cursorIndex >= 0) root.toggleItem(root.cursorIndex)
  }

  function ejectCursor() {
    if (root.cursorIndex >= 0) root.eject(root.cursorIndex)
  }

  function beginDrag(source) {
    if (!source) return
    root.dragActive = true
    root.dropHandled = false
    root.draggingId = source.itemId
    root.draggingOrigin = source.origin
    root.draggingPosition = source.origin === "folder" ? source.position : -1
  }

  function handleDrop(source, index) {
    if (!source) return
    root.dropHandled = true
    if (source.origin === "bar") {
      root.fold(source.itemId)
      return
    }
    if (source.position === index) return
    root.runEngine(["reorder", String(source.itemId), String(index)])
  }

  function endDrag() {
    // DropArea.onDropped can arrive just after the source's dragFinished, so
    // settle on the next tick before treating the drag as a drag-out.
    settleTimer.restart()
  }

  function settleDrag() {
    if (!root.dropHandled && root.dragActive && root.draggingOrigin === "folder" && root.draggingPosition >= 0) {
      root.eject(root.draggingPosition)
      root.showNotice("Ejected back to the bar")
    }
    root.dragActive = false
    root.dropHandled = false
    root.draggingId = ""
    root.draggingOrigin = ""
    root.draggingPosition = -1
  }

  onOpenedChanged: if (opened) root.reload()
  Component.onCompleted: root.reload()

  Process {
    id: summaryProcess
    command: [root.engine, "summary"]
    stdout: StdioCollector { id: summaryOutput; waitForEnd: true }
    onExited: function(code) { root.applySummary(code, summaryOutput.text) }
  }

  Process {
    id: modulesProcess
    command: [root.engine, "bar-modules"]
    stdout: StdioCollector { id: modulesOutput; waitForEnd: true }
    onExited: function(code) { root.applyModules(code, modulesOutput.text) }
  }

  Process {
    id: engineProcess
    stdout: StdioCollector { id: engineOutput; waitForEnd: true }
    onExited: function(code) {
      root.busy = false
      var payload = null
      try { payload = JSON.parse(String(engineOutput.text || "")) } catch (error) { payload = null }
      if (code !== 0 || !payload || payload.ok === false) {
        root.showNotice(payload && payload.error ? payload.error : "That did not work")
      } else if (root.manageOpen) {
        root.reloadModules()
      }
      root.reload()
    }
  }

  Process {
    id: summonProcess
    stdout: StdioCollector { id: summonOutput; waitForEnd: true }
    onExited: function(code) {
      var text = String(summonOutput.text || "").trim()
      if (code !== 0 || text === "" || text.indexOf("unknown") === 0) {
        root.showNotice("That widget has no panel of its own — eject it to use it")
      }
    }
  }

  Process {
    id: hideProcess
    command: []
  }

  Timer {
    id: noticeTimer
    interval: 2600
    onTriggered: root.notice = ""
  }

  Timer {
    id: settleTimer
    interval: 90
    onTriggered: root.settleDrag()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.cardWidth)
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.ejectCursor()
      onTextKey: function(text) {
        if (text === "m" || text === "+") root.toggleManage()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.spacing.xs

        // ------------------------------------------------------------ header
        Text {
          visible: root.manageOpen
          width: parent.width
          text: "Drag a bar widget onto the folder"
          color: Util.alpha(root.contentColor, 0.7)
          font.family: root.contentFont
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          topPadding: Style.spacing.xs
        }

        // ------------------------------------------------------------- strip
        Column {
          width: parent.width
          spacing: Style.spacing.xxs

          Repeater {
            model: root.items

            DrawerItem {
              required property var modelData
              required property int index

              width: column.width
              item: modelData
              origin: "folder"
              position: index
              displayColor: root.contentColor
              accentColor: Color.accent
              hasCursor: root.cursorIndex === index

              onActivateRequested: root.toggleItem(index)
              onSummonRequested: root.summon(index)
              onEjectRequested: root.eject(index)
              onDragStarted: root.beginDrag(this)
              onDragFinished: root.endDrag()
              onDropped: function(source, target) { root.handleDrop(source, target) }
            }
          }
        }

        Text {
          visible: root.empty && !root.loading
          width: parent.width
          text: "Empty"
          color: Util.alpha(root.contentColor, 0.55)
          font.family: root.contentFont
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          padding: Style.spacing.xs
        }

        // Eject zone, only while dragging a folded row.
        Item {
          id: ejectZone
          visible: root.dragActive && root.draggingOrigin === "folder"
          width: parent.width
          height: visible ? Style.space(30) : 0

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: ejectArea.containsDrag ? Util.alpha(Color.urgent, 0.25) : Util.alpha(root.contentColor, 0.06)
            border.width: 1
            border.color: Util.alpha(root.contentColor, 0.2)
          }

          Text {
            anchors.centerIn: parent
            text: "\uf08e"
            color: root.contentColor
            font.family: root.contentFont
            font.pixelSize: Style.font.body
          }

          DropArea {
            id: ejectArea
            anchors.fill: parent
            onDropped: function(drop) {
              if (!drop.source) return
              drop.accept(Qt.MoveAction)
              root.dropHandled = true
              if (drop.source.origin === "folder") root.eject(drop.source.position)
            }
          }
        }

        // ------------------------------------------------------------ footer
        Item {
          width: parent.width
          height: Style.space(28)

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: manageMouse.containsMouse ? Util.alpha(root.contentColor, Style.hoverFillAlpha) : "transparent"
          }

          Text {
            anchors.centerIn: parent
            text: root.manageOpen ? "\uf00d" : "\uf067"
            color: root.contentColor
            font.family: root.contentFont
            font.pixelSize: Style.font.body
          }

          MouseArea {
            id: manageMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleManage()
          }
        }

        // ------------------------------------------------------------- manage
        Column {
          visible: root.manageOpen
          width: parent.width
          spacing: Style.spacing.xxs

          Repeater {
            model: root.barModules

            Item {
              id: moduleRow
              required property var modelData
              required property int index

              readonly property string itemId: String(modelData.id || "")
              readonly property string origin: "bar"
              readonly property int position: -1
              readonly property bool dragging: false

              width: column.width
              height: Style.space(26)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: moduleMouse.containsMouse ? Util.alpha(root.contentColor, Style.hoverFillAlpha) : "transparent"
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                text: Model.iconFor(moduleRow.itemId)
                color: root.contentColor
                font.family: root.contentFont
                font.pixelSize: Style.font.body
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(24)
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                text: String(moduleRow.modelData.name || moduleRow.itemId)
                color: Util.alpha(root.contentColor, 0.8)
                font.family: root.contentFont
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              MouseArea {
                id: moduleMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.fold(moduleRow.itemId)
              }

              Drag.active: moduleRow.dragging
              Drag.source: moduleRow
              Drag.dragType: Drag.Internal
              Drag.hotSpot: Qt.point(moduleRow.width / 2, moduleRow.height / 2)
              Drag.mimeData: ({ "text/omafolder-id": moduleRow.itemId })

              // Module rows only start dragging when the pointer leaves them
              // vertically; a plain click folds instead.
              DragHandler {
                target: null
                onActiveChanged: if (active) root.beginDrag(moduleRow)
              }
            }
          }

          Text {
            visible: root.barModules.length === 0
            width: parent.width
            text: "Nothing left on the bar to fold"
            color: Util.alpha(root.contentColor, 0.5)
            font.family: root.contentFont
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ------------------------------------------------------------- notice
        Text {
          visible: root.notice !== ""
          width: parent.width
          text: root.notice
          color: Color.urgent
          font.family: root.contentFont
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
