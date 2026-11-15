import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The vertical drawer behind the folder icon.
// It owns no state of its own beyond what it renders: every mutation goes
// through bin/omafolder-state, which rewrites state.json and the bar layout in
// shell.json and then asks the shell to reload. That keeps the drawer, the bar
// and a shell restart in agreement.
//
// Two things are deliberately drawn inside this panel rather than in popups:
// the + button's plugin list and the right-click menu. A popup anchored to a
// row of a layer-shell panel lands wherever the anchor maths says instead of
// under the pointer, and its focus grab fights the panel for input - which is
// what made the old menu appear at the top of the screen and freeze the shell.

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
    return url.replace(/^file:/, "")
  }

  readonly property color contentColor: bar && bar.foreground !== undefined ? bar.foreground : Color.foreground
  readonly property string contentFont: bar && bar.fontFamily ? bar.fontFamily : Style.font.family
  readonly property bool empty: items.length === 0

  // A 32px strip with 2px of card padding: the icon keeps roughly a pixel of
  // breathing room on each side instead of sitting in a fat column.
  readonly property int stripWidth: Style.space(32)
  readonly property int listWidth: Style.space(198)
  readonly property int cardPadding: Style.space(2)
  readonly property int rowHeight: Style.space(32)
  // The menu lives in the space the card gains when it widens, so it can sit
  // beside the strip the pointer is on instead of on top of it.
  readonly property int menuWidth: Math.max(Style.space(150), listWidth - stripWidth - Style.spacing.sm)
  readonly property int menuRowHeight: Style.space(24)

  // ---------------------------------------------------------------- geometry
  //
  // The card is sized from these numbers instead of from implicit layout
  // heights. The panel hangs off the bar, so whatever the card does not count
  // is cut off at the top edge - which is what hid the first row. Every
  // section carries its own gap and an exact height, and the card is the sum.
  readonly property int rowGap: Style.spacing.xxs
  readonly property int footerHeight: Style.space(28)
  readonly property int lineHeight: Math.round(Style.font.caption * 1.45)
  readonly property int confirmHeight: Style.space(26)
  readonly property int menuHeight: root.menuRows.length * root.menuRowHeight + Style.spacing.xs * 2

  readonly property int stripContentHeight: root.items.length === 0
    ? 0
    : root.items.length * root.rowHeight + (root.items.length - 1) * root.rowGap
  readonly property int listHeaderHeight: Math.round(root.lineHeight * 1.8)
  readonly property int listContentHeight: root.availableWidgets.length === 0
    ? root.lineHeight
    : root.availableWidgets.length * root.rowHeight + (root.availableWidgets.length - 1) * root.rowGap

  // What the panel can hand to the card. The rest of the sections are taken
  // out of that budget before the rows get their share, so the card can never
  // grow past the space the panel offers.
  readonly property int bodyCap: Math.max(root.rowHeight + root.footerHeight,
    Math.round(panel.availableCardHeight - panel.verticalContentInset))
  readonly property int promptHeight: root.updatePrompt === null ? 0
    : root.lineHeight * 4 + root.confirmHeight + Style.spacing.xs * 2 + root.rowGap
  readonly property int noticeHeight: (root.notice !== "" || root.checkingId !== "") ? root.lineHeight + root.rowGap : 0
  readonly property int emptyHeight: (root.empty && !root.loading) ? root.lineHeight + root.rowGap : 0

  readonly property int reservedHeight: root.footerHeight + root.rowGap + root.promptHeight + root.noticeHeight + root.emptyHeight
  readonly property int stripViewport: Math.min(root.stripContentHeight,
    Math.max(root.rowHeight, root.bodyCap - root.reservedHeight - root.rowGap * 2))
  readonly property int listViewport: root.listOpen
    ? Math.min(root.listHeaderHeight + root.listContentHeight + root.rowGap,
        Math.max(root.rowHeight * 2,
          root.bodyCap - root.reservedHeight - root.stripViewport - root.rowGap * 3))
    : 0

  readonly property int stripSectionHeight: root.stripViewport > 0 ? root.stripViewport + root.rowGap : 0
  readonly property int addSectionHeight: root.footerHeight + root.rowGap
  readonly property int listSectionHeight: root.listOpen ? root.listViewport + root.rowGap : 0
  readonly property int wantedHeight: root.stripSectionHeight + root.emptyHeight + root.addSectionHeight
    + root.listSectionHeight + root.promptHeight + root.noticeHeight
  readonly property int bodyHeight: Math.max(root.menuOpen ? root.menuHeight : 0,
    Math.min(root.bodyCap, root.wantedHeight))

  // The card widens whenever something with words is showing - the plugin
  // list, the right-click menu or the update prompt - and stays a slim strip
  // otherwise.
  readonly property bool wide: root.listOpen || root.menuOpen || root.updatePrompt !== null
  readonly property int cardWidth: (wide ? listWidth : stripWidth) + cardPadding * 2 + Style.space(2)

  // How far the rows sit from the top of the key catcher, needed to place the
  // right-click menu at the row the pointer is on.
  readonly property real bodyOffset: body.y + stripSection.y + stripFlick.y - stripFlick.contentY

  property var items: []
  property var barModules: []
  property bool loading: true
  property bool busy: false
  property string notice: ""
  property int cursorIndex: -1

  // The + button: closed it is a plus, open the same glyph has turned 45° into
  // a cross and the list of foldable bar widgets has grown underneath it.
  property bool listOpen: false

  readonly property var availableWidgets: (root.barModules || []).filter(function (module) {
    return String(module.id || "") !== "io.github.shayanshahravi.omafolder"
  })

  // Right-click menu, drawn inside the panel at the pointer.
  property bool menuOpen: false
  property int menuIndex: -1
  property real menuX: 0
  property real menuY: 0
  readonly property var menuRows: root.buildMenuRows()

  // Widgets the shell answered "unknown" for, remembered for this session so
  // the menu can say so instead of failing silently.
  property var panellessIds: ({})

  // Per-plugin update check: the id being checked and the result awaiting a
  // yes/no before anything is installed.
  property string checkingId: ""
  property var updatePrompt: null

  // Cursor row inside the open menu, for keyboard walking.
  property int menuCursor: 0
  // Widget the pending summon call is for, read when it answers.
  property string summoningId: ""
  // Widget currently sitting on the bar only because its panel is open.
  property string watchingId: ""
  property int closedReads: 0

  readonly property int itemCount: items.length

  // ---------------------------------------------------------------- state

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

  // ---------------------------------------------------------------- list

  function toggleList() {
    root.listOpen = !root.listOpen
    if (root.listOpen) {
      root.closeMenu()
      root.reloadModules()
    }
    if (root.cursorIndex >= root.items.length) root.cursorIndex = root.items.length - 1
  }

  function fold(id) {
    if (root.busy) return
    root.runEngine(["fold", String(id)])
  }

  // ---------------------------------------------------------------- items

  function isPanelless(item) {
    if (!item) return true
    if (root.panellessIds[String(item.id || "")] === true) return true
    return item.panel === false
  }

  // Fold/eject rewrite the bar layout and reload the shell, which tears this
  // panel down mid-callback. Close first so the reload never lands on a live
  // drawer - that reload was a second way to wedge the shell.
  function runLayoutEngine(args) {
    root.closeMenu()
    root.close()
    Qt.callLater(function() {
      layoutProcess.command = [root.engine].concat(args)
      layoutProcess.running = true
    })
  }

  function toggleItem(index) {
    var entry = root.items[index]
    if (!entry) return
    root.closeMenu()
    root.runEngine(["toggle", String(entry.id)])
  }

  function eject(index) {
    var entry = root.items[index]
    if (!entry) return
    root.runLayoutEngine(["eject", String(entry.id)])
  }

  // Panel, overlay and menu plugins are loaded by the shell registry, so they
  // can be summoned while folded. A plain bar widget can only open its panel
  // through a live bar instance, and a folded one has none.
  readonly property var loaderKinds: ["panel", "overlay", "menu"]

  function needsExpose(entry) {
    var kinds = (entry && entry.kinds) || []
    for (var i = 0; i < kinds.length; i++) {
      if (root.loaderKinds.indexOf(kinds[i]) !== -1) return false
    }
    return kinds.indexOf("bar-widget") !== -1
  }

  function summon(index) {
    var entry = root.items[index]
    if (!entry) return
    root.closeMenu()
    root.summoningId = String(entry.id || "")
    root.close()
    if (root.needsExpose(entry)) {
      // Lend it to the bar for as long as the panel is up, then take it back.
      Qt.callLater(function() {
        exposeProcess.command = [root.engine, "expose", root.summoningId]
        exposeProcess.running = true
      })
      return
    }
    Qt.callLater(function() {
      summonProcess.command = ["omarchy-shell", "shell", "summon", root.summoningId, "{}"]
      summonProcess.running = true
    })
  }

  // The row is only on the bar while its panel is up: as soon as the panel
  // closes it goes back into the folder, in the same position.
  function conceal(id) {
    if (String(id) === "") return
    root.watchingId = ""
    root.closedReads = 0
    watchTimer.stop()
    concealProcess.command = [root.engine, "conceal", String(id)]
    concealProcess.running = true
  }

  function moveItem(from, to) {
    var entry = root.items[from]
    if (!entry) return
    if (to < 0 || to >= root.items.length) return
    root.closeMenu()
    root.runEngine(["reorder", String(entry.id), String(to)])
  }

  // ---------------------------------------------------------------- menu

  function menuItem() {
    if (root.menuIndex < 0 || root.menuIndex >= root.items.length) return null
    return root.items[root.menuIndex]
  }

  function buildMenuRows() {
    var entry = root.menuItem()
    if (!entry) return []
    var index = root.menuIndex
    return [
      {
        action: "summon",
        label: "Open panel",
        enabled: true
      },
      {
        action: "toggle",
        label: entry.active === true ? "Deactivate" : "Activate",
        enabled: true
      },
      { action: "up", label: "Move up", enabled: index > 0 },
      { action: "down", label: "Move down", enabled: index >= 0 && index < root.items.length - 1 },
      { action: "update", label: "Check for update", enabled: true },
      { action: "eject", label: "Eject to bar", enabled: true }
    ]
  }

  function openMenu(index, atY) {
    root.menuIndex = index
    root.listOpen = false
    // Open beside the pointer: `atY` is where the click landed inside the row,
    // so the menu can be centred on it and only then pulled back inside the
    // card. The strip is 32px wide, so its right edge is where the menu starts.
    var height = root.menuRows.length * root.menuRowHeight + Style.spacing.xs * 2
    var x = Math.min(root.stripWidth + Style.spacing.xs, Math.max(0, root.listWidth - root.menuWidth))
    var y = atY - height / 2
    root.menuX = Math.max(0, x)
    root.menuY = Math.max(0, Math.min(y, keyCatcher.height - height))
    root.menuOpen = true
  }

  function closeMenu() {
    root.menuOpen = false
    root.menuIndex = -1
  }

  function chooseMenu(action) {
    var index = root.menuIndex
    root.closeMenu()
    if (action === "summon") root.summon(index)
    else if (action === "toggle") root.toggleItem(index)
    else if (action === "eject") root.eject(index)
    else if (action === "update") root.checkUpdate(index)
    else if (action === "up") root.moveItem(index, index - 1)
    else if (action === "down") root.moveItem(index, index + 1)
  }

  // ---------------------------------------------------------------- updates

  function checkUpdate(index) {
    var entry = root.items[index]
    if (!entry) return
    root.closeMenu()
    root.updatePrompt = null
    root.notice = ""
    root.checkingId = String(entry.id)
    checkProcess.command = [root.engine, "update-check", String(entry.id)]
    checkProcess.running = true
  }

  function applyUpdateCheck(code, text) {
    root.checkingId = ""
    var payload = null
    try { payload = JSON.parse(String(text || "")) } catch (error) { payload = null }
    if (!payload || payload.ok === false) {
      root.showNotice(payload && payload.error ? payload.error : "Could not check for updates")
      return
    }
    if (payload.updateAvailable === true) {
      root.notice = ""
      root.updatePrompt = payload
      return
    }
    root.showNotice(Model.updateSummary(payload))
  }

  function installUpdate() {
    var prompt = root.updatePrompt
    if (!prompt) return
    root.updatePrompt = null
    root.closeMenu()
    root.close()
    Qt.callLater(function() {
      updateProcess.command = [root.engine, "update", String(prompt.id)]
      updateProcess.running = true
    })
  }

  function cancelUpdate() {
    root.updatePrompt = null
  }

  // ---------------------------------------------------------------- keyboard

  function moveCursor(dx, dy) {
    if (root.menuOpen) {
      // j/k walk the menu while it is up.
      if (root.menuRows.length === 0) return
      var next = root.menuCursor + dy
      if (next < 0) next = 0
      if (next > root.menuRows.length - 1) next = root.menuRows.length - 1
      root.menuCursor = next
      return
    }
    if (root.listOpen && dy !== 0) return
    if (root.items.length === 0) return
    var target = root.cursorIndex < 0 ? 0 : root.cursorIndex + dy
    root.cursorIndex = Model.clampIndex(target, root.items.length)
  }

  function activateCursor() {
    if (root.menuOpen) {
      var row = root.menuRows[root.menuCursor]
      if (row && row.enabled) root.chooseMenu(row.action)
      return
    }
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
      root.listOpen = false
      root.updatePrompt = null
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
      if (root.listOpen) root.reloadModules()
      root.reload()
    }
  }

  // Layout mutations reload the shell, so they report through a notification
  // instead of a notice the closing drawer would swallow.
  Process {
    id: layoutProcess
    stdout: StdioCollector { id: layoutOutput; waitForEnd: true }
    onExited: function(code) {
      var payload = null
      try { payload = JSON.parse(String(layoutOutput.text || "")) } catch (error) { payload = null }
      if (code === 0 && payload && payload.ok !== false) return
      notifyProcess.command = [
        "notify-send", "-a", "OmaFolder",
        "OmaFolder", payload && payload.error ? String(payload.error) : "That did not work"
      ]
      notifyProcess.running = true
    }
  }

  Process {
    id: summonProcess
    stdout: StdioCollector { id: summonOutput; waitForEnd: true }
    onExited: function(code) {
      var text = String(summonOutput.text || "").trim()
      var id = root.summoningId
      if (code === 0 && text === "ok") {
        root.watchingId = id
        root.closedReads = 0
        watchTimer.restart()
        return
      }
      // It did not open: put the row straight back in the folder.
      if (id !== "") root.conceal(id)
      if (text === "unknown" && id !== "") {
        var next = {}
        for (var key in root.panellessIds) next[key] = root.panellessIds[key]
        next[id] = true
        root.panellessIds = next
      }
      notifyProcess.command = [
        "notify-send", "-a", "OmaFolder",
        "OmaFolder", "That widget has no panel of its own. Eject it to use it on the bar."
      ]
      notifyProcess.running = true
    }
  }

  // Expose-then-summon: a folded widget has no live bar instance, so the shell
  // cannot summon its panel and answers "unknown". Putting it back in the bar
  // layout gives it an instance and registers its handler; the summon then
  // lands on that instance, and the watcher puts the row back in the folder as
  // soon as the panel closes.
  Process {
    id: exposeProcess
    stdout: StdioCollector { id: exposeOutput; waitForEnd: true }
    onExited: function(code) {
      var payload = null
      try { payload = JSON.parse(String(exposeOutput.text || "")) } catch (error) { payload = null }
      if (code !== 0 || !payload || payload.ok === false) {
        root.summoningId = ""
        notifyProcess.command = [
          "notify-send", "-a", "OmaFolder",
          "OmaFolder", payload && payload.error ? String(payload.error) : "That widget could not be opened"
        ]
        notifyProcess.running = true
        return
      }
      summonTimer.restart()
    }
  }

  Process {
    id: concealProcess
    stdout: StdioCollector { id: concealOutput; waitForEnd: true }
    onExited: function(code) {
      root.reload()
      if (root.listOpen) root.reloadModules()
    }
  }

  // The bar knows whether a widget's panel is up; two closed reads in a row so
  // the moment between summon and the panel appearing does not fold it away.
  Timer {
    id: watchTimer
    interval: 600
    repeat: true
    onTriggered: {
      var id = root.watchingId
      if (id === "") { watchTimer.stop(); return }
      var isOpen = root.bar && typeof root.bar.isBarWidgetOpen === "function"
        && root.bar.isBarWidgetOpen(id) === true
      if (isOpen) { root.closedReads = 0; return }
      root.closedReads += 1
      if (root.closedReads >= 2) root.conceal(id)
    }
  }

  Process {
    id: checkProcess
    stdout: StdioCollector { id: checkOutput; waitForEnd: true }
    onExited: function(code) { root.applyUpdateCheck(code, checkOutput.text) }
  }

  Process {
    id: updateProcess
    stdout: StdioCollector { id: updateOutput; waitForEnd: true }
    onExited: function(code) {
      var payload = null
      try { payload = JSON.parse(String(updateOutput.text || "")) } catch (error) { payload = null }
      if (code === 0 && payload && payload.ok !== false) {
        notifyProcess.command = [
          "notify-send", "-a", "OmaFolder", "OmaFolder",
          Model.updatedMessage(payload)
        ]
      } else {
        notifyProcess.command = [
          "notify-send", "-a", "OmaFolder", "-u", "critical", "OmaFolder update failed",
          payload && payload.error ? String(payload.error) : "The plugin could not be updated"
        ]
      }
      notifyProcess.running = true
    }
  }

  Process {
    id: notifyProcess
    command: []
  }

  Timer {
    id: noticeTimer
    interval: 2600
    onTriggered: root.notice = ""
  }

  // The eject write reloads the shell, so the widget only has a live instance a
  // moment later; the summon has to wait for that reload.
  Timer {
    id: summonTimer
    interval: 1500
    onTriggered: {
      if (root.summoningId === "") return
      summonProcess.command = ["omarchy-shell", "shell", "summon", root.summoningId, "{}"]
      summonProcess.running = true
    }
  }

  // ---------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: root.cardPadding
    contentWidth: panel.fittedContentWidth(root.cardWidth)
    // The card grows to fit the menu when it is open, so the menu never has to
    // spill outside the clickable surface.
    contentHeight: panel.fittedContentHeight(root.bodyHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: {
        if (root.menuOpen) root.closeMenu()
        else if (root.updatePrompt !== null) root.cancelUpdate()
        else if (root.listOpen) root.listOpen = false
        else root.close()
      }
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.ejectCursor()
      onTextKey: function(text) {
        if (text === "m" || text === "+") root.toggleList()
        else if (text === "c") {
          if (root.cursorIndex >= 0) root.checkUpdate(root.cursorIndex)
        }
      }

      // Everything stacks in one column of exactly sized sections, so the card
      // cannot clip a row at its top edge.
      Column {
        id: body
        width: parent.width
        height: root.bodyHeight
        spacing: 0

        // The strip grows out of the bar: content rides up from below the card
        // while the card itself fades in. The rows scroll when the folder holds
        // more than the panel can show.
        Item {
          id: stripSection
          width: body.width
          height: root.stripSectionHeight

          Flickable {
            id: stripFlick
            width: parent.width
            height: root.stripViewport
            contentHeight: strip.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            interactive: root.stripViewport < strip.implicitHeight

            Column {
              id: strip
              width: stripFlick.width
              spacing: root.rowGap
              y: root.opened ? 0 : stripFlick.height

            Behavior on y {
              NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
            }

            Repeater {
              model: root.items

              DrawerItem {
                id: stripRow
                required property var modelData
                required property int index

                width: strip.width
                height: root.rowHeight
                item: modelData
                // With the list open the card is wide, so the folded rows show
                // their names too, aligned exactly like the rows below the +.
                showLabel: root.listOpen
                origin: "folder"
                position: index
                hasCursor: root.cursorIndex === index
                displayColor: root.contentColor
                accentColor: Color.accent

                onSummonRequested: root.summon(index)
                onMenuRequested: function(row, atX, atY) {
                  root.cursorIndex = index
                  // The row itself knows where it sits inside the column, so the
                  // pointer offset only has to be added to that.
                  root.openMenu(index, root.bodyOffset + stripRow.y + atY)
                }
              }
            }
            }
          }
        }

        Text {
          visible: root.empty && !root.loading
          width: body.width
          height: root.emptyHeight
          text: "Empty"
          color: Util.alpha(root.contentColor, 0.55)
          font.family: root.contentFont
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          topPadding: Style.spacing.xs
        }

        // ------------------------------------------------ footer: + button
        Item {
          id: addButton
          width: body.width
          height: root.addSectionHeight

          Item {
            id: addFace
            width: parent.width
            height: root.footerHeight

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: root.listOpen
                ? Util.alpha(root.contentColor, Style.hoverFillAlpha)
                : (addMouse.containsMouse ? Util.alpha(root.contentColor, Style.hoverFillAlpha) : "transparent")
            }

            Text {
              id: addGlyph
              anchors.centerIn: parent
              // A plain plus, not a private-use glyph: the theme's font does not
              // carry every icon code point and a missing one draws nothing.
              text: "+"
              color: root.contentColor
              font.family: root.contentFont
              font.pixelSize: Style.space(16)

              // 0° is a plus, 45° is a cross: the same glyph, rotated.
              transform: Rotation {
                origin.x: addGlyph.width / 2
                origin.y: addGlyph.height / 2
                angle: root.listOpen ? 45 : 0

                Behavior on angle {
                  NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
              }
            }

            MouseArea {
              id: addMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleList()
            }
          }
        }

        // ------------------------------------------------ plugin list (+ button)
        // The list is the + button's open state: it opens right under the + and
        // the card grows upward to make room, scrolling when the bar holds more
        // widgets than the panel can show.
        Item {
          id: listSection
          width: body.width
          height: root.listSectionHeight
          visible: root.listOpen

          Flickable {
            id: listFlick
            width: parent.width
            height: root.listViewport
            contentHeight: foldList.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            interactive: root.listViewport < foldList.implicitHeight

            Column {
              id: foldList
              width: listFlick.width
              spacing: root.rowGap

          Text {
            width: parent.width
            topPadding: Style.spacing.xs
            bottomPadding: Style.spacing.xxs
            text: "Fold a widget into OmaFolder"
            color: Util.alpha(root.contentColor, 0.6)
            font.family: root.contentFont
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.availableWidgets

            DrawerItem {
              required property var modelData
              required property int index

              width: foldList.width
              height: root.rowHeight
              item: ({
                id: modelData.id,
                name: modelData.name,
                active: true,
                kindLabel: "On the bar",
                summonable: false,
                panel: modelData.panel !== false,
                icon: modelData.icon || ""
              })
              origin: "bar"
              position: index
              showLabel: true
              displayColor: root.contentColor
              accentColor: Color.accent

              onSummonRequested: root.fold(modelData.id)
              // A list row has no actions of its own; right-click folds nothing.
              onMenuRequested: function(row, atX, atY) {}
            }
          }

          Text {
            visible: root.availableWidgets.length === 0
            width: parent.width
            text: "Everything on the bar is already folded"
            color: Util.alpha(root.contentColor, 0.5)
            font.family: root.contentFont
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
            }
          }
        }

        // ------------------------------------------------ update prompt
        Item {
          id: promptSection
          width: body.width
          height: root.promptHeight
          visible: root.updatePrompt !== null

          Column {
            id: updateCard
            width: parent.width
            spacing: Style.spacing.xs

            Text {
              objectName: "updateTitle"
              width: parent.width
              height: root.lineHeight
              text: root.updatePrompt === null ? "" : Model.updateTitle(root.updatePrompt)
              color: root.contentColor
              font.family: root.contentFont
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              height: root.lineHeight * 3
              text: root.updatePrompt === null ? "" : Model.updateBody(root.updatePrompt)
              color: Util.alpha(root.contentColor, 0.7)
              font.family: root.contentFont
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              maximumLineCount: 3
              elide: Text.ElideRight
            }

            Row {
              height: root.confirmHeight
              spacing: Style.spacing.xs

            Repeater {
              model: [
                { label: "Install", action: "install", primary: true },
                { label: "Later", action: "later", primary: false }
              ]

              Item {
                required property var modelData
                width: (updateCard.width - Style.spacing.xs) / 2
                height: Style.space(26)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: modelData.primary
                    ? Util.alpha(Color.accent, confirmMouse.containsMouse ? 0.35 : 0.22)
                    : Util.alpha(root.contentColor, confirmMouse.containsMouse ? Style.hoverFillAlpha : 0)
                }

                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  color: modelData.primary ? root.contentColor : Util.alpha(root.contentColor, 0.7)
                  font.family: root.contentFont
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: confirmMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (modelData.action === "install") root.installUpdate()
                    else root.cancelUpdate()
                  }
                }
              }
            }
          }
          }
        }

        // ------------------------------------------------ notice
        Text {
          visible: root.notice !== "" || root.checkingId !== ""
          width: body.width
          height: root.noticeHeight
          text: root.checkingId !== "" ? "Checking " + Model.shortName(root.checkingId) + "…" : root.notice
          color: root.checkingId !== "" ? Util.alpha(root.contentColor, 0.7) : Color.urgent
          font.family: root.contentFont
          font.pixelSize: Style.font.caption
          maximumLineCount: 1
          elide: Text.ElideRight
        }

      }

      // ------------------------------------------------ right-click menu
      BorderSurface {
        id: menuCard
        visible: root.menuOpen
        x: root.menuX
        y: root.menuY
        width: root.menuWidth
        height: menuColumn.implicitHeight + Style.spacing.xs * 2
        z: 200
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.localOrSurfaceSpec(
          "popups", "border", Color.popups.border, Color.popups.border,
          Math.max(1, Style.space(1))
        )

        // Swallow clicks on the padding so they cannot reach a row behind.
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
        }

        Column {
          id: menuColumn
          anchors.fill: parent
          anchors.margins: Style.spacing.xs
          spacing: 0

          Repeater {
            model: root.menuRows

            Item {
              required property var modelData
              required property int index

              width: menuColumn.width
              height: root.menuRowHeight

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: rowMouse.containsMouse && modelData.enabled
                  ? Util.alpha(root.contentColor, Style.hoverFillAlpha)
                  : (root.menuCursor === index && modelData.enabled
                    ? Util.alpha(root.contentColor, Style.hoverFillAlpha * 0.7)
                    : "transparent")
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                text: modelData.label
                color: Util.alpha(root.contentColor, modelData.enabled ? 0.92 : 0.35)
                font.family: root.contentFont
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                enabled: modelData.enabled
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.chooseMenu(modelData.action)
              }
            }
          }
        }
      }
    }
  }

  onMenuOpenChanged: {
    if (root.menuOpen) {
      root.menuCursor = 0
      for (var i = 0; i < root.menuRows.length; i++) {
        if (root.menuRows[i].enabled) { root.menuCursor = i; break }
      }
    }
  }
}
