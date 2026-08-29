import QtQuick
import qs.Commons
import qs.Ui
import "MenubarModel.js" as MenubarModel

// Bartender/Ice-style manager for the Omarchy bar: hosts other registered
// bar widgets inside a hover-to-reveal drawer. "Hosting" a widget relocates
// its shell.json entry from bar.layout.<section> into the top-level
// config.plugins[] array (see MenubarModel.hostWidget) — that keeps
// PluginRegistry.isEnabled() true for it (component stays registered in
// barWidgetRegistry, its own settings-persistence keeps working) without
// Bar.qml auto-rendering a ModuleSlot for it, since Bar.qml only builds
// slots from bar.layout.*. We then Loader-instantiate its Component
// ourselves from bar.barWidgetRegistry.
//
// v1 scope: horizontal bar only (root.vertical branch not implemented).
// Hosted widgets are NOT registered in bar.moduleSlots, so Hyprland
// hotkeys / `omarchy toggle <id>` bound to a hosted widget won't find it
// while hosted — clicking it inside the drawer still opens its own panel
// fine, only external hotkey-summon is affected. See plan doc for why this
// is an acceptable v1 tradeoff.
BarWidget {
  id: root
  moduleName: "kc.menubar-manager"

  property bool expanded: false
  property bool managePopupOpen: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var hostedIds: MenubarModel.normalizeIds(settings.hosted)
  readonly property var pinnedIds: MenubarModel.normalizeIds(settings.pinned)
  readonly property var hiddenIds: MenubarModel.normalizeIds(settings.hidden)
  readonly property var drawerIds: MenubarModel.bucket("drawer", hostedIds, pinnedIds, hiddenIds)
  readonly property var pinnedBucketIds: MenubarModel.bucket("pinned", hostedIds, pinnedIds, hiddenIds)

  readonly property int itemGap: Style.space(4)
  readonly property int animationDuration: 600

  function persist(nextHosted, nextPinned, nextHidden) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    root.bar.shell.updateEntryInline(root.moduleName, {
      id: root.moduleName,
      hosted: nextHosted,
      pinned: nextPinned,
      hidden: nextHidden
    })
  }

  // PopupCard's outside-click dismissal calls owner.close() when the owner
  // defines one; without it, it falls back to directly assigning
  // `root.open = false` on itself, which permanently breaks the one-way
  // `open: root.managePopupOpen` binding below (a plain assignment
  // overwrites a QML binding). Omitting this is why the popup opened once
  // and then stopped responding to every click after the first dismissal.
  function close() {
    root.managePopupOpen = false
  }

  function togglePin(id) {
    var next = MenubarModel.togglePin(pinnedIds, hiddenIds, id)
    persist(hostedIds, next.pinned, next.hidden)
  }

  function toggleHide(id) {
    var next = MenubarModel.toggleHide(pinnedIds, hiddenIds, id)
    persist(hostedIds, next.pinned, next.hidden)
  }

  function hostWidgetById(id) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.mutateShellConfig !== "function") return
    // Host/un-host are structural bar.layout changes, which Bar.qml can't
    // diff against a settings-only edit — it rebuilds every module slot on
    // the bar, destroying and recreating this widget (and its open
    // PopupCard) outright. If the popup's HyprlandFocusGrab is still active
    // when that destruction happens, Hyprland can be left holding a grab for
    // a window that no longer exists, which reads as "clicks stopped
    // working" well beyond just this widget. Closing the popup first lets
    // the grab release cleanly before anything gets torn down.
    root.managePopupOpen = false
    root.bar.shell.mutateShellConfig(function(config) {
      MenubarModel.hostWidget(config, root.moduleName, id)
    })
  }

  function unhostWidgetById(id) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.mutateShellConfig !== "function") return
    root.managePopupOpen = false
    // Read-only lookup of the widget's own manifest default section. Reached
    // via bar.shell.pluginRegistry, an incidental (not documented) channel —
    // defensively guarded, never used for writes. See plan doc Risk #1.
    var registry = root.bar.shell.pluginRegistry
    var manifest = registry && registry.installedPlugins ? registry.installedPlugins[id] : null
    var section = MenubarModel.defaultSectionForManifest(manifest)
    root.bar.shell.mutateShellConfig(function(config) {
      MenubarModel.unhostWidget(config, root.moduleName, id, section)
    })
  }

  // A hosted widget's own inline settings now live in config.plugins[]
  // rather than a bar.layout entry, so it needs its own read path — mirrors
  // updateEntryInline's own {id, ...rest} reconstruction, in reverse.
  function pluginEntrySettings(id) {
    var cfg = root.bar && root.bar.shell ? root.bar.shell.shellConfig : null
    // Not Array.isArray(cfg.plugins): this is live QML-sourced data (same
    // property-var indirection chain that boxed settings.hosted as a QML
    // sequence type rather than a native Array — see normalizeIds' comment
    // in MenubarModel.js), so duck-type on .length instead.
    if (!cfg || !cfg.plugins || typeof cfg.plugins.length !== "number") return {}
    for (var i = 0; i < cfg.plugins.length; i++) {
      if (cfg.plugins[i] && String(cfg.plugins[i].id) === id) {
        var s = {}
        for (var k in cfg.plugins[i]) if (k !== "id") s[k] = cfg.plugins[i][k]
        return s
      }
    }
    return {}
  }

  function candidateWidgets() {
    if (!root.bar || !root.bar.barWidgetRegistry) return []
    var registry = root.bar.barWidgetRegistry
    var ids = registry.availableIds()
    return MenubarModel.candidateWidgets(ids, function(id) { return registry.metadataFor(id) }, hostedIds, root.moduleName)
  }

  // bar/moduleName are fixed for a hosted instance's lifetime, but settings
  // must stay live (e.g. the hosted widget's own settings panel writing a
  // new value) — Qt.binding keeps it re-evaluating on every shellConfig
  // change, same effect Bar.qml gets from ModuleSlot's onModuleSettingsChanged.
  function injectHostedProps(item, id) {
    if (!item) return
    if ("bar" in item) item.bar = root.bar
    if ("moduleName" in item) item.moduleName = id
    if ("settings" in item) item.settings = Qt.binding(function() { return root.pluginEntrySettings(id) })
  }

  component HostedWidgetSlot: Loader {
    id: hostedLoader
    required property var modelData
    readonly property string widgetId: String(modelData)
    active: !!(root.bar && root.bar.barWidgetRegistry && root.bar.barWidgetRegistry.has(widgetId))
    sourceComponent: active ? root.bar.barWidgetRegistry.widgets[widgetId].component : null
    onLoaded: root.injectHostedProps(item, widgetId)
  }

  // Always visible (unlike the tray, which hides itself when empty) — this
  // widget IS the entry point for adding widgets to host, so the chevron
  // must stay reachable even with nothing hosted yet.
  visible: true
  clip: false
  implicitWidth: contentRow.implicitWidth
  implicitHeight: root.barSize

  Row {
    id: contentRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.itemGap

    Item {
      id: drawerArea
      width: expandIcon.implicitWidth + drawerClip.width
      height: root.barSize

      HoverHandler {
        onHoveredChanged: root.expanded = hovered
      }

      BarIconButton {
        id: expandIcon
        bar: root.bar
        width: implicitWidth
        height: implicitHeight
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        // Either button opens the manage popup — unlike the system tray
        // (whose chevron has no popup of its own to open on left-click),
        // this widget's only purpose when nothing is hosted yet is to be a
        // discoverable entry point, so don't require right-click specifically.
        onPressed: function(button) {
          root.managePopupOpen = !root.managePopupOpen
        }
      }

      Item {
        id: drawerClip
        anchors.left: expandIcon.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.expanded ? drawerContent.implicitWidth : 0
        height: root.barSize
        clip: true

        Behavior on width {
          NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
        }

        Row {
          id: drawerContent
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.itemGap

          Repeater {
            model: root.drawerIds
            HostedWidgetSlot {}
          }
        }
      }
    }

    Row {
      id: pinnedRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.itemGap

      Repeater {
        model: root.pinnedBucketIds
        HostedWidgetSlot {}
      }
    }
  }

  PopupCard {
    id: managePopup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.managePopupOpen
    contentWidth: managePopup.fittedContentWidth(Style.space(320))
    contentHeight: managePopup.fittedContentHeight(manageColumn.implicitHeight)

    Column {
      id: manageColumn
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        text: "Hosted widgets"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        visible: root.hostedIds.length === 0
        text: "Nothing hosted yet — add a widget below."
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: true
      }

      Repeater {
        model: root.hostedIds
        delegate: Item {
          id: hostedRow
          required property var modelData
          readonly property string itemId: String(modelData)
          readonly property bool isPinned: root.pinnedIds.indexOf(itemId) !== -1
          readonly property bool isHidden: root.hiddenIds.indexOf(itemId) !== -1
          readonly property var meta: root.bar && root.bar.barWidgetRegistry
            ? root.bar.barWidgetRegistry.metadataFor(itemId) : null
          readonly property string displayName: meta && meta.displayName ? meta.displayName : itemId

          width: manageColumn.width
          implicitHeight: Style.space(28)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: unhostBtn.left
            anchors.rightMargin: Style.space(8)
            text: hostedRow.displayName
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            id: unhostBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: hideBtn.left
            anchors.rightMargin: Style.space(6)
            text: "Remove"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            fontSize: Style.font.bodySmall
            onClicked: root.unhostWidgetById(hostedRow.itemId)
          }

          Button {
            id: hideBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: pinBtn.left
            anchors.rightMargin: Style.space(6)
            text: hostedRow.isHidden ? "Show" : "Hide"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            fontSize: Style.font.bodySmall
            onClicked: root.toggleHide(hostedRow.itemId)
          }

          Button {
            id: pinBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            text: hostedRow.isPinned ? "Unpin" : "Pin"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            fontSize: Style.font.bodySmall
            onClicked: root.togglePin(hostedRow.itemId)
          }
        }
      }

      Item { width: 1; height: Style.space(6) }

      Text {
        text: "Add a widget"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      // Recomputed each time the popup opens rather than kept live — the
      // catalogue of registered widgets changes rarely enough that this is
      // simpler than wiring a reactive dependency on barWidgetRegistry.revision.
      Repeater {
        model: root.managePopupOpen ? root.candidateWidgets() : []
        delegate: Item {
          id: candidateRow
          required property var modelData

          width: manageColumn.width
          implicitHeight: Style.space(26)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: addBtn.left
            anchors.rightMargin: Style.space(8)
            text: candidateRow.modelData.displayName
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            id: addBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            text: "Host"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            fontSize: Style.font.bodySmall
            onClicked: root.hostWidgetById(candidateRow.modelData.id)
          }
        }
      }
    }
  }
}
