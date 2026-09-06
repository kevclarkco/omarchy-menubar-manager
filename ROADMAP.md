# Roadmap

## Done

- Initial working version of the menubar drawer manager
- Fixed drawer stay-open behavior and a real click mis-routing bug
- Added README and MIT LICENSE
- Distinguished the ⋯ glyph from the system tray's own chevron
- Kept the glyph stationary under the cursor while the drawer opens
- Added an open-panel indicator to hosted widget icons
- Suppressed the glyph's open-panel underline; polished manage popup labels
- Excluded `omarchy.tray` from hosting; fixed un-host section fallback
- Renamed plugin id to `kc.omarchy-menubar-manager`
- Fixed README to match actual UI (Add/Remove labels, ⋯ glyph)
- Detect a hosted widget's open panel via `bar.activePopout` instead of `opened`
- Un-host now restores a widget to its original *index* within its section,
  not just the section (`hostedFrom` records `{section, index}`)
- Fixed the manage popup silently losing Add/Remove clicks on long lists —
  the candidate/hosted list now scrolls (`Flickable` + `ScrollBar`) instead
  of overflowing past the popup's actual clickable area
- Fixed a race where rapid Add/Remove clicks could silently revert the
  hosted list: the popup-reopen flag's clearing write now reads
  `shell.shellConfig` fresh instead of a stale snapshot captured earlier
- Fixed a null-deref (`unregisterHostedPanels of null`) that fired on every
  single host/unhost, from teardown ordering between this widget and its
  nested hosted-widget Loaders
- Added tray-pinning: this widget now keeps itself immediately to the right
  of the tray's ⋯ chevron, self-correcting on any bar rebuild (mirrors the
  shell's own `BarModel.pinTrayToInner`)
- Fixed un-host inserting a widget in front of our own icon when its
  remembered position conflicted with the tray-pinning slot
- Removed Pin/Unpin: a hosted widget is now either in the drawer or hidden,
  no third "always visible" state — it only duplicated what Remove already
  gave you
- Added vertical bar support (`position: left`/`right`): a second layout
  tree (mirroring the shell's own Tray.qml/Indicators.qml dual-Component
  pattern) handles the drawer reveal, glyph rotation, and per-icon
  "panel open" indicator along the vertical axis

## Known upstream issue (not fixable from this plugin)

Any structural `bar.layout` change — hosting/un-hosting, installing or
enabling a plugin, drag-reordering — forces the Omarchy shell to destroy and
rebuild every bar widget, and that rebuild doesn't clean up old instances
reliably: reproduced via the plain `omarchy plugin enable` command, with zero
involvement from this plugin's code. Symptoms seen: duplicate IpcHandler
registration warnings, and progressively unreliable clicks across the bar
the more such changes happen in one session. A full `omarchy restart shell`
clears it. Worth reporting upstream to Omarchy; nothing to do here except
avoid triggering more structural changes than necessary (see the tray-pinning
note above, which checks before writing for exactly this reason).

## Next up

Roughly in priority order — see README "Limitations" for the user-facing
description of each gap.

1. **Hotkey/CLI summon reaching hosted widgets.** `omarchy toggle <id>` and
   Hyprland keybinds don't find a widget once it's hosted — only clicking
   inside the drawer opens its panel. Worth fixing for anyone who binds a
   hotkey to something they also want to host.
2. **Drag-and-drop reordering.** Currently reordering (if any) goes through
   the manage popup only, not by dragging hosted icons directly.

## Notes

- No dedicated changelog file existed before this; the "Done" list above was
  reconstructed from `git log`.
- Update this file as work lands — move finished items from "Next up" to
  "Done", and add newly discovered gaps as they're found.
