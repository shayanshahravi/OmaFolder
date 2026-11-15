// Unit tests for Model.js, the pure logic behind the drawer.
//
// Run with: node --test tests/model.test.mjs

import { readFileSync } from "node:fs"
import { test } from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../Model.js", import.meta.url), "utf8")
const model = new Function(
  source +
    "\nreturn { moveItem, clampIndex, iconFor, hasIcon, initialFor, badgeText," +
    " shortName, noPanelNotice, updateSummary, updateTitle, updateBody, updatedMessage }"
)()

test("moveItem reorders without dropping entries", () => {
  const items = [{ id: "a" }, { id: "b" }, { id: "c" }]
  assert.deepEqual(model.moveItem(items, 0, 2).map((entry) => entry.id), ["b", "c", "a"])
  assert.deepEqual(model.moveItem(items, 2, 0).map((entry) => entry.id), ["c", "a", "b"])
  assert.deepEqual(items.map((entry) => entry.id), ["a", "b", "c"], "input is not mutated")
})

test("clampIndex keeps the cursor inside the list", () => {
  assert.equal(model.clampIndex(-4, 3), 0)
  assert.equal(model.clampIndex(9, 3), 2)
  assert.equal(model.clampIndex(1, 3), 1)
  assert.equal(model.clampIndex(2, 0), 0)
})

test("known widgets get their own glyph and unknown ones fall back to an initial", () => {
  assert.notEqual(model.iconFor("omarchy.audio"), "")
  assert.equal(model.hasIcon("omarchy.audio"), true)
  assert.equal(model.iconFor("someone.unknown-widget"), "")
  assert.equal(model.hasIcon("someone.unknown-widget"), false)
  assert.equal(model.initialFor({ id: "gotar.omarchy-themes", name: "Themes Gallery" }), "T")
  assert.equal(model.initialFor({ id: "x.y", name: "  Android Mirror" }), "A")
})

test("badges stay short", () => {
  assert.equal(model.badgeText(0), "")
  assert.equal(model.badgeText(3), "3")
  assert.equal(model.badgeText(12), "9+")
})

test("shortName drops the namespace", () => {
  assert.equal(model.shortName("omarchy.audio"), "audio")
  assert.equal(model.shortName("io.github.ayan-de.android-mirror"), "android-mirror")
  assert.equal(model.shortName("nodots"), "nodots")
  assert.equal(model.shortName(""), "")
})

test("a panelless widget is told to go back to the bar", () => {
  const notice = model.noPanelNotice({ id: "omarchy.system-update", name: "System update" })
  assert.match(notice, /System update/)
  assert.match(notice, /eject/i)
})

test("an available update names both versions", () => {
  const review = {
    id: "marcho78.titlebars",
    name: "Title Bars",
    installed: "1.0.0",
    latest: "1.2.0",
    updateAvailable: true,
    listed: true
  }
  assert.equal(model.updateTitle(review), "Version 1.2.0 of Title Bars is published")
  assert.match(model.updateBody(review), /1\.0\.0/)
  assert.match(model.updateBody(review), /Omarchy marketplace/)
  assert.match(model.updateBody(review), /Install it now\?/)
  assert.equal(model.updateSummary(review), "Version 1.2.0 is published")
})

test("an up-to-date check explains itself", () => {
  const review = {
    id: "marcho78.titlebars",
    name: "Title Bars",
    installed: "1.0.0",
    latest: "1.0.0",
    updateAvailable: false,
    listed: true,
    note: "Up to date"
  }
  assert.equal(model.updateSummary(review), "Up to date")
  assert.equal(model.updateSummary({ note: "Ships with Omarchy; it updates with the system" }),
    "Ships with Omarchy; it updates with the system")
  assert.equal(model.updateSummary(null), "No update information")
})

test("an update result turns into one sentence", () => {
  assert.equal(
    model.updatedMessage({ id: "x.y", name: "Title Bars", version: "1.2.0" }),
    "Title Bars updated to 1.2.0"
  )
  assert.equal(
    model.updatedMessage({ id: "x.y", name: "Title Bars", version: "" }),
    "Title Bars updated to the latest commit"
  )
})
