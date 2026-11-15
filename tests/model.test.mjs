// Unit tests for Model.js, the pure logic behind the drawer.
//
// Run with: node --test tests/model.test.mjs

import { readFileSync } from "node:fs"
import { test } from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../Model.js", import.meta.url), "utf8")
const model = new Function(
  source + "\nreturn { resolveDrop, moveItem, clampIndex, iconFor, hasIcon, initialFor, badgeText }"
)()

test("a folder row dropped outside the drawer ejects", () => {
  assert.deepEqual(model.resolveDrop("folder", 1, 2, false, 3), { action: "eject" })
})

test("a manage row dropped outside the drawer does nothing", () => {
  assert.deepEqual(model.resolveDrop("bar", -1, -1, false, 3), { action: "none" })
})

test("a manage row dropped inside the drawer folds", () => {
  assert.deepEqual(model.resolveDrop("bar", -1, 1, true, 3), { action: "fold" })
})

test("a folder row dropped on another row reorders", () => {
  assert.deepEqual(model.resolveDrop("folder", 0, 2, true, 3), { action: "reorder", index: 2 })
  assert.deepEqual(model.resolveDrop("folder", 2, 0, true, 3), { action: "reorder", index: 0 })
})

test("a folder row dropped on itself reports same", () => {
  assert.deepEqual(model.resolveDrop("folder", 1, 1, true, 3), { action: "same" })
})

test("an out-of-range target is ignored", () => {
  assert.deepEqual(model.resolveDrop("folder", 0, 5, true, 3), { action: "none" })
  assert.deepEqual(model.resolveDrop("folder", 0, -1, true, 3), { action: "none" })
})

test("an unknown origin is ignored", () => {
  assert.deepEqual(model.resolveDrop("nope", 0, 0, true, 3), { action: "none" })
})

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
