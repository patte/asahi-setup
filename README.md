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
| `codecs` | RPM Fusion free + nonfree, swaps `ffmpeg-free` for the full `ffmpeg` |
| `shell` | zsh + login shell, `.zshrc` / `.zshenv`, atuin and starship, with their configs |
| `rust` | rustup, the default toolchain, `rust-src`, `bindgen-cli` |
| `fonts` | The families in `fonts_enabled` into `~/.local/share/fonts` (knows DM Mono, JetBrains Mono, SF Mono, Tabular) |
| `ghostty` | scottames COPR, ghostty, templated config (Ayu theme, font from `ghostty_font_family`) |
| `claude` | Claude Code via the native installer and `settings.json` |
| `vscode` | Microsoft repo + key, `code` |
| `tailscale` | Tailscale repo + key, daemon enabled |
| `keyswaps` | Builds keyd from source into `/usr/local`, installs the mac-style keymap, enables it |
| `titdb` | Builds trackpad-is-too-damn-big, installs binary + unit, enables it |
| `hyprland` | sdegler COPR (scoped), the hypr stack, waybar/wofi/mako, `hyprland.lua` |
| `fairydust` | Builds and installs the patched Asahi kernel. Tagged `never`, needs `rust` |

### The prompt

[starship](https://starship.rs), stock but for the prompt character:

```
asahi-setup on  main [!?⇡1] took 4s
$
```

It replaced a hand-written zsh prompt that used to sit at the top of `.zshrc`,
and nothing of that was carried over. Tuning goes in
`roles/shell/files/starship.toml` and is applied by `./run.sh shell` — the role
overwrites `~/.config/starship.toml`, so hand-edits there do not survive.

The branch glyph needs a Nerd Font — see the `fonts` role.

starship is not in Fedora, so the role takes the static aarch64-musl tarball
from upstream's releases and drops the binary in `~/.local/bin`, which is why
the `starship init` line in `.zshrc` sits *below* the `PATH` export.

[jj-starship](https://github.com/dmmulroy/jj-starship) is what to add here if
[jj](https://jj-vcs.github.io/jj/) ever gets used: starship has no jj module,
so in a jj repo the built-in `git_*` ones show the stale underlying ref or
nothing at all. It is a single binary starship execs per prompt, and it covers
git as well, so `git_branch`, `git_status` and `git_commit` get disabled
alongside it.

### codecs is about decode speed, not formats

Easy to mistake for the usual "enable RPM Fusion for restricted formats" advice.
It is not that. MP4 plays out of the box — `qtdemux` is in
`gstreamer1-plugins-good`, and H.264 decodes through Cisco's `libopenh264`,
which the `fedora-cisco-openh264` repo enables by default.

The problem is how *fast* it decodes. `libopenh264` is single-threaded, and this
laptop has no hardware video decode at all — the M-series decode block has no
Linux driver — so a 4K file is one core doing every frame. Measured on a
3840x2160 41 Mbit/s H.264 High master:

```
frame=720  speed=0.944x
bench: utime=31.582s  stime=0.127s  rtime=31.786s
```

23 fps against the 24 the file needs, and `utime` ≈ `rtime`: one core of eight.
Just under realtime is the worst place to be — it stutters and drifts instead of
failing honestly. Firefox and VLC both decode through system libavcodec, so both
did it identically.

RPM Fusion's `ffmpeg` restores libavcodec's own H.264 decoder, which is NEON
tuned and frame-threaded. The same file afterwards:

```
frame=720  fps=160  speed=6.67x
bench: utime=27.537s  stime=0.168s  rtime=4.498s
```

7× the wall-clock rate and 160 fps against the 24 needed — margin, not a fix
that only just holds. `utime` *fell* too: the decode is cheaper per frame as
well as spread across roughly six cores instead of one.

One thing the swap does **not** fix is gstreamer. Fedora builds
`gstreamer1-plugin-libav` with the encumbered decoders blacklisted at compile
time, so `avdec_h264` and `avdec_h265` stay missing whichever libavcodec is
underneath — gstreamer keeps using the slow `openh264dec` and has no HEVC
decoder at all. Nothing here plays video through gstreamer, so it is left
alone; `gstreamer1-plugins-bad-freeworld` is the package to add if that changes.

Re-run the benchmark after a rebuild if playback ever regresses:

```sh
ffmpeg -benchmark -i FILE -t 30 -an -sn -f null -
```

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
else — and then `hyprctl reload`. About a second, and no sudo, since the COPR
and package tasks are not in the tag. Use `./run.sh hyprland` when the packages
themselves need attention.

Most of that second used to be fact gathering, for the single fact those tasks
read; see fact caching below.

## Fact caching

`ansible.cfg` turns on `smart` gathering against a jsonfile cache, so every
entry point — `./run.sh`, `./hypr.sh`, a bare `ansible-playbook` — skips the
`Gathering Facts` task while the cache is warm. Worth roughly 1.7s a run, which
is two thirds of `./hypr.sh`.

The cache lives in `${XDG_RUNTIME_DIR}/asahi-setup/facts`, which is tmpfs and
is emptied on every reboot. That is what makes it safe rather than merely fast,
and it is why the timeout is `0`, never expire: **a reboot is the only event
that changes a fact this repo reads.** The five in use are `user_dir`,
`architecture`, `processor_vcpus`, `distribution_major_version` and `kernel` —
the first three would need different hardware, the fourth a release upgrade,
and `kernel` reports the *running* kernel, so it flips at boot and not when
`fairydust` builds one.

That last one is the reason not to move the cache somewhere persistent. A cache
surviving a reboot is exactly how `./run.sh fairydust` would read a pre-reboot
`ansible_kernel` and rebuild the kernel already running.

Two facts do get written by roles — `shell` sets `user_shell`, `tailscale` adds
`tailscale0` — and neither is ever read, so neither matters. If you start
reading a fact a role changes mid-run, this scheme stops holding.

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
- starship: bump `starship_version` and that is all — the task compares against
  `--version` rather than guarding on the file, so there is nothing to delete
