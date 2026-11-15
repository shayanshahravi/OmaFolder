import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The vertical drawer behind the folder icon.
//
// It owns no state of its own beyond what it renders: every mutation goes
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

  // A 32px strip with 2px of card padding: the icon keeps roughly a pixel of
  // breathing room on each side instead of sitting in a fat column.
  readonly property int stripWidth: Style.space(32)
  readonly property int manageWidth: Style.space(204)
  readonly property int cardPadding: Style.space(2)
  readonly property int cardWidth: (manageOpen ? manageWidth : stripWidth) + cardPadding * 2 + Style.space(2)
  readonly property int rowHeight: Style.space(32)

  property var items: []
  property var barModules: []
  property bool manageOpen: false
  property bool loading: true
  property bool busy: false
  property string notice: ""
  property int cursorIndex: -1

  // Drag state. The pointer position is tracked in `viewport` coordinates so
  // "inside the drawer" is a plain bounds check.
  property bool dragActive: false
  property string dragId: ""
  property string dragOrigin: ""
  property int dragFrom: -1
  property point dragPoint: Qt.point(0, 0)
  property int dropIndex: -1

  // Right-click menu target.
  property var menuRow: null
  property int menuIndex: -1

  readonly property int itemCount: items.length
  readonly property bool draggingFolderRow: dragActive && dragOrigin === "folder"
  readonly property bool dropOutside: dragActive && (dragPoint.y < 0 || dragPoint.y > viewport.height)

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
    root.runEngine(["toggle", String(entry.id)])
    if (entry.active === true) {
      hideProcess.command = ["omarchy-shell", "-q", "shell", "hide", String(entry.id)]
      hideProcess.running = true
    }
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

  function reorderTo(index) {
    if (!root.dragActive || root.dragOrigin !== "folder" || root.dragFrom < 0) return
    if (index < 0 || index >= root.items.length) return
    if (index === root.dragFrom) return
    root.runEngine(["reorder", root.dragId, String(index)])
  }

  // ---------------------------------------------------------------- menu

  function openMenu(row, index) {
    if (!row) return
    root.menuRow = row
    root.menuIndex = index
    menuPopup.open = true
  }

  function closeMenu() {
    menuPopup.open = false
    root.menuRow = null
  }

  // ---------------------------------------------------------------- dragging

  function beginDrag(source) {
    if (!source) return
    root.dragActive = true
    root.dragId = source.itemId
    root.dragOrigin = source.origin
    root.dragFrom = source.origin === "folder" ? source.position : -1
    root.dropIndex = -1
    root.closeMenu()
  }

  function moveDrag(x, y) {
    if (!root.dragActive) return
    root.dragPoint = Qt.point(x, y)
    root.dropIndex = root.draggingFolderRow ? indexAt(y) : (y >= 0 && y <= viewport.height ? root.items.length : -1)
  }

  function endDrag(x, y) {
    if (!root.dragActive) return
    var inside = y >= 0 && y <= viewport.height && x >= 0 && x <= viewport.width
    var origin = root.dragOrigin
    var id = root.dragId
    var from = root.dragFrom
    var target = root.dropIndex

    root.dragActive = false
    root.dragId = ""
    root.dragOrigin = ""
    root.dragFrom = -1
    root.dropIndex = -1
    root.dragPoint = Qt.point(0, 0)

    // The decision itself lives in Model.resolveDrop so it can be tested
    // without a running shell.
    var plan = Model.resolveDrop(origin, from, target, inside, root.items.length)
    if (plan.action === "fold") root.fold(id)
    else if (plan.action === "eject") {
      root.runEngine(["eject", id])
      root.showNotice("Ejected back to the bar")
    } else if (plan.action === "reorder") root.runEngine(["reorder", id, String(plan.index)])
    else if (plan.action === "same") root.showNotice("Dropped where it started")
  }

  // Which row the pointer is over, by nearest row centre.
  function resetDrag() {
    root.dragActive = false
    root.dragId = ""
    root.dragOrigin = ""
    root.dragFrom = -1
    root.dropIndex = -1
    root.dragPoint = Qt.point(0, 0)
  }

  // Which row the pointer is over, by nearest row centre.
  function indexAt(y) {
    var repeater = stripRepeater
    if (!repeater || repeater.count === 0) return -1
    var best = -1
    var bestDistance = Infinity
    for (var i = 0; i < repeater.count; i++) {
      var row = repeater.itemAt(i)
      if (!row) continue
      var centre = row.mapToItem(viewport, 0, row.height / 2).y
      var distance = Math.abs(centre - y)
      if (distance < bestDistance) {
        bestDistance = distance
        best = i
      }
    }
    return best
  }

  // Drive one complete drag without a pointer: the same begin/move/end path a
  // mouse takes, so automation (and the test suite) exercises the real hit
  // testing and drop rules rather than a shortcut around them.
  // `target` is a row index, or "out" to release outside the drawer.
  function drag(fromIndex, target) {
    var rows = stripRepeater
    if (!rows || rows.count === 0) return JSON.stringify({ ok: false, error: "the drawer is empty" })
    var from = Math.max(0, Math.min(Number(fromIndex) || 0, rows.count - 1))
    var row = rows.itemAt(from)
    if (!row) return JSON.stringify({ ok: false, error: "no row at " + from })

    var y = -1
    if (String(target) !== "out") {
      var to = Math.max(0, Math.min(Number(target) || 0, rows.count - 1))
      var targetRow = rows.itemAt(to)
      if (!targetRow) return JSON.stringify({ ok: false, error: "no row at " + to })
      y = targetRow.mapToItem(viewport, 0, targetRow.height / 2).y
    }

    root.beginDrag(row)
    root.moveDrag(viewport.width / 2, y)
    var resolved = root.dropIndex
    root.endDrag(viewport.width / 2, y)
    return JSON.stringify({ ok: true, from: from, dropIndex: resolved, target: String(target) })
  }

  // ---------------------------------------------------------------- keyboard

  function moveCursor(dx, dy) {
    if (root.manageOpen && dy !== 0) return
    if (root.items.length === 0) return
    var next = root.cursorIndex < 0 ? 0 : root.cursorIndex + dy
    root.cursorIndex = Model.clampIndex(next, root.items.length)
  }

  function activateCursor() {
    if (root.cursorIndex >= 0) root.summon(root.cursorIndex)
  }

  function ejectCursor() {
    if (root.cursorIndex >= 0) root.eject(root.cursorIndex)
  }

  onOpenedChanged: {
    if (opened) {
      root.reload()
    } else {
      root.closeMenu()
      root.resetDrag()
    }
  }
  Component.onCompleted: root.reload()

  // ---------------------------------------------------------------- processes

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
      }
      if (root.manageOpen) root.reloadModules()
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

  // ---------------------------------------------------------------- menu popup

  PopupCard {
    id: menuPopup
    anchorItem: root.menuRow ? root.menuRow : root
    bar: root.bar
    owner: root
    open: false
    margin: Style.gapsOut
    padding: Style.spacing.xs
    contentWidth: Style.space(184)
    contentHeight: menuColumn.implicitHeight + menuPopup.padding * 2
    onOpenChanged: if (!open) root.menuRow = null

    Column {
      id: menuColumn
      width: parent.width
      spacing: Style.spacing.xxs

      readonly property var entry: root.menuIndex >= 0 && root.menuIndex < root.items.length ? root.items[root.menuIndex] : null
      readonly property var actions: [
        { action: "summon", label: "Open panel", enabled: true },
        { action: "toggle", label: menuColumn.entry && menuColumn.entry.active === true ? "Deactivate" : "Activate", enabled: true },
        { action: "up", label: "Move up", enabled: root.menuIndex > 0 },
        { action: "down", label: "Move down", enabled: root.menuIndex >= 0 && root.menuIndex < root.items.length - 1 },
        { action: "eject", label: "Eject to bar", enabled: true }
      ]

      Repeater {
        model: menuColumn.actions

        Item {
          required property var modelData
          width: menuColumn.width
          height: Style.space(26)

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: menuMouse.containsMouse && parent.modelData.enabled
              ? Util.alpha(root.contentColor, Style.hoverFillAlpha)
              : "transparent"
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.xs
            text: parent.modelData.label
            color: Util.alpha(root.contentColor, parent.modelData.enabled ? 0.92 : 0.35)
            font.family: root.contentFont
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: menuMouse
            anchors.fill: parent
            enabled: parent.modelData.enabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
              var action = parent.modelData.action
              var index = root.menuIndex
              menuPopup.open = false
              if (action === "summon") root.summon(index)
              else if (action === "toggle") root.toggleItem(index)
              else if (action === "eject") root.eject(index)
              else if (action === "up" && index > 0) root.runEngine(["reorder", root.items[index].id, String(index - 1)])
              else if (action === "down" && index < root.items.length - 1) root.runEngine(["reorder", root.items[index].id, String(index + 1)])
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- drawer

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: root.cardPadding
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

      // The strip grows out of the bar: content rides up from below the card
      // while the card itself fades in.
      Item {
        id: viewport
        width: parent.width
        height: column.implicitHeight
        clip: true

        Column {
          id: column
          width: viewport.width
          spacing: Style.spacing.xxs
          y: root.opened ? 0 : viewport.height

          Behavior on y {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
          }

          Repeater {
            id: stripRepeater
            model: root.items

            DrawerItem {
              required property var modelData
              required property int index

              width: column.width
              height: root.rowHeight
              item: modelData
              origin: "folder"
              position: index
              displayColor: root.contentColor
              accentColor: Color.accent
              dragLayer: viewport
              hasCursor: root.cursorIndex === index
              dropTarget: root.draggingFolderRow && root.dropIndex === index && root.dragFrom !== index

              onSummonRequested: root.summon(index)
              onMenuRequested: function(row) { root.openMenu(row, index) }
              onDragBegan: root.beginDrag(this)
              onDragMoved: function(x, y) { root.moveDrag(x, y) }
              onDragEnded: function(x, y) { root.endDrag(x, y) }
            }
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
        topPadding: Style.spacing.xs
      }

      // Footer: manage view toggle.
      Item {
        width: parent.width
        height: Style.space(26)

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

      // Manage view: everything still on the bar, one click or one drag away.
      Column {
        visible: root.manageOpen
        width: parent.width
        spacing: Style.spacing.xxs

        Text {
          width: parent.width
          text: "Click to fold, or drag into the folder"
          color: Util.alpha(root.contentColor, 0.6)
          font.family: root.contentFont
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          topPadding: Style.spacing.xs
        }

        Repeater {
          model: root.barModules

          DrawerItem {
            required property var modelData
            required property int index

            width: parent.width
            height: root.rowHeight
            item: ({ id: modelData.id, name: modelData.name, active: true, kindLabel: "On the bar", summonable: false })
            origin: "bar"
            position: index
            displayColor: root.contentColor
            accentColor: Color.accent
            dragLayer: viewport
            showLabel: true
            dropTarget: root.dragActive && root.dragOrigin === "bar" && root.dropIndex === root.items.length

            onSummonRequested: root.fold(modelData.id)
            onMenuRequested: function(row) { root.fold(modelData.id) }
            onDragBegan: root.beginDrag(this)
            onDragMoved: function(x, y) { root.moveDrag(x, y) }
            onDragEnded: function(x, y) { root.endDrag(x, y) }
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

      // Drop hint while dragging outside the strip.
      Text {
        visible: root.draggingFolderRow && root.dropOutside
        width: parent.width
        text: "Release to eject"
        color: Color.urgent
        font.family: root.contentFont
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        topPadding: Style.spacing.xs
      }

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
