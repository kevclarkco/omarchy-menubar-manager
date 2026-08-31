// Pure JS: no QML/Quickshell imports, so this stays runnable/testable outside
// the shell (same reasoning as the built-in Tray widget's TrayModel.js). All
// shell-object access (bar.shell.mutateShellConfig, bar.shell.updateEntryInline,
// bar.barWidgetRegistry, ...) happens in MenubarManager.qml, which calls into
// these functions with plain data.

// omarchy.tray is excluded from hosting: two places in the shell
// (PluginRegistry.barTarget's right-section anchor, BarModel.pinTrayToInner)
// assume its entry always sits in bar.layout.right and key off that literal
// id. Hosting it would relocate that entry into config.plugins[], silently
// changing default-insertion placement for every other right-section widget
// added afterward — plus our own drawer's gatedByDrawer teardown would
// destroy/recreate Tray's live SystemTray subscriptions and open submenu
// state on every hover-out. Not worth it.
var EXCLUDED_WIDGET_IDS = ["omarchy.tray"]

function entryId(entry) {
  if (typeof entry === "string") return entry
  if (entry && typeof entry === "object" && entry.id !== undefined && entry.id !== null)
    return String(entry.id)
  return ""
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

// Local re-implementation of PluginRegistry.ensureConfigShape — deliberately
// not calling the real one. PluginRegistry is only reachable from a bar
// widget via bar.shell.pluginRegistry, an incidental channel (Bar.qml
// exposes `shell`, shell.qml happens to expose `pluginRegistry` on itself),
// not a documented third-party write API. Depending on it for a *write* path
// would couple this plugin to shell internals that could change without
// notice. The ~8-line duplication here is the trade against that coupling.
function ensureShape(config) {
  if (!isPlainObject(config.bar)) config.bar = { layout: { left: [], center: [], right: [] } }
  if (!isPlainObject(config.bar.layout)) config.bar.layout = { left: [], center: [], right: [] }
  var sections = ["left", "center", "right"]
  for (var i = 0; i < sections.length; i++) {
    if (!Array.isArray(config.bar.layout[sections[i]])) config.bar.layout[sections[i]] = []
  }
  if (!Array.isArray(config.plugins)) config.plugins = []
}

function findLayoutLocation(config, id) {
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var arr = config.bar.layout[sections[s]]
    for (var i = 0; i < arr.length; i++) {
      if (entryId(arr[i]) === id) return { section: sections[s], index: i }
    }
  }
  return null
}

function findPluginsLocation(config, id) {
  for (var i = 0; i < config.plugins.length; i++) {
    if (entryId(config.plugins[i]) === id) return { index: i }
  }
  return null
}

function findOwnEntry(config, ownId) {
  var loc = findLayoutLocation(config, ownId)
  if (loc) return config.bar.layout[loc.section][loc.index]
  var ploc = findPluginsLocation(config, ownId)
  if (ploc) return config.plugins[ploc.index]
  return null
}

// Moves widgetId's shell.json entry (with whatever inline settings it already
// carries, e.g. a VPN widget's refreshIntervalSec) from bar.layout.<section>
// into the top-level config.plugins[] array, and records ownership on this
// manager's own entry's `hosted` list. Landing in config.plugins[] keeps
// PluginRegistry.isEnabled() true for the widget (so its Component stays
// registered in barWidgetRegistry and its own settings-persistence keeps
// working) without Bar.qml auto-rendering a ModuleSlot for it anywhere,
// since Bar.qml only ever builds slots from bar.layout.*.
// Call inside bar.shell.mutateShellConfig(function(config) { ... }).
function hostWidget(config, ownId, widgetId) {
  var id = String(widgetId || "")
  if (!id || id === ownId) return false
  if (EXCLUDED_WIDGET_IDS.indexOf(id) !== -1) return false
  ensureShape(config)

  var entry = null
  var layoutLoc = findLayoutLocation(config, id)
  if (layoutLoc) {
    entry = config.bar.layout[layoutLoc.section][layoutLoc.index]
    config.bar.layout[layoutLoc.section].splice(layoutLoc.index, 1)
  }

  var pluginsLoc = findPluginsLocation(config, id)
  if (entry) {
    if (pluginsLoc) config.plugins[pluginsLoc.index] = entry
    else config.plugins.push(entry)
  } else if (!pluginsLoc) {
    // Widget had no layout entry yet (e.g. a first-party widget never
    // placed by the user) and isn't already hosted — start it fresh.
    config.plugins.push({ id: id })
  }
  // else: entry is null and pluginsLoc found — already hosted, nothing to move.

  var own = findOwnEntry(config, ownId)
  if (!own) return false
  if (!Array.isArray(own.hosted)) own.hosted = []
  if (own.hosted.indexOf(id) === -1) own.hosted.push(id)
  // Remember where this widget actually lived, if it lived anywhere, so
  // unhostWidget can put it back there instead of guessing from the
  // widget's manifest defaultSection — most manifests (e.g. the built-in
  // Workspaces widget) don't declare one at all, which silently sent every
  // such widget to "right" on un-host regardless of its real origin.
  if (layoutLoc) {
    if (!isPlainObject(own.hostedFrom)) own.hostedFrom = {}
    own.hostedFrom[id] = layoutLoc.section
  }
  // This is a structural bar.layout change, which forces Bar.qml to destroy
  // and recreate every module slot (see MenubarManager.qml's hostWidgetById
  // comment) — including this widget's own manage popup, mid-click. Flagging
  // a reopen here, in the same atomic write, lets the freshly (re)constructed
  // instance restore it, so the user can act on one widget after another
  // without the popup vanishing on every single click.
  own.popupOpen = true
  return true
}

// Reverses hostWidget: pulls widgetId's entry out of config.plugins[] and
// back into bar.layout.<fallbackSection>, preserving whatever settings it
// accumulated while hosted. Drops it from this manager's hosted/pinned/hidden.
function unhostWidget(config, ownId, widgetId, fallbackSection) {
  var id = String(widgetId || "")
  if (!id) return false
  ensureShape(config)

  var entry = null
  var pluginsLoc = findPluginsLocation(config, id)
  if (pluginsLoc) {
    entry = config.plugins[pluginsLoc.index]
    config.plugins.splice(pluginsLoc.index, 1)
  }
  if (!entry) entry = { id: id }

  var own = findOwnEntry(config, ownId)
  // The section this widget actually came from (recorded by hostWidget)
  // beats the manifest-guessed fallbackSection — most manifests don't
  // declare a defaultSection at all, which isn't the same thing as this
  // widget having genuinely belonged in "right".
  var remembered = own && isPlainObject(own.hostedFrom) ? own.hostedFrom[id] : null
  var section = ["left", "center", "right"].indexOf(remembered) !== -1
    ? remembered
    : (["left", "center", "right"].indexOf(fallbackSection) !== -1 ? fallbackSection : "right")
  config.bar.layout[section].push(entry)

  if (own) {
    own.hosted = (own.hosted || []).filter(function(x) { return x !== id })
    own.pinned = (own.pinned || []).filter(function(x) { return x !== id })
    own.hidden = (own.hidden || []).filter(function(x) { return x !== id })
    if (isPlainObject(own.hostedFrom)) delete own.hostedFrom[id]
    // See the matching comment in hostWidget: also a structural change,
    // also needs the popup restored on the other side of the rebuild.
    own.popupOpen = true
  }
  return true
}

// Pin/hide only ever touch this manager's own inline settings — no
// relocation, no mutateShellConfig — so they stay pure functions the QML
// side persists in one updateEntryInline call, same shape as Tray.qml's
// togglePin/toggleHide (Tray.qml L189-211).
function togglePin(pinnedIds, hiddenIds, id) {
  var p = pinnedIds.slice(), h = hiddenIds.slice()
  var idx = p.indexOf(id)
  if (idx !== -1) {
    p.splice(idx, 1)
  } else {
    p.push(id)
    var hi = h.indexOf(id)
    if (hi !== -1) h.splice(hi, 1)
  }
  return { pinned: p, hidden: h }
}

function toggleHide(pinnedIds, hiddenIds, id) {
  var p = pinnedIds.slice(), h = hiddenIds.slice()
  var idx = h.indexOf(id)
  if (idx !== -1) {
    h.splice(idx, 1)
  } else {
    h.push(id)
    var pi = p.indexOf(id)
    if (pi !== -1) p.splice(pi, 1)
  }
  return { pinned: p, hidden: h }
}

// hosted − pinned − hidden = the drawer bucket, mirroring Tray.qml's
// classifyItem/bucket (Tray.qml L155-181) over widget ids instead of tray items.
function classify(id, pinnedIds, hiddenIds) {
  if (hiddenIds.indexOf(id) !== -1) return "hidden"
  if (pinnedIds.indexOf(id) !== -1) return "pinned"
  return "drawer"
}

function bucket(category, hostedIds, pinnedIds, hiddenIds) {
  var result = []
  for (var i = 0; i < hostedIds.length; i++) {
    var id = hostedIds[i]
    if (category === "all") { result.push(id); continue }
    if (classify(id, pinnedIds, hiddenIds) === category) result.push(id)
  }
  return result
}

// "Add a widget to host" list for the manage popup: every registered bar
// widget minus ourselves minus what's already hosted minus EXCLUDED_WIDGET_IDS,
// sorted by display name.
function candidateWidgets(availableIds, metadataForFn, hostedIds, ownId) {
  var out = []
  for (var i = 0; i < availableIds.length; i++) {
    var id = availableIds[i]
    if (id === ownId) continue
    if (hostedIds.indexOf(id) !== -1) continue
    if (EXCLUDED_WIDGET_IDS.indexOf(id) !== -1) continue
    var meta = metadataForFn(id) || {}
    out.push({ id: id, displayName: meta.displayName || id, category: meta.category || "" })
  }
  out.sort(function(a, b) {
    if (a.displayName < b.displayName) return -1
    if (a.displayName > b.displayName) return 1
    return 0
  })
  return out
}

// Where to put a widget back when un-hosting it, if the caller doesn't pin
// down a section explicitly. `manifest` is the widget's installedPlugins[id]
// entry, or null/undefined if unavailable — caller is responsible for the
// defensive bar.shell.pluginRegistry null-checks before calling this.
function defaultSectionForManifest(manifest) {
  var section = manifest && manifest.barWidget ? String(manifest.barWidget.defaultSection || "") : ""
  return ["left", "center", "right"].indexOf(section) !== -1 ? section : "right"
}

// Deliberately not Array.isArray(list) + .filter(): values read back through
// QML's live property system (settings.hosted, as opposed to a value fresh
// out of JSON.parse inside a mutateShellConfig callback) can arrive boxed as
// a QML sequence type rather than a native JS Array — array-like (.length,
// indexing, JSON.stringify-able) but Array.isArray() false for it, which
// made every real settings read silently fall through to the empty branch
// here despite the data being correct. Duck-type on .length instead.
function normalizeIds(list) {
  if (!list || typeof list.length !== "number") return []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var x = list[i]
    if (typeof x === "string" && x.length > 0) out.push(x)
  }
  return out
}

// Same live-QML-property caution as normalizeIds, for the id->section map:
// only copy over well-formed string values into a fresh plain object.
function normalizeSectionMap(map) {
  var out = {}
  if (!map || typeof map !== "object") return out
  for (var k in map) {
    var v = map[k]
    if (typeof v === "string" && ["left", "center", "right"].indexOf(v) !== -1) out[k] = v
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    entryId: entryId,
    ensureShape: ensureShape,
    findLayoutLocation: findLayoutLocation,
    findPluginsLocation: findPluginsLocation,
    findOwnEntry: findOwnEntry,
    hostWidget: hostWidget,
    unhostWidget: unhostWidget,
    togglePin: togglePin,
    toggleHide: toggleHide,
    classify: classify,
    bucket: bucket,
    candidateWidgets: candidateWidgets,
    defaultSectionForManifest: defaultSectionForManifest,
    normalizeIds: normalizeIds,
    normalizeSectionMap: normalizeSectionMap
  }
}
