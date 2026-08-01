# asahi-setup

Opinionated setup for my Fedora Asahi Workstation

## Usage

```sh
./bootstrap.sh          # once, on a fresh box: installs ansible, then stop
./run.sh                # everything except the kernel
./run.sh keyswaps       # one role
./run.sh base ghostty   # several roles
./run.sh --check        # dry run, changes nothing
./run.sh --list         # list roles
./run.sh fairydust      # the kernel build, deliberately
./hypr.sh               # hyprland config only, then hyprctl reload
```

Flags pass through to `ansible-playbook`, so `./run.sh titdb --diff -v` works —
`./hypr.sh --diff` too.

## Where this starts

**Not** at bare metal. This playbook assumes:

1. Fedora Asahi Remix 44 Workstation is installed and booted.
2. You are logged in as `patte` with working network and sudo.

From there `./run.sh` should get everything else back.

## Roles

| Role | What it does |
|---|---|
| `base` | The packages actually installed by hand, `~/src` |
| `shell` | zsh + login shell, `.zshrc` / `.zshenv`, atuin and its config |
| `rust` | rustup, the default toolchain, `rust-src`, `bindgen-cli` |
| `ghostty` | scottames COPR, ghostty, config (uses the built-in Ayu theme) |
| `claude` | Claude Code via the native installer and `settings.json` |
| `vscode` | Microsoft repo + key, `code` |
| `tailscale` | Tailscale repo + key, daemon enabled |
| `keyswaps` | Builds keyd from source into `/usr/local`, installs the mac-style keymap, enables it |
| `titdb` | Builds trackpad-is-too-damn-big, installs binary + unit, enables it |
| `hyprland` | sdegler COPR (scoped), the hypr stack, waybar/wofi/mako, `hyprland.lua` |
| `fairydust` | Builds and installs the patched Asahi kernel. Tagged `never`, needs `rust` |

### fairydust needs rust

The kernel build needs `cargo` and `bindgen` in `~/.cargo/bin`. `./run.sh
fairydust` adds the `rust` role to the run automatically, and the fairydust
role fails with an explanation if the toolchain is missing anyway.

This is deliberately *not* done with a `meta/dependencies` entry. Role
dependencies inherit the tags of the role that pulls them in, and Ansible
de-duplicates a role that appears twice in a play — so with `fairydust` tagged
`never`, the dependency copy of `rust` would be dropped in favour of the
standalone one, which `--tags fairydust` does not select. The kernel build
would then run without a toolchain. Handling it in `run.sh` is less clever and
actually works.

### hyprland sits next to GNOME

Installing it adds `/usr/share/wayland-sessions/hyprland.desktop`; nothing about
the GNOME session changes. Log out, click the gear at the GDM password prompt,
pick Hyprland. GDM remembers the choice per user, so GNOME stays the default
until it is picked deliberately, and a bad session is one login away from being
GNOME again. keyd carries over unchanged — it rewrites below the compositor.

The COPR is scoped with `includepkgs` to the hypr stack only. It also builds
kitty, waybar, qt6ct, uwsm, cliphist and swww, which Fedora ships too, and with
no repo priority the higher version would silently win.

Config is `roles/hyprland/files/hyprland.lua` — Hyprland 0.5x reads
`~/.config/hypr/hyprland.lua` and only falls back to the old `hyprland.conf`
when there is no `.lua`. It is deliberately minimal: waybar, wofi and mako run
on stock configs, and there is no wallpaper, colour scheme or animation tuning
yet. Not done yet, on purpose: a lock screen (`hyprlock`), an idle daemon
(`hypridle`) and lid/suspend behaviour.

Editing it is a tight enough loop to deserve its own entry point: `./hypr.sh`
runs the `hyprland-config` tag — the two tasks that place the file, nothing
else — and then `hyprctl reload`. No sudo, since the COPR and package tasks are
not in the tag. Use `./run.sh hyprland` when the packages themselves need
attention.

## Source of truth

Config files live **here**, in `roles/*/files/`, and are copied out to the
system. After a change, edit the copy in this repo and re-run the role — do not
edit `/etc/keyd/default.conf` or `~/.config/ghostty/config.ghostty` directly, or
the next run will quietly revert you.

`~/src/keyswaps/` and the notes in the titdb checkout stay where they are as
documentation, but the files this playbook installs are the ones in here.

## What is deliberately not automated

- **`tailscale up`** — needs interactive browser auth. Run once by hand.
- **The kernel, by default.** `fairydust` is tagged `never`; only an explicit
  `./run.sh fairydust` reaches it. It also skips itself if you are already
  running a `-asahi-fairydust` kernel, so it will not pick up new upstream
  commits on its own. That is intentional — an unattended kernel rebuild is not
  something a config run should decide to do.

## Rebuild triggers

Source builds are guarded so re-runs are cheap. To force one:

- keyd: bump `keyd_version` in `group_vars/all.yml` (it compares against
  `keyd --version`)
- titdb: bump `titdb_commit`, then delete
  `~/src/trackpad-is-too-damn-big/build/titdb`
