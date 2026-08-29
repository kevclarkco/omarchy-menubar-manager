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

  // Bar.qml's ModuleSlot draws an underline under whichever widget's popout
  // is active (bar.activePopout, which opening the manage popup sets to
  // this widget), sized by default to 55% of the *whole slot's* width. That
  // slot can be anywhere from 27px (collapsed) to well over 100px (drawer
  // open, several hosted icons showing) — nothing to do with how wide the
  // glyph that actually opens the popup is, so the mark ballooned across
  // several drawer icons instead of marking just the glyph. Declaring this
  // is the sanctioned override (see panelIndicatorExtent in Bar.qml): any
  // widget can report the width it actually wants the mark drawn at.
  readonly property real openPanelIndicatorWidth: expandIcon.width

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var hostedIds: MenubarModel.normalizeIds(settings.hosted)
  readonly property var pinnedIds: MenubarModel.normalizeIds(settings.pinned)
  readonly property var hiddenIds: MenubarModel.normalizeIds(settings.hidden)
  readonly property var drawerIds: MenubarModel.bucket("drawer", hostedIds, pinnedIds, hiddenIds)
  readonly property var pinnedBucketIds: MenubarModel.bucket("pinned", hostedIds, pinnedIds, hiddenIds)

  // Host/un-host destroy and recreate this widget mid-click (see
  // hostWidgetById below), taking any open manage popup down with it.
  // MenubarModel flags own.popupOpen in that same atomic write so the fresh
  // instance can restore it here; persist() writes it back out without
  // popupOpen, a settings-only change Bar.qml can patch in place rather than
  // rebuilding again — so the reopened popup then stays open for the next
  // click instead of vanishing every time.
  onSettingsChanged: {
    if (settings.popupOpen === true) {
      root.managePopupOpen = true
      // Deferred, not immediate: this fires while the structural rebuild
      // that just recreated this very instance is still settling (same
      // reason Bar.qml's own ModuleSlot defers injectProps via
      // Qt.callLater). Clearing synchronously here landed a second config
      // write on top of one still resolving, which is what triggered a
      // "binding loop detected for barConfig" warning during testing.
      Qt.callLater(function() { root.persist(root.hostedIds, root.pinnedIds, root.hiddenIds) })
    }
  }

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

  // {widgetId: true} for every hosted widget whose own panel is currently
  // open. Most first-party/plugin widgets expose `opened` via qs.Ui.Panel's
  // PanelController — a purely local bool, NOT wired through
  // bar.activePopout/requestPopout the way PopupCard is, so that mechanism
  // can't be reused here; each hosted instance's own openedChanged has to be
  // watched directly. Kept as an id-keyed map (not a count) so a slot being
  // destroyed mid-open — host/un-host's own destructive rebuild — can't
  // leave a stale "something's open" entry with nothing left to clear it.
  property var openHostedPanels: ({})
  readonly property bool anyHostedPanelOpen: Object.keys(openHostedPanels).length > 0

  // A hosted widget's panel window, once open, physically covers this same
  // screen region — so the moment it opens, hover on the drawer genuinely
  // (not spuriously) reads false, and the moment it closes, hover genuinely
  // reads true again (the cursor really is sitting wherever the close-click
  // landed, right over the now-uncovered drawer). Both readings are
  // accurate; neither reflects the user's actual intent to leave. Debouncing
  // raw hover can't fix that — it's not noise to filter, it's a real signal
  // with the wrong meaning at that instant. So anyHostedPanelOpen going
  // false must never by itself trigger a visible collapse: combine it with
  // (already hover-debounced) `expanded` and only let the combined signal
  // collapse the drawer after it's stayed unwanted for a sustained beat,
  // while still expanding it immediately the moment either turns true.
  readonly property bool wantDrawerOpen: expanded || anyHostedPanelOpen
  property bool drawerShown: false

  onWantDrawerOpenChanged: {
    if (wantDrawerOpen) {
      drawerCloseTimer.stop()
      root.drawerShown = true
    } else {
      drawerCloseTimer.restart()
    }
  }

  Timer {
    id: drawerCloseTimer
    interval: 450
    onTriggered: root.drawerShown = false
  }

  function setHostedPanelOpen(id, isOpen) {
    if (!!openHostedPanels[id] === !!isOpen) return
    var next = {}
    for (var k in openHostedPanels) next[k] = openHostedPanels[k]
    if (isOpen) next[id] = true
    else delete next[id]
    openHostedPanels = next
  }

  component HostedWidgetSlot: Loader {
    id: hostedLoader
    required property var modelData
    // True for the collapsible drawer bucket, false for the always-visible
    // pinned row — only drawer items get torn down while collapsed, below.
    property bool gatedByDrawer: false
    readonly property string widgetId: String(modelData)
    // clip:true on drawerClip only hides this widget's *paint* — the loaded
    // item, and every WidgetButton-style control nested inside it, keeps its
    // normal size and stays registered in bar.clickTargets (a bar-wide list,
    // unscoped to any one widget's own slot). Bar.qml's click routing does a
    // geometric hit-test against that whole list, so a click on a completely
    // unrelated bar widget could land on a hidden-but-still-registered
    // hosted widget instead — confirmed live: clicking Network opened
    // LocalSend's panel while the drawer was collapsed. Setting opacity/
    // visible on the top-level loaded item doesn't fix this: the actual
    // registered target is typically a control nested inside it (its own
    // local `opacity`/`visible` stay whatever they were regardless of an
    // ancestor's), so the eligibility checks in moduleTargetClickable()
    // never see the change. The only reliable fix is to stop the widget (and
    // everything nested in it) existing at all while collapsed: gating
    // `active` on drawerShown fully destroys it, which correctly runs each
    // control's own Component.onDestruction → unregisterClickTarget cleanup.
    // It reloads fresh the next time the drawer is hovered open, before
    // anything inside it is reachable to click.
    active: (!gatedByDrawer || root.drawerShown)
      && !!(root.bar && root.bar.barWidgetRegistry && root.bar.barWidgetRegistry.has(widgetId))
    sourceComponent: active ? root.bar.barWidgetRegistry.widgets[widgetId].component : null
    onLoaded: root.injectHostedProps(item, widgetId)

    // "opened" isn't declared on every widget (e.g. a plain BarWidget with
    // no popup, like a clock) — ignoreUnknownSignals lets those load here
    // without a warning; they just never report open.
    Connections {
      target: hostedLoader.item
      ignoreUnknownSignals: true
      function onOpenedChanged() {
        root.setHostedPanelOpen(hostedLoader.widgetId, hostedLoader.item.opened === true)
      }
    }

    onItemChanged: root.setHostedPanelOpen(widgetId, item && item.opened === true)
    Component.onDestruction: root.setHostedPanelOpen(widgetId, false)

    // Hosted widgets aren't real ModuleSlots, so they never get Bar.qml's
    // own "this widget's panel is open" underline — reproduce it here,
    // matching its look (Color.accent, same 55%-of-width sizing) and
    // per-icon, driven by the same openHostedPanels tracking already used
    // to keep the drawer open while a hosted panel is up.
    Rectangle {
      id: openIndicator
      readonly property int inset: Style.space(2)
      visible: opacity > 0
      opacity: root.openHostedPanels[hostedLoader.widgetId] === true ? 0.9 : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
      width: Math.max(Style.space(10), Math.round(parent.width * 0.55))
      height: Style.space(2)
      anchors.horizontalCenter: parent.horizontalCenter
      y: (root.bar && root.bar.position === "top") ? parent.height - height - inset : inset
      z: 50

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }
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

      // Filters short, unrelated hover blips (e.g. an unrelated widget's own
      // panel opening/closing elsewhere on the bar momentarily disturbing
      // what Hyprland reports here) before they ever reach root.expanded.
      // The false-then-true dance a hosted panel's own open/close produces
      // is a longer, *genuine* hover change, not blip noise — that case is
      // handled separately below via wantDrawerOpen/drawerCloseTimer.
      HoverHandler {
        id: drawerHover
        onHoveredChanged: hoverSettleTimer.restart()
      }

      Timer {
        id: hoverSettleTimer
        interval: 150
        onTriggered: root.expanded = drawerHover.hovered
      }

      BarIconButton {
        id: expandIcon
        bar: root.bar
        width: implicitWidth
        height: implicitHeight
        // Anchored to the right (not left) so drawerClip below grows
        // leftward, away from the glyph, instead of pushing it — see the
        // comment on drawerClip for why that keeps the glyph stationary
        // under the cursor as the drawer opens.
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: ""
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
        // Right edge pinned to the glyph, growing leftward as width
        // increases (not anchors.left, which would grow rightward and push
        // the glyph — and everything after it in the bar's right-anchored
        // row — further left to compensate, sliding the glyph out from
        // under whatever's hovering it).
        anchors.right: expandIcon.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.drawerShown ? drawerContent.implicitWidth : 0
        height: root.barSize
        clip: true

        Behavior on width {
          NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
        }

        Row {
          id: drawerContent
          // Pinned to this clip's right edge (nearest the glyph) rather
          // than the default left-aligned x:0, so revealed icons unfurl
          // outward from next to the glyph as the clip widens, instead of
          // from its far (left) edge inward.
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.itemGap

          Repeater {
            model: root.drawerIds
            HostedWidgetSlot { gatedByDrawer: true }
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

  // A separate coordinator object for the manage popup's owner, instead of
  // root itself. Bar.qml's ModuleSlot lights up its "panel open" underline
  // when bar.activePopout === slot.activeItem — and slot.activeItem is this
  // widget's own root. Using root as PopupCard's owner also makes it the
  // requestPopout coordinatorKey, so opening the manage popup made that
  // comparison match and drew the mark. A distinct object still gets
  // PopupCard's outside-click auto-close (which calls owner.close()) and
  // still participates correctly in cross-widget popout exclusivity, but
  // no longer equals slot.activeItem, so the mark never lights up for it.
  QtObject {
    id: managePopupCoordinator
    function close() { root.close() }
  }

  PopupCard {
    id: managePopup
    anchorItem: root
    owner: managePopupCoordinator
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
            anchors.right: pinBtn.left
            anchors.rightMargin: Style.space(8)
            text: hostedRow.displayName
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            id: pinBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: hideBtn.left
            anchors.rightMargin: Style.space(6)
            text: hostedRow.isPinned ? "Unpin" : "Pin"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            fontSize: Style.font.bodySmall
            onClicked: root.togglePin(hostedRow.itemId)
          }

          Button {
            id: hideBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: unhostBtn.left
            anchors.rightMargin: Style.space(6)
            text: hostedRow.isHidden ? "Show" : "Hide"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            fontSize: Style.font.bodySmall
            onClicked: root.toggleHide(hostedRow.itemId)
          }

          Button {
            id: unhostBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            text: "Remove"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            fontSize: Style.font.bodySmall
            onClicked: root.unhostWidgetById(hostedRow.itemId)
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
            text: "Add"
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
