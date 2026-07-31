---
name: keyd-mac-style-copy-paste
description: "Fedora Asahi box does Super+C/V/X copy-paste AND Caps-as-Ctrl entirely in keyd; setup documented in ~/src/keyswaps/README.md"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5446834e-bd33-4547-bc02-75f6b945df29
  modified: 2026-07-30T20:05:00.000Z
---

Patrick's Fedora Asahi aarch64 / GNOME Wayland laptop has keyd v2.6.0 built from
source at `~/src/keyd`, installed via `sudo make install` (prefix `/usr/local`).

**Read `~/src/keyswaps/README.md` first — that folder is the source of truth.**
`~/src/keyswaps/default.conf` is the canonical config; `/etc/keyd/default.conf` is a
copy of it (`sudo cp` + `sudo keyd reload`). Bindings: `Super+C/V/X` = copy/paste/cut,
`Caps` = Ctrl, `Ctrl` = Ctrl, `Super+Caps` = toggle real Caps Lock.

**Why:** Copy/paste maps to the XF86 `copy`/`paste`/`cut` keysyms, not `Ctrl+C` —
`Ctrl+C` would SIGINT in a terminal. keyd 2.6.0 also rejects the inline chord form
`meta+c = copy`; the `[meta]` layer form is required. Caps→Ctrl lives in keyd rather
than xkb because xkb remaps by *keycode*: with any `ctrl:` xkb option set, no keycode
can reach apps as a real Caps Lock, which kills the `Super+Caps` escape hatch he asked
for. xkb options are now `['terminate:ctrl_alt_bksp']` only. Avoid `ctrl:swapcaps`
specifically — it is two-way, so the bottom-left Ctrl key typed Caps Lock, and on this
Apple keyboard that key is next to Cmd, so reaching for Super+C kept triggering caps
(the bug fixed 2026-07-30).

**How to apply:** Don't propose xkb/GNOME settings for this machine's remapping — it
all belongs in keyd now. Validate edits with `keyd check` before installing; debug with
`sudo keyd monitor -t` (needs his password, so ask him to run it). Trade-offs he
accepted: keyd shadows GNOME's `Super+V` notification list, and Caps→Ctrl now depends
on `keyd.service` running.
See [[prefers-source-builds-over-third-party-repos]].
