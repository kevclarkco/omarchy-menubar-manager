import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Extracted out of Bar.qml (rather than kept as an inline `component
// ModuleSlot: Item {}`) solely to break a cycle: DrawerWidget needs to
// instantiate ModuleSlot for each hosted widget, and ModuleSlot needs to
// instantiate DrawerWidget for the drawer glyph itself (see drawerLoader
// below) — QML's inline-component syntax rejects that as "Inline components
// form a cycle!" even though nothing here is actually recursive at runtime
// (a drawer glyph is never itself hosted inside its own drawer). Ordinary
// same-directory file resolution has no such restriction, so both moved out
// to their own files (see DrawerWidget.qml) instead.
//
// Everything that used to be reached via the enclosing Item's `id: root`
// (this was nested directly inside Bar.qml) now comes through this explicit
// `bar` property instead — Bar.qml passes `bar: root` at every place it
// instantiates this type.
Item {
  id: slot

  required property var bar
  required property var entry
  property string region: ""
  readonly property string moduleName: bar.entryId(entry)
  readonly property var moduleSettings: bar.entrySettings(entry)
  // The drawer glyph is a render-time-only sentinel (see
  // bar.sectionEntriesForRender) — never a real barWidgetRegistry entry or
  // custom module, so it's excluded from every one of those lookups below
  // and given its own loader instead.
  readonly property bool isDrawerGlyph: moduleName === bar.drawerEntryId
  readonly property string customType: isDrawerGlyph ? "" : bar.customModuleType(entry)
  readonly property var registryMetadata: isDrawerGlyph ? null
    : bar.barWidgetRegistry.metadataFor(bar.canonicalWidgetId(moduleName))
  readonly property bool firstParty: registryMetadata && registryMetadata.firstParty === true
  readonly property string pluginApiId: registered ? bar.canonicalWidgetId(moduleName) : "bar-entry:" + moduleName
  // Re-evaluate when the registry mutates (Component reference changes,
  // plugin enabled/disabled, etc.). Reading the `widgets` property creates
  // the binding dependency — the wrapped function call alone wouldn't.
  readonly property var registryComponent: {
    if (isDrawerGlyph) return null
    var w = bar.barWidgetRegistry.widgets
    if (customType) return null
    var registryName = bar.canonicalWidgetId(moduleName)
    return w[registryName] ? w[registryName].component : null
  }
  readonly property bool qmlCustom: !isDrawerGlyph && customType === "qml"
  readonly property bool commandCustom: !isDrawerGlyph && customType === "command"
  readonly property bool registered: !isDrawerGlyph && registryComponent !== null
  readonly property var activeItem: {
    if (isDrawerGlyph) return drawerLoader.item
    if (registered) return registryLoader.item
    if (qmlCustom) return qmlLoader.item
    return componentLoader.item
  }
  readonly property bool hovered: moduleHover.hovered
  readonly property bool dragSource: bar.barDragSource === slot
  readonly property bool panelOpen: bar.activePopout === slot.activeItem
  // Modules bigger than the mark they want (a text label in a padded slot,
  // a multi-line stack on a vertical bar) can say how long the open-panel
  // dot should be along the bar, so it tracks what the module paints
  // instead of a fraction of whatever slot it happens to fill.
  readonly property real panelIndicatorExtent: {
    var key = bar.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
    var hint = activeItem && key in activeItem ? activeItem[key] : undefined
    if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
    return Math.max(Style.space(10), Math.round((bar.vertical ? slot.height : slot.width) * 0.55))
  }
  implicitWidth: activeItem && activeItem.visible ? (bar.vertical ? bar.barSize : activeItem.implicitWidth) : 0
  implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
  width: implicitWidth
  height: implicitHeight
  z: modulePointer.dragging ? 100 : 0

  Component.onCompleted: {
    bar.registerModuleSlot(slot)
    // Loaded by URL (Loader.setSource), not a static `DrawerWidget {}` type
    // reference: ModuleSlot instantiates DrawerWidget (for the drawer
    // glyph's own slot) and DrawerWidget instantiates ModuleSlot (for each
    // hosted widget) — Qt's QML type resolver rejects that as a cyclic
    // dependency between the two files even though nothing is actually
    // recursive at runtime (a drawer glyph is never itself hosted inside
    // its own drawer). setSource's second argument satisfies DrawerWidget's
    // `required property var bar` at construction time, the same as an
    // inline `DrawerWidget { bar: slot.bar }` would.
    if (slot.isDrawerGlyph)
      drawerLoader.setSource(Qt.resolvedUrl("DrawerWidget.qml"), { bar: slot.bar })
  }
  Component.onDestruction: {
    if (bar.barDragSource === slot) bar.clearBarDrag()
    bar.unregisterModuleSlot(slot)
  }

  HoverHandler { id: moduleHover }

  BorderSurface {
    visible: slot.dragSource
    anchors.fill: parent
    anchors.margins: Style.space(1)
    color: bar.transparent ? "transparent" : bar.background
    borderSpec: Border.flat(bar.barForeground, 1)
    radius: Math.min(Style.cornerRadius, height / 2)
    opacity: bar.transparent ? 0.22 : 0.32
  }

  Loader {
    id: drawerLoader
    anchors.fill: parent
    opacity: slot.dragSource ? 0.22 : 1.0
    onLoaded: {
      slot.injectProps()
      Qt.callLater(slot.injectProps)
    }
  }

  Loader {
    id: componentLoader
    active: !slot.isDrawerGlyph && !slot.qmlCustom && !slot.registered
    sourceComponent: slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent
    anchors.fill: parent
    opacity: slot.dragSource ? 0.22 : 1.0
    onLoaded: {
      slot.injectProps()
      Qt.callLater(slot.injectProps)
    }
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }

  Loader {
    id: registryLoader
    active: slot.registered
    sourceComponent: slot.registered ? slot.registryComponent : null
    anchors.fill: parent
    opacity: slot.dragSource ? 0.22 : 1.0
    onLoaded: {
      slot.injectProps()
      Qt.callLater(slot.injectProps)
    }
  }

  Loader {
    id: qmlLoader
    active: slot.qmlCustom
    source: slot.qmlCustom ? bar.customModuleSource(slot.entry) : ""
    anchors.fill: parent
    opacity: slot.dragSource ? 0.22 : 1.0
    onLoaded: {
      slot.injectProps()
      Qt.callLater(slot.injectProps)
    }
  }

  Rectangle {
    id: openPanelIndicator

    readonly property int inset: Style.space(2)

    visible: opacity > 0
    opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
    color: Color.accent
    radius: Math.min(width, height) / 2
    width: bar.vertical ? Style.space(2) : slot.panelIndicatorExtent
    height: bar.vertical ? slot.panelIndicatorExtent : Style.space(2)
    // The mark sits on the module's inner edge — the one facing the
    // desktop — so it underlines a top bar, overlines a bottom one, and
    // points inward from a left or right one. It reads as pointing at the
    // panel that opens on that side.
    x: bar.vertical
      ? (bar.position === "left" ? parent.width - width - inset : inset)
      : Math.round((parent.width - width) / 2)
    y: bar.vertical
      ? Math.round((parent.height - height) / 2)
      : (bar.position === "top" ? parent.height - height - inset : inset)
    z: 50

    Behavior on opacity {
      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }
  }

  MouseArea {
    id: modulePointer

    property bool dragging: false
    property bool suppressClick: false
    property real pressedX: 0
    property real pressedY: 0
    readonly property bool canReorder: bar.shell && typeof bar.shell.mutateShellConfig === "function"
    readonly property real dragThreshold: Style.space(4)

    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    enabled: slot.visible && slot.width > 0 && slot.height > 0
    propagateComposedEvents: true
    cursorShape: bar.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor
    // Do not assign drag.target here: ModuleSlot is owned by Row/Column
    // positioners, and mutating slot.x/slot.y can leave stale offsets that
    // make neighboring modules overlap after a small aborted drag.

    onPressed: function(mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
      bar.clearBarDrag()
    }

    onPositionChanged: function(mouse) {
      if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

      var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
      if (distance >= dragThreshold) {
        if (!dragging) {
          bar.barDragWindow = bar.targetWindow(slot.activeItem) || bar.targetWindow(slot)
          bar.barDragScreen = bar.barDragWindow ? bar.barDragWindow.screen : null
          bar.barDragOffsetX = pressedX
          bar.barDragOffsetY = pressedY
          bar.captureBarDragGhost(slot)
          bar.barDragSource = slot
        }
        dragging = true
        bar.hideTooltip(slot.activeItem)
      }

      if (dragging) {
        var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
        var screenPoint = bar.barDragScreenPoint(scenePoint)
        bar.barDragSceneX = scenePoint.x
        bar.barDragSceneY = scenePoint.y
        bar.barDragScreenX = screenPoint.x
        bar.barDragScreenY = screenPoint.y

        var drop = bar.moduleDropAtScene(scenePoint, slot)
        bar.barDragTarget = drop ? drop.slot : null
        bar.barDragAfter = drop ? drop.after : false
        bar.barDragTargetGeometry = drop ? bar.dropMarkerRect(drop.slot, drop.after) : null
      }
    }

    onReleased: function(mouse) {
      var wasDragging = dragging
      var targetSlot = bar.barDragTarget
      var afterTarget = bar.barDragAfter

      if (wasDragging) suppressClick = true

      dragging = false
      bar.clearBarDrag()

      if (wasDragging && targetSlot) {
        bar.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
        mouse.accepted = true
      } else if (!wasDragging) {
        mouse.accepted = false
      }
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      bar.clearBarDrag()
    }

    onClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
        return
      }

      if (!bar.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
    }
  }

  onActiveItemChanged: Qt.callLater(injectProps)
  onModuleSettingsChanged: injectProps()

  function injectProps() {
    var target = activeItem
    if (!target) return
    // The drawer glyph's own `bar` was already set correctly at construction
    // (setSource's initial properties, in Component.onCompleted above) — it
    // needs full internal access, not the narrow third-party facade every
    // other widget gets here, and isn't read from `registryMetadata` (null
    // for the sentinel entry) so `firstParty` can't tell the two apart.
    if (!isDrawerGlyph && "bar" in target) target.bar = firstParty
      ? bar : bar.pluginBarApiFor(pluginApiId, moduleName, registered)
    if ("moduleName" in target) target.moduleName = moduleName
    if ("settings" in target) target.settings = moduleSettings
  }

  Component {
    id: customCommandModuleComponent
    CustomCommandModule { entry: slot.entry }
  }

  component CustomCommandModule: WidgetButton {
    id: customRoot

    required property var entry
    readonly property string moduleName: slot.bar.entryId(entry)
    readonly property var settings: slot.bar.entrySettings(entry)
    property string outputText: ""
    property string outputTooltip: ""
    property bool outputActive: false

    function setting(name, fallback) {
      var value = settings ? settings[name] : undefined
      return value === undefined || value === null ? fallback : value
    }

    function update(raw) {
      var data = Util.parseModuleJson(raw)
      var klass = data.class || data.alt || ""

      outputText = data.text || String(raw || "").trim()
      outputTooltip = data.tooltip || String(setting("tooltip", ""))
      outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
    }

    bar: slot.bar
    text: outputText || String(setting("text", ""))
    tooltipText: outputTooltip || String(setting("tooltip", ""))
    active: outputActive
    keepSpace: setting("keepSpace", false) === true
    horizontalMargin: Number(setting("horizontalMargin", 7.5))
    verticalPadding: Number(setting("verticalPadding", 6))
    fontSize: Number(setting("fontSize", 12))

    onPressed: function(button) {
      var command = ""
      if (button === Qt.RightButton)
        command = String(setting("onRightClick", ""))
      else if (button === Qt.MiddleButton)
        command = String(setting("onMiddleClick", ""))
      else
        command = String(setting("onClick", ""))

      if (command) slot.bar.run(command)
    }

    Process {
      id: customProc
      command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: customRoot.update(text)
      }
    }

    Timer {
      interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
      running: String(customRoot.setting("exec", "")) !== ""
      repeat: true
      triggeredOnStart: true
      onTriggered: slot.bar.runProcess(customProc)
    }
  }
}
