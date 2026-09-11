import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Extracted out of Bar.qml as its own file (rather than kept as an inline
// `component DrawerWidget: Item {}`) for the same reason as ModuleSlot.qml —
// see the comment at the top of that file for the cycle this breaks.
//
// Hosts other bar widgets in a hover-reveal drawer, Bartender/Ice style.
// Rendered by ModuleSlot's isDrawerGlyph branch, at the position
// bar.sectionEntriesForRender splices its sentinel entry into. Reuses the
// real ModuleSlot component for every hosted widget, so a hosted widget gets
// identical rendering, click routing, drag handling, tooltip, and
// open-panel indicator to one sitting directly in the strip — no
// hand-rolled widget instantiation needed, unlike a plugin outside the bar,
// which has no access to ModuleSlot at all.
Item {
  id: drawer

  required property var bar

  property bool expanded: false
  property bool managePopupOpen: false
  readonly property var hostedIds: bar.drawerHostedIds()
  readonly property var visibleEntries: bar.drawerVisibleEntries()
  readonly property var visibleIds: visibleEntries.map(function(e) { return bar.entryId(e) })
  readonly property int animationDuration: 600
  readonly property int itemGap: Style.space(4)

  // A hosted widget's own popup counts as "wanting the drawer open" the
  // same as hovering it directly — otherwise opening one, then moving the
  // pointer to actually use it, would collapse the drawer out from under
  // an open popup.
  function anyHostedPanelOpen() {
    if (!bar.activePopout) return false
    for (var i = 0; i < bar.moduleSlots.length; i++) {
      var slot = bar.moduleSlots[i]
      if (slot && slot.activeItem === bar.activePopout
          && hostedIds.indexOf(slot.moduleName) !== -1) return true
    }
    return false
  }

  readonly property bool wantOpen: expanded || anyHostedPanelOpen()
  property bool drawerShown: false

  onWantOpenChanged: {
    if (wantOpen) {
      drawerCloseTimer.stop()
      drawer.drawerShown = true
    } else {
      drawerCloseTimer.restart()
    }
  }

  Timer {
    id: drawerCloseTimer
    interval: 450
    onTriggered: drawer.drawerShown = false
  }

  // Always visible, unlike the tray (which hides itself when empty): this
  // widget is the entry point for adding widgets to host, so the glyph
  // must stay reachable even with nothing hosted yet.
  visible: true
  implicitWidth: bar.vertical ? bar.barSize : contentLoader.implicitWidth
  implicitHeight: bar.vertical ? contentLoader.implicitHeight : bar.barSize

  Loader {
    id: contentLoader
    anchors.fill: parent
    sourceComponent: bar.vertical ? verticalLayout : horizontalLayout
  }

  Component {
    id: horizontalLayout

    Item {
      id: layoutRoot
      implicitWidth: expandIcon.implicitWidth + drawerClip.width
      implicitHeight: bar.barSize

      HoverHandler {
        id: drawerHover
        onHoveredChanged: hoverSettleTimer.restart()
      }

      Timer {
        id: hoverSettleTimer
        interval: 150
        onTriggered: drawer.expanded = drawerHover.hovered
      }

      BarIconButton {
        id: expandIcon
        bar: drawer.bar
        width: implicitWidth
        height: implicitHeight
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "\uf141"
        onPressed: function(button) {
          drawer.managePopupOpen = !drawer.managePopupOpen
        }
      }

      Item {
        id: drawerClip
        anchors.right: expandIcon.left
        anchors.verticalCenter: parent.verticalCenter
        width: drawer.drawerShown ? drawerContent.implicitWidth : 0
        height: bar.barSize
        clip: true

        Behavior on width {
          NumberAnimation { duration: drawer.animationDuration; easing.type: Easing.OutCubic }
        }

        Row {
          id: drawerContent
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: drawer.itemGap

          // Hosted widgets are only instantiated while the reveal row is
          // actually open, destroyed (not just hidden) on every collapse
          // — clipping is paint-only, so a merely-invisible-but-still-
          // live widget's own click targets would keep registering at
          // their real geometry and could be hit by a click on an
          // unrelated, later bar widget.
          Repeater {
            model: drawer.visibleEntries
            delegate: Loader {
              id: hostedLoader
              required property var modelData
              active: drawer.drawerShown
              sourceComponent: active ? hostedSlotComponent : null
              Component {
                id: hostedSlotComponent
                ModuleSlot { bar: drawer.bar; entry: hostedLoader.modelData; region: drawer.bar.drawerSection }
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: verticalLayout

    Item {
      id: layoutRootV
      implicitWidth: bar.barSize
      implicitHeight: expandIconV.implicitHeight + drawerClipV.height

      HoverHandler {
        id: drawerHoverV
        onHoveredChanged: hoverSettleTimerV.restart()
      }

      Timer {
        id: hoverSettleTimerV
        interval: 150
        onTriggered: drawer.expanded = drawerHoverV.hovered
      }

      BarIconButton {
        id: expandIconV
        bar: drawer.bar
        width: implicitWidth
        height: implicitHeight
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        text: "\uf141"
        textRotation: 90
        onPressed: function(button) {
          drawer.managePopupOpen = !drawer.managePopupOpen
        }
      }

      Item {
        id: drawerClipV
        anchors.bottom: expandIconV.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: bar.barSize
        height: drawer.drawerShown ? drawerContentV.implicitHeight : 0
        clip: true

        Behavior on height {
          NumberAnimation { duration: drawer.animationDuration; easing.type: Easing.OutCubic }
        }

        Column {
          id: drawerContentV
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: drawer.itemGap

          Repeater {
            model: drawer.visibleEntries
            delegate: Loader {
              id: hostedLoaderV
              required property var modelData
              active: drawer.drawerShown
              sourceComponent: active ? hostedSlotComponentV : null
              Component {
                id: hostedSlotComponentV
                ModuleSlot { bar: drawer.bar; entry: hostedLoaderV.modelData; region: drawer.bar.drawerSection }
              }
            }
          }
        }
      }
    }
  }

  // A distinct coordinator object for the popup's owner, rather than
  // `drawer` itself: Bar.qml's ModuleSlot lights up its "panel open" mark
  // when bar.activePopout === slot.activeItem, and slot.activeItem for the
  // glyph's own slot is `drawer`. Using `drawer` as the popup's
  // requestPopout owner too would make that comparison match while the
  // manage popup is open, lighting the mark for it — a distinct object
  // still gets PopupCard's outside-click auto-close and popout exclusivity
  // without ever equaling slot.activeItem.
  QtObject {
    id: managePopupCoordinator
    function close() { drawer.managePopupOpen = false }
  }

  PopupCard {
    id: managePopup
    anchorItem: drawer
    owner: managePopupCoordinator
    bar: drawer.bar
    open: drawer.managePopupOpen
    contentWidth: managePopup.fittedContentWidth(Style.space(320))
    readonly property int listMaxHeight: Style.space(420)
    contentHeight: managePopup.fittedContentHeight(manageColumn.implicitHeight, listMaxHeight)

    Flickable {
      id: manageFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: manageColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: manageColumn
        width: manageFlick.width
        spacing: Style.space(10)

        Text {
          text: "Hosted widgets"
          textFormat: Text.PlainText
          color: drawer.bar.foreground
          font.family: drawer.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          visible: drawer.hostedIds.length === 0
          text: "Nothing hosted yet — add a widget below."
          textFormat: Text.PlainText
          color: Qt.darker(drawer.bar.foreground, 1.5)
          font.family: drawer.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        Repeater {
          model: drawer.hostedIds
          delegate: Item {
            id: hostedRow
            required property var modelData
            readonly property string itemId: String(modelData)
            readonly property bool isHidden: drawer.visibleIds.indexOf(itemId) === -1
            readonly property int itemIndex: drawer.hostedIds.indexOf(itemId)
            readonly property bool canMoveUp: itemIndex > 0
            readonly property bool canMoveDown: itemIndex !== -1 && itemIndex < drawer.hostedIds.length - 1
            readonly property var meta: drawer.bar.barWidgetRegistry
              ? drawer.bar.barWidgetRegistry.metadataFor(drawer.bar.canonicalWidgetId(itemId)) : null
            readonly property string displayName: meta && meta.displayName ? meta.displayName : itemId

            width: manageColumn.width
            implicitHeight: Style.space(28)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: upBtn.left
              anchors.rightMargin: Style.space(8)
              // displayName comes from another plugin's own manifest
              // (barWidgetRegistry.metadataFor) — not something this
              // plugin wrote, so it's untrusted input. Plain text only,
              // same reasoning as the stock Tray widget's own manage
              // popup rows.
              textFormat: Text.PlainText
              text: hostedRow.displayName
              color: drawer.bar.foreground
              font.family: drawer.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Button {
              id: upBtn
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: downBtn.left
              anchors.rightMargin: Style.space(4)
              enabled: hostedRow.canMoveUp
              opacity: enabled ? 1.0 : 0.35
              text: "▲"
              foreground: drawer.bar.foreground
              horizontalPadding: 6
              verticalPadding: 3
              fontSize: Style.font.bodySmall
              onClicked: drawer.bar.moveDrawerEntry(hostedRow.itemId, -1)
            }

            Button {
              id: downBtn
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: hideBtn.left
              anchors.rightMargin: Style.space(6)
              enabled: hostedRow.canMoveDown
              opacity: enabled ? 1.0 : 0.35
              text: "▼"
              foreground: drawer.bar.foreground
              horizontalPadding: 6
              verticalPadding: 3
              fontSize: Style.font.bodySmall
              onClicked: drawer.bar.moveDrawerEntry(hostedRow.itemId, 1)
            }

            Button {
              id: hideBtn
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: unhostBtn.left
              anchors.rightMargin: Style.space(6)
              text: hostedRow.isHidden ? "Show" : "Hide"
              foreground: drawer.bar.foreground
              horizontalPadding: 8
              verticalPadding: 3
              fontSize: Style.font.bodySmall
              onClicked: drawer.bar.setDrawerEntryHidden(hostedRow.itemId, !hostedRow.isHidden)
            }

            Button {
              id: unhostBtn
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              text: "Remove"
              foreground: drawer.bar.foreground
              horizontalPadding: 8
              verticalPadding: 3
              fontSize: Style.font.bodySmall
              onClicked: drawer.bar.unhostFromDrawer(hostedRow.itemId)
            }
          }
        }

        Item { width: 1; height: Style.space(6) }

        Text {
          text: "Add a widget"
          textFormat: Text.PlainText
          color: drawer.bar.foreground
          font.family: drawer.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        // Recomputed each time the popup opens rather than kept live —
        // the catalogue of registered widgets changes rarely enough that
        // this is simpler than wiring a reactive dependency on
        // barWidgetRegistry.revision.
        Repeater {
          model: drawer.managePopupOpen ? drawer.bar.candidateDrawerWidgets() : []
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
              // Same untrusted-manifest concern as hostedRow's
              // displayName Text above — see its comment.
              textFormat: Text.PlainText
              text: candidateRow.modelData.displayName
              color: drawer.bar.foreground
              font.family: drawer.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Button {
              id: addBtn
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              text: "Add"
              foreground: drawer.bar.foreground
              horizontalPadding: 8
              verticalPadding: 3
              fontSize: Style.font.bodySmall
              onClicked: drawer.bar.hostInDrawer(candidateRow.modelData.id)
            }
          }
        }
      }
    }
  }
}
