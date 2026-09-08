import QtQuick

// Omarchy 4.0.3 intentionally limits the API injected into third-party bar
// widgets. Services may opt into the supported, detached widget-catalog
// snapshot without receiving the shell's mutable internal registry.
QtObject {
  property var barWidgetRegistry: null
}
