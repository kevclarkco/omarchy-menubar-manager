# Omarchy Menubar Manager

A Bartender/Ice-style menubar manager for the [Omarchy](https://omarchy.org)
bar: collapse other bar widgets into a hover-to-reveal drawer, so your bar
doesn't stay permanently cluttered with icons you only need occasionally.

<!-- ![Omarchy Menubar Manager, collapsed and hovered open](preview.png) -->

## Why

The built-in system tray already has this hover-to-reveal drawer behavior,
but it's hardcoded to system-tray (SNI) icons only — there's no way to
collapse an ordinary bar widget, first-party or third-party, the same way.
This plugin is a generic version of that mechanism: it can host *any*
registered bar widget, not just tray icons.

## Features

- Hover the ⋯ icon to reveal hosted widgets; move away and it collapses
  again
- A manage popup (click the ⋯ icon) to add, remove, pin, or hide widgets
- **Add** moves a widget into the drawer
- **Pin** keeps a hosted widget always visible, outside the drawer
- **Hide** keeps a widget hosted (its background service, if it has one,
  keeps running) without showing it anywhere
- Hosted widgets work exactly as normal: click to open their own panel,
  their own settings keep persisting, theming and tooltips are unaffected
- The drawer stays open for as long as a hosted widget's panel is open, so
  you can click it again to close it without hunting for it

## Install

```bash
omarchy plugin add https://github.com/ultgames/omarchy-menubar-manager --enable --yes
```

The widget appears on the right side of the bar by default.

To update later:

```bash
omarchy plugin update kc.omarchy-menubar-manager --yes
```

## Uninstall

```bash
omarchy plugin remove kc.omarchy-menubar-manager --yes
```

Uninstalling does **not** remove hosted widgets from the drawer first — any
widgets still hosted at uninstall time will need to be added back to the bar
by hand (`omarchy bar put <widget-id> --section <left|center|right>`), since
their shell.json entries live in the top-level `plugins[]` array while
hosted, rather than in `bar.layout.*`.

## Use

1. Click the ⋯ icon (either mouse button) to open the manage popup.
2. Under **Add a widget**, click **Add** next to anything you want to
   collapse into the drawer.
3. Hover the ⋯ icon to reveal what's hosted; click a hosted widget's icon
   to open its own panel, same as if it were still sitting directly on the
   bar.
4. Back in the manage popup: **Pin** to keep something always visible
   outside the drawer, **Hide** to keep it hosted but never shown, **Remove**
   to put it back on the bar normally.

## Limitations

- **Horizontal bars only.** `position: left`/`right` isn't implemented yet.
- **No drag-and-drop.** Reordering happens through the manage popup, not by
  dragging.
- **Hotkey/CLI summon doesn't reach hosted widgets.** `omarchy toggle <id>`
  or a Hyprland keybind bound to a widget won't find it while it's hosted —
  clicking it inside the drawer still opens its panel fine, only *external*
  summon is affected. Worth fixing if you actually bind a hotkey to
  something you also want to host.

## How it works

Bar widgets only render where `shell.json`'s `bar.layout.<section>` says
they are. Hosting a widget moves its entry into the top-level `plugins[]`
array instead, which keeps it enabled (so its component and its own
settings-persistence keep working) without the bar auto-placing it anywhere
— this widget then loads and shows it itself, inside the drawer.

## License

MIT
