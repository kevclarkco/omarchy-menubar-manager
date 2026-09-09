# Omarchy Menubar Manager

> **⚠️ Retired for now.** As of Omarchy 4.0.3, third-party `bar-widget`
> plugins lost the shell-config write access this plugin needs to add or
> remove hosted widgets — see [Limitations](#limitations). **Add and
> Remove in the manage popup do nothing on 4.0.3+.** Nothing else is
> affected: widgets already hosted before you hit 4.0.3 keep rendering,
> reordering, hiding/showing, and opening normally. This project is paused
> — not abandoned — until Omarchy exposes a capability that covers this
> pattern, or a workaround turns up. New installs aren't recommended right
> now unless you're fine with a fixed, unchangeable set of hosted widgets.

A Bartender/Ice-style menubar manager for the [Omarchy](https://omarchy.org)
bar: collapse other bar widgets into a hover-to-reveal drawer, so your bar
doesn't stay permanently cluttered with icons you only need occasionally.

![Menubar Manager](preview.png)

## Why

The built-in system tray already has this hover-to-reveal drawer behavior,
but it's hardcoded to system-tray (SNI) icons only — there's no way to
collapse an ordinary bar widget, first-party or third-party, the same way.
This plugin is a generic version of that mechanism: it can host *any*
registered bar widget, not just tray icons.

## Features

- Works on horizontal (top/bottom) and vertical (left/right) bars alike
- Hover the ⋯ icon to reveal hosted widgets; move away and it collapses
  again
- The ⋯ icon keeps itself immediately next to the system tray, wherever
  that ends up on your bar
- A manage popup (click the ⋯ icon) to add, remove, hide, or reorder widgets
- **Add** moves a widget into the drawer
- **▲/▼** reorders a hosted widget within the drawer
- **Hide** keeps a widget hosted (its background service, if it has one,
  keeps running) without showing it anywhere
- Hosted widgets work exactly as normal: click to open their own panel,
  their own settings keep persisting, theming and tooltips are unaffected
- The drawer stays open for as long as a hosted widget's panel is open, so
  you can click it again to close it without hunting for it

## Install

```bash
omarchy plugin add https://github.com/kevclarkco/omarchy-menubar-manager --enable --yes
```

The widget appears on the right side of the bar by default.

Version 0.2.1 restores compatibility with Omarchy 4.0.3's scoped plugin
APIs. The manager now obtains the widget catalog through Omarchy's supported
read-only service injection, so the hover drawer can render its hosted
widgets without accessing the shell's internal bar object.

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
4. Back in the manage popup: **▲/▼** to reorder within the drawer, **Hide**
   to keep it hosted but never shown, **Remove** to put it back on the bar
   normally.

## Limitations

- **Add/Remove don't work on Omarchy 4.0.3+.** Adding or removing a hosted
  widget requires moving *another* plugin's entry between `bar.layout.*`
  and the top-level `plugins[]` — a shell-config write Omarchy 4.0.3
  restricts to `bar`-kind (full-bar-replacement) plugins. This plugin is a
  `bar-widget`, so `mutateShellConfig` refuses the write and Add/Remove
  silently do nothing. There's no plugin-side fix: it would need Omarchy to
  add a scoped capability for this pattern, or the plugin to become a full
  bar replacement (a much bigger change than "let me host a few widgets").
  Work around it by editing `~/.config/omarchy/shell.json` directly: move
  the widget's entry between its `bar.layout.<section>` array and the
  top-level `plugins[]` array, and add/remove its id from this plugin's own
  `hosted`/`hidden` lists in its `bar.layout` entry.
- **Hotkey/CLI summon doesn't reach hosted widgets.** `omarchy toggle <id>`
  or a Hyprland keybind bound to a widget won't find it while it's hosted —
  clicking it inside the drawer still opens its panel fine, only *external*
  summon is affected.

## How it works

Bar widgets only render where `shell.json`'s `bar.layout.<section>` says
they are. Hosting a widget moves its entry into the top-level `plugins[]`
array instead, which keeps it enabled (so its component and its own
settings-persistence keep working) without the bar auto-placing it anywhere
— this widget then loads and shows it itself, inside the drawer.

## Development

`MenubarModel.js` is pure, dependency-free JS (no QML/Quickshell imports),
so its host/un-host/reorder/tray-pinning logic has a test suite that runs
outside the shell entirely:

```bash
node --test
```

## License

MIT
