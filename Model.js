// Pure helpers for the OmaFolder drawer. Nothing here touches QML types, so
// the same functions can be exercised from a plain JS runtime in tests.

var FOLDER_GLYPH = "\uf07b"
var FALLBACK_GLYPH = "\uf12e"
var CHEVRON_GLYPH = "\uf078"

// Font Awesome / Nerd Font glyphs for the Omarchy bar widgets most people
// fold. Anything unknown falls back to a neutral dot rather than rendering a
// missing-glyph box.
var ICONS = {
  "omarchy.menu": "\uf0c9",
  "omarchy.workspaces": "\uf009",
  "omarchy.clock": "\uf017",
  "omarchy.audio": "\uf028",
  "omarchy.network": "\uf1eb",
  "omarchy.bluetooth": "\uf293",
  "omarchy.power": "\uf240",
  "omarchy.monitor": "\uf108",
  "omarchy.media": "\uf001",
  "omarchy.microphone": "\uf130",
  "omarchy.weather": "\uf0c2",
  "omarchy.tray": "\uf02d",
  "omarchy.tailscale": "\uf023",
  "omarchy.system-update": "\uf019",
  "omarchy.indicators": "\uf111",
  "omarchy.keyboard-layout": "\uf11c",
  "omarchy.agents": "\uf085"
}

// Known widgets get their own glyph. Anything else gets an empty string so the
// view can fall back to the plugin's initial: an unknown id has no icon, and a
// guessed glyph renders as a missing-glyph box on fonts without that codepoint.
function iconFor(id) {
  var key = String(id || "")
  return ICONS[key] || ""
}

function hasIcon(id) {
  return !!ICONS[String(id || "")]
}

function initialFor(item) {
  var name = String((item && (item.name || item.id)) || "")
  var trimmed = name.replace(/^[^A-Za-z0-9\u0600-\u06FF]+/, "")
  return trimmed.length > 0 ? trimmed.charAt(0).toUpperCase() : "\u2022"
}

function clampIndex(index, count) {
  var value = Number(index)
  if (!isFinite(value)) return 0
  value = Math.round(value)
  if (value < 0) return 0
  if (count <= 0) return 0
  if (value > count - 1) return count - 1
  return value
}

// Returns a new array with the item at `from` moved to `to`. QML's ListModel
// is not used for the drawer, so plain array math keeps the state file and the
// rendered column in the same order.
function moveItem(items, from, to) {
  var list = (items || []).slice()
  if (list.length < 2) return list
  var source = clampIndex(from, list.length)
  var target = clampIndex(to, list.length)
  if (source === target) return list
  var entry = list.splice(source, 1)[0]
  list.splice(target, 0, entry)
  return list
}

function badgeText(count) {
  var value = Number(count) || 0
  if (value <= 0) return ""
  if (value > 9) return "9+"
  return String(value)
}

function statusLabel(item) {
  return item && item.active === true ? "Active" : "Inactive"
}

function title(item) {
  if (!item) return ""
  return String(item.name || item.id || "")
}

// Compact line under the title in the hover tooltip.
function subtitle(item) {
  if (!item) return ""
  return statusLabel(item) + " · " + String(item.kindLabel || "Bar widget")
}

function tooltipText(item) {
  if (!item) return ""
  return title(item) + "\n" + subtitle(item)
}

function drawerTooltip(item) {
  if (!item) return ""
  return title(item) + " — " + subtitle(item)
}

function folderTooltip(count) {
  var value = Number(count) || 0
  if (value <= 0) return "OmaFolder · empty, drag a bar widget in"
  return "OmaFolder · " + value + (value === 1 ? " folded widget" : " folded widgets")
}

function isEmpty(items) {
  return !items || items.length === 0
}

function indexOfId(items, id) {
  var list = items || []
  for (var i = 0; i < list.length; i++) {
    if (String(list[i].id || "") === String(id || "")) return i
  }
  return -1
}

// "omarchy.audio" -> "audio", "io.github.ayan-de.android-mirror" ->
// "android-mirror". Used where the full id would be noise.
function shortName(id) {
  var value = String(id || "")
  if (value === "") return ""
  var parts = value.split(".")
  return parts.length > 1 ? parts[parts.length - 1] : value
}

// A widget whose click cannot open a panel: say what to do instead of failing.
function noPanelNotice(item) {
  return title(item) + " has no panel of its own -- eject it to use it on the bar"
}

// ------------------------------------------------------------ update review
//
// `review` is what `bin/omafolder-state update-check <id>` prints: the installed
// version, the version the marketplace shows, and why the check ended the way
// it did.

function updateSummary(review) {
  if (!review) return "No update information"
  if (review.updateAvailable === true) {
    return "Version " + String(review.latest || "") + " is published"
  }
  return String(review.note || "Up to date")
}

function updateTitle(review) {
  if (!review) return ""
  var name = String(review.name || review.id || "this plugin")
  var latest = String(review.latest || "")
  if (latest === "") return "A newer " + name + " is published"
  return "Version " + latest + " of " + name + " is published"
}

function updateBody(review) {
  if (!review) return ""
  var installed = String(review.installed || "")
  var where = review.listed === true ? "the Omarchy marketplace" : "its repository"
  var text = installed !== ""
    ? "You have " + installed + ", checked against " + where + "."
    : "Checked against " + where + "."
  return text + " Install it now?"
}

function updatedMessage(payload) {
  if (!payload) return "Plugin updated"
  var name = String(payload.name || payload.id || "Plugin")
  var version = String(payload.version || "")
  return version !== "" ? name + " updated to " + version : name + " updated to the latest commit"
}

function summaryLine(count) {
  var value = Number(count) || 0
  if (value === 0) return "No folded widgets"
  return value + (value === 1 ? " folded widget" : " folded widgets")
}
