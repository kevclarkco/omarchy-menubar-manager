// Run with: node --test
//
// MenubarModel.js is deliberately pure/dependency-free (see its own header
// comment) so it can be exercised here without any QML/Quickshell runtime.
// These tests exist because at least one bug fixed in this plugin's history
// (un-host landing in front of the tray-pinned icon) was a plain logic
// error in exactly this file, found only by hand — the kind of thing a
// two-line regression test would have caught for free. Keep that habit:
// when you fix a bug here, add the case that would have failed before the
// fix, not just the happy path.

"use strict"

const { test, describe } = require("node:test")
const assert = require("node:assert/strict")
const m = require("../MenubarModel.js")

function freshConfig(overrides) {
  var config = {
    bar: { layout: { left: [], center: [], right: [] } },
    plugins: []
  }
  return Object.assign(config, overrides)
}

function ids(list) {
  return list.map(function(e) { return typeof e === "string" ? e : e.id })
}

describe("entryId", function() {
  test("string entry is itself", function() {
    assert.equal(m.entryId("omarchy.tray"), "omarchy.tray")
  })
  test("object entry uses .id, stringified", function() {
    assert.equal(m.entryId({ id: "omarchy.tray", hidden: [] }), "omarchy.tray")
    assert.equal(m.entryId({ id: 5 }), "5")
  })
  test("missing/null id, or non-object/string, is empty string", function() {
    assert.equal(m.entryId({}), "")
    assert.equal(m.entryId({ id: null }), "")
    assert.equal(m.entryId(null), "")
    assert.equal(m.entryId(42), "")
  })
})

describe("ensureShape", function() {
  test("fills in every missing piece", function() {
    var config = {}
    m.ensureShape(config)
    assert.deepEqual(config.bar.layout, { left: [], center: [], right: [] })
    assert.deepEqual(config.plugins, [])
  })
  test("leaves existing valid data alone", function() {
    var config = freshConfig({ bar: { layout: { left: ["a"], center: [], right: [] } }, plugins: [{ id: "x" }] })
    m.ensureShape(config)
    assert.deepEqual(config.bar.layout.left, ["a"])
    assert.deepEqual(config.plugins, [{ id: "x" }])
  })
})

describe("findLayoutLocation / findPluginsLocation / findOwnEntry", function() {
  test("finds a string entry in any section", function() {
    var config = freshConfig({ bar: { layout: { left: [], center: ["b"], right: [] } } })
    assert.deepEqual(m.findLayoutLocation(config, "b"), { section: "center", index: 0 })
  })
  test("finds an object entry by id", function() {
    var config = freshConfig({ bar: { layout: { left: [], center: [], right: [{ id: "c" }] } } })
    assert.deepEqual(m.findLayoutLocation(config, "c"), { section: "right", index: 0 })
  })
  test("returns null when not present", function() {
    var config = freshConfig()
    assert.equal(m.findLayoutLocation(config, "nope"), null)
    assert.equal(m.findPluginsLocation(config, "nope"), null)
  })
  test("findOwnEntry checks bar.layout before plugins[]", function() {
    var config = freshConfig({
      bar: { layout: { left: [], center: [], right: [{ id: "x", fromLayout: true }] } },
      plugins: [{ id: "x", fromPlugins: true }]
    })
    assert.equal(m.findOwnEntry(config, "x").fromLayout, true)
  })
  test("findOwnEntry falls back to plugins[]", function() {
    var config = freshConfig({ plugins: [{ id: "x", hosted: [] }] })
    assert.ok(m.findOwnEntry(config, "x"))
    assert.equal(m.findOwnEntry(config, "missing"), null)
  })
})

describe("hostWidget", function() {
  test("moves a layout entry into plugins[] and records hosted + hostedFrom", function() {
    var config = freshConfig({
      bar: { layout: { left: [], center: [], right: ["omarchy.tray", { id: "kc.mgr", hosted: [] }, "target", "after"] } }
    })
    var changed = m.hostWidget(config, "kc.mgr", "target")
    assert.equal(changed, true)
    assert.deepEqual(ids(config.bar.layout.right), ["omarchy.tray", "kc.mgr", "after"])
    assert.deepEqual(ids(config.plugins), ["target"])
    var own = m.findOwnEntry(config, "kc.mgr")
    assert.deepEqual(own.hosted, ["target"])
    assert.deepEqual(own.hostedFrom, { target: { section: "right", index: 2 } })
    assert.equal(own.popupOpen, true)
  })

  test("refuses to host the tray", function() {
    var config = freshConfig({ bar: { layout: { left: [], center: [], right: ["omarchy.tray", { id: "kc.mgr", hosted: [] }] } } })
    assert.equal(m.hostWidget(config, "kc.mgr", "omarchy.tray"), false)
    assert.deepEqual(ids(config.bar.layout.right), ["omarchy.tray", "kc.mgr"])
  })

  test("refuses empty id or hosting itself", function() {
    var config = freshConfig({ plugins: [{ id: "kc.mgr", hosted: [] }] })
    assert.equal(m.hostWidget(config, "kc.mgr", ""), false)
    assert.equal(m.hostWidget(config, "kc.mgr", "kc.mgr"), false)
  })

  test("a widget with no layout entry yet starts a fresh plugins[] entry", function() {
    var config = freshConfig({ plugins: [{ id: "kc.mgr", hosted: [] }] })
    m.hostWidget(config, "kc.mgr", "never.placed")
    assert.deepEqual(config.plugins.filter(function(p) { return p.id === "never.placed" }), [{ id: "never.placed" }])
    assert.deepEqual(m.findOwnEntry(config, "kc.mgr").hosted, ["never.placed"])
    // No layout entry existed, so there's nothing to remember a position for.
    assert.equal(m.findOwnEntry(config, "kc.mgr").hostedFrom, undefined)
  })

  test("hosting an already-hosted widget again is a harmless no-op on plugins[]", function() {
    var config = freshConfig({ plugins: [{ id: "kc.mgr", hosted: ["already"] }, { id: "already", setting: 1 }] })
    m.hostWidget(config, "kc.mgr", "already")
    assert.deepEqual(ids(config.plugins.filter(function(p) { return p.id === "already" })), ["already"])
    assert.deepEqual(m.findOwnEntry(config, "kc.mgr").hosted, ["already"])
  })

  test("returns false when this manager's own entry can't be found", function() {
    var config = freshConfig({ bar: { layout: { left: [], center: [], right: ["target"] } } })
    assert.equal(m.hostWidget(config, "kc.mgr", "target"), false)
  })
})

describe("unhostWidget", function() {
  test("restores a widget to its remembered section and index", function() {
    var config = freshConfig({
      bar: { layout: { left: [], center: [], right: [
        "omarchy.tray",
        { id: "kc.mgr", hosted: ["target"], hostedFrom: { target: { section: "right", index: 2 } } },
        "a", "b"
      ] } },
      plugins: [{ id: "target", setting: 1 }]
    })
    m.unhostWidget(config, "kc.mgr", "target", "right")
    assert.deepEqual(ids(config.bar.layout.right), ["omarchy.tray", "kc.mgr", "target", "a", "b"])
    // Settings accumulated while hosted travel back with it.
    assert.deepEqual(config.bar.layout.right[2], { id: "target", setting: 1 })
    var own = m.findOwnEntry(config, "kc.mgr")
    assert.deepEqual(own.hosted, [])
    assert.equal(own.hostedFrom.target, undefined)
  })

  test("falls back to fallbackSection, appended at the end, when nothing was remembered", function() {
    var config = freshConfig({
      bar: { layout: { left: [], center: [], right: [
        "omarchy.tray",
        { id: "kc.mgr", hosted: ["target"] },
        "a"
      ] } },
      plugins: [{ id: "target" }]
    })
    m.unhostWidget(config, "kc.mgr", "target", "right")
    assert.deepEqual(ids(config.bar.layout.right), ["omarchy.tray", "kc.mgr", "a", "target"])
  })

  test("honors the older plain-string hostedFrom shape (persisted before index tracking)", function() {
    var config = freshConfig({
      bar: { layout: { left: [], center: [], right: [
        "omarchy.tray",
        { id: "kc.mgr", hosted: ["target"], hostedFrom: { target: "right" } }
      ] } },
      plugins: [{ id: "target" }]
    })
    m.unhostWidget(config, "kc.mgr", "target", "left")
    // No index remembered for the old shape, so it lands at the end of the
    // remembered *section* (right), not the fallback (left).
    assert.deepEqual(ids(config.bar.layout.right), ["omarchy.tray", "kc.mgr", "target"])
    assert.deepEqual(config.bar.layout.left, [])
  })

  test("never lands in front of this manager's own icon, even at its exact remembered index", function() {
    // Regression test: `target` was hosted from right index 1 — the same
    // slot pinAfterTray keeps kc.mgr in — so un-hosting it there naively
    // would push kc.mgr to index 2, breaking "always right after tray".
    var config = freshConfig({
      bar: { layout: { left: [], center: [], right: [
        "omarchy.tray",
        { id: "kc.mgr", hosted: ["target"], hostedFrom: { target: { section: "right", index: 1 } } },
        "b"
      ] } },
      plugins: [{ id: "target" }]
    })
    m.unhostWidget(config, "kc.mgr", "target", "right")
    assert.deepEqual(ids(config.bar.layout.right), ["omarchy.tray", "kc.mgr", "target", "b"])
  })

  test("an orphaned widget id (not actually in plugins[]) still un-hosts as a bare entry", function() {
    var config = freshConfig({
      bar: { layout: { left: [], center: [], right: [
        "omarchy.tray",
        { id: "kc.mgr", hosted: ["ghost"] }
      ] } },
      plugins: []
    })
    m.unhostWidget(config, "kc.mgr", "ghost", "right")
    assert.deepEqual(ids(config.bar.layout.right), ["omarchy.tray", "kc.mgr", "ghost"])
    assert.deepEqual(m.findOwnEntry(config, "kc.mgr").hosted, [])
  })
})

describe("pinAfterTray", function() {
  test("no-op when already immediately after tray", function() {
    var config = freshConfig({ bar: { layout: { left: [], center: [], right: ["omarchy.tray", "kc.mgr", "x"] } } })
    assert.equal(m.pinAfterTray(config, "kc.mgr"), false)
    assert.deepEqual(config.bar.layout.right, ["omarchy.tray", "kc.mgr", "x"])
  })

  test("moves forward into place when several widgets sit between tray and it", function() {
    var config = freshConfig({ bar: { layout: { left: [], center: [], right: ["omarchy.tray", "a", "b", "c", "kc.mgr", "d"] } } })
    assert.equal(m.pinAfterTray(config, "kc.mgr"), true)
    assert.deepEqual(config.bar.layout.right, ["omarchy.tray", "kc.mgr", "a", "b", "c", "d"])
  })

  test("moves backward into place when it currently sits before tray", function() {
    var config = freshConfig({ bar: { layout: { left: [], center: [], right: ["kc.mgr", "omarchy.tray", "x"] } } })
    assert.equal(m.pinAfterTray(config, "kc.mgr"), true)
    assert.deepEqual(config.bar.layout.right, ["omarchy.tray", "kc.mgr", "x"])
  })

  test("no-op when tray isn't in the same section", function() {
    var config = freshConfig({ bar: { layout: { left: ["kc.mgr"], center: [], right: ["omarchy.tray"] } } })
    assert.equal(m.pinAfterTray(config, "kc.mgr"), false)
    assert.deepEqual(config.bar.layout.left, ["kc.mgr"])
  })

  test("no-op when this manager's own entry isn't placed anywhere", function() {
    var config = freshConfig({ bar: { layout: { left: [], center: [], right: ["omarchy.tray"] } } })
    assert.equal(m.pinAfterTray(config, "kc.mgr"), false)
  })
})

describe("toggleHide", function() {
  test("hides a shown widget", function() {
    assert.deepEqual(m.toggleHide([], "a"), ["a"])
  })
  test("un-hides an already-hidden widget", function() {
    assert.deepEqual(m.toggleHide(["a", "b"], "a"), ["b"])
  })
  test("doesn't mutate the array it was given", function() {
    var hidden = ["a"]
    m.toggleHide(hidden, "b")
    assert.deepEqual(hidden, ["a"])
  })
})

describe("moveHosted", function() {
  test("moves earlier (direction < 0)", function() {
    assert.deepEqual(m.moveHosted(["a", "b", "c"], "b", -1), ["b", "a", "c"])
  })
  test("moves later (direction > 0)", function() {
    assert.deepEqual(m.moveHosted(["a", "b", "c"], "b", 1), ["a", "c", "b"])
  })
  test("no-op moving the first item earlier", function() {
    assert.deepEqual(m.moveHosted(["a", "b", "c"], "a", -1), ["a", "b", "c"])
  })
  test("no-op moving the last item later", function() {
    assert.deepEqual(m.moveHosted(["a", "b", "c"], "c", 1), ["a", "b", "c"])
  })
  test("no-op for an id that isn't present", function() {
    assert.deepEqual(m.moveHosted(["a", "b"], "z", -1), ["a", "b"])
  })
  test("doesn't mutate the array it was given", function() {
    var hosted = ["a", "b"]
    m.moveHosted(hosted, "a", 1)
    assert.deepEqual(hosted, ["a", "b"])
  })
})

describe("drawerBucket", function() {
  test("hosted minus hidden, order preserved", function() {
    assert.deepEqual(m.drawerBucket(["a", "b", "c"], ["b"]), ["a", "c"])
  })
  test("nothing hidden returns everything", function() {
    assert.deepEqual(m.drawerBucket(["a", "b"], []), ["a", "b"])
  })
  test("everything hidden returns nothing", function() {
    assert.deepEqual(m.drawerBucket(["a", "b"], ["a", "b"]), [])
  })
})

describe("candidateWidgets", function() {
  function metadataFor(id) {
    var names = { "z.widget": "Zeta", "a.widget": "Alpha" }
    return names[id] ? { displayName: names[id] } : null
  }

  test("excludes self, already-hosted, and the excluded list; sorts by display name", function() {
    var out = m.candidateWidgets(["kc.mgr", "z.widget", "a.widget", "already", "omarchy.tray"], metadataFor, ["already"], "kc.mgr")
    assert.deepEqual(out.map(function(c) { return c.id }), ["a.widget", "z.widget"])
    assert.equal(out[0].displayName, "Alpha")
  })

  test("falls back to the id when metadata is missing", function() {
    var out = m.candidateWidgets(["mystery.widget"], metadataFor, [], "kc.mgr")
    assert.deepEqual(out, [{ id: "mystery.widget", displayName: "mystery.widget", category: "" }])
  })
})

describe("defaultSectionForManifest", function() {
  test("uses a valid declared defaultSection", function() {
    assert.equal(m.defaultSectionForManifest({ barWidget: { defaultSection: "left" } }), "left")
  })
  test("falls back to right for a missing or invalid section", function() {
    assert.equal(m.defaultSectionForManifest({ barWidget: { defaultSection: "nowhere" } }), "right")
    assert.equal(m.defaultSectionForManifest({ barWidget: {} }), "right")
    assert.equal(m.defaultSectionForManifest(null), "right")
    assert.equal(m.defaultSectionForManifest(undefined), "right")
  })
})

describe("normalizeIds", function() {
  test("passes through a clean array of non-empty strings", function() {
    assert.deepEqual(m.normalizeIds(["a", "b"]), ["a", "b"])
  })
  test("drops non-strings and empty strings", function() {
    assert.deepEqual(m.normalizeIds(["a", "", 5, null, "b"]), ["a", "b"])
  })
  test("accepts an array-like object (QML sequence type stand-in)", function() {
    var arrayLike = { 0: "a", 1: "b", length: 2 }
    assert.deepEqual(m.normalizeIds(arrayLike), ["a", "b"])
  })
  test("null/undefined/non-array-like becomes an empty array", function() {
    assert.deepEqual(m.normalizeIds(null), [])
    assert.deepEqual(m.normalizeIds(undefined), [])
    assert.deepEqual(m.normalizeIds({}), [])
  })
})

describe("normalizeSectionMap", function() {
  test("keeps a valid old-style plain-string entry", function() {
    assert.deepEqual(m.normalizeSectionMap({ a: "left" }), { a: "left" })
  })
  test("keeps a valid new-style {section, index} entry", function() {
    assert.deepEqual(m.normalizeSectionMap({ a: { section: "right", index: 2 } }), { a: { section: "right", index: 2 } })
  })
  test("a {section} with no numeric index degrades to the bare section string", function() {
    assert.deepEqual(m.normalizeSectionMap({ a: { section: "right" } }), { a: "right" })
  })
  test("drops invalid sections and malformed entries", function() {
    assert.deepEqual(m.normalizeSectionMap({ a: "nowhere", b: { section: "nowhere", index: 1 }, c: 5, d: null }), {})
  })
  test("null/undefined map becomes an empty object", function() {
    assert.deepEqual(m.normalizeSectionMap(null), {})
    assert.deepEqual(m.normalizeSectionMap(undefined), {})
  })
})
