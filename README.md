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
| `steam` | Steam, plus a wrapper that gives the microVM the D-Bus bus Steam's login needs, and keeps the kernel it can run on |
| `hyprland` | sdegler COPR (scoped), the hypr stack, waybar/wofi/mako/hyprpaper, `hyprland.lua` |
| `narchy` | Clones the theme engine, links it into `~/.local/bin`, sets a palette and points the app configs at it |
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

### steam needs a kernel and a bus

Steam runs in a muvm microVM under FEX, and two things about that are not
handled by the packaged launcher.

The kernel is the hard one. On 7.1.5 any GPU client inside the microVM brings
the whole VM down the moment it maps a blob — `Failure during vcpu run: Bad
address (os error 14)`, which is [muvm#240][muvm240]. Steam is only the visible
casualty; a native `glxinfo` does it too. 7.0.13 is known good, so the role
keeps it installed: dnf prunes kernels oldest-first at `installonly_limit`, and
the known-good one is exactly what a couple of updates would evict. It is
reinstalled rather than pinned because /boot is 974M against ~185M a kernel,
which fits three and not four. Nothing here touches the bootloader — the role
warns when the running kernel is a bad one and leaves the choice alone:

```sh
sudo grubby --info=ALL | grep -E "index|title"
sudo grub2-reboot <index>     # next boot only
```

The bus is the subtle one. Steam gates its login UI on creating a
NetworkManager client, which lives on the D-Bus *system* bus, and muvm's guest
has a session bus but no system bus. So Steam sits on "Waiting for network..."
forever while the network is fine — its own connectivity tests pass over v4 and
v6. `libnm` only needs a bus it can reach, not NetworkManager on it, so
`steam-asahi` starts one inside the guest and points `DBUS_SYSTEM_BUS_ADDRESS`
at it. Running the real NetworkManager there does not work: no udev, so eth0
stays `unmanaged`.

The wrapper is `/usr/local/bin/steam-asahi`, and the menu entry is a user-level
`steam.desktop` that overrides the packaged one. `/usr/bin/steam` is left alone,
so `dnf update steam` cannot clobber any of this and deleting the one desktop
file puts the stock launcher back.

What the wrapper cannot fix is the UI scale. `xwayland.force_zero_scaling` hands
XWayland clients the raw panel and expects each toolkit to scale itself, and
Steam is neither Qt nor GTK. Valve removed both `STEAM_FORCE_DESKTOPUI_SCALING`
and `-forcedesktopscaling` when they added the Accessibility tab, so it is now a
per-account setting: **Settings → Accessibility → UI scaling**.

[muvm240]: https://github.com/AsahiLinux/muvm/issues/240

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

### narchy is the colour, and runs last

[narchy](https://github.com/patte/narchy) is where every colour in the desktop
comes from. This playbook installs the programs and their layout; narchy paints
them, all from one palette, and the two are kept apart on purpose — nothing in
`roles/` sets a colour, and narchy sets nothing else.

Cloned to `~/.local/share/narchy` with the three commands symlinked into
`~/.local/bin`, which is the install narchy's own README describes — **not**
into `~/src` like keyd and titdb, since nothing here is built and there is no
reason to keep it beside things that are.

`narchy_version: main` tracks the branch rather than pinning, since it is ours
and a re-run should pick up the last push. Then `narchy set` renders the palette
into `~/.local/state/narchy/current/`, and `narchy link` writes one include line
into each app's own config pointing at it. That second step is what makes the
first matter, and it is separate because narchy will not touch a config you have
not offered it.

Both sides of that arrangement have to hold, which is why the role is last in
`site.yml`:

- **narchy only ever writes inside its state directory**, except for vscode,
  vlc and firefox, which have no include mechanism — those three it edits in
  place, only once linked, and `narchy unlink` puts back what it found.
- **This playbook never rewrites a file narchy has a line in.** The waybar
  stylesheet is the one they share, and the hyprland role seeds it with
  `force: false` and adds its import with `lineinfile` for exactly that reason.
  Turning either into a plain `copy` would drop narchy's imports on every run.
  The ghostty role sidesteps it entirely by owning `config.ghostty` and leaving
  `config`, where narchy's line goes, alone.

Ordering is the other half: `link` writes into configs that must already exist,
and it skips any app it cannot find on PATH, so a role that has not run yet is
an app that silently goes unthemed.

Firefox is the exception to all of it, and gets the loader instead of a link.
`narchy link firefox` writes into every profile and reaches Firefox at its next
start; `narchy-firefox-live` puts a loader in Firefox's install directory —
root, and the only privileged thing narchy does — and recolours the windows in
front of you. The two are mutually exclusive, since a sheet imported by
userChrome.css is loaded first and pins the palette Firefox opened with.

The role installs the loader and then runs a bare `narchy link`, because narchy
refuses to link firefox over an installed loader. So there is no app list to
keep in step here: firefox drops out of `link` by itself, and stays out. Set
`narchy_firefox_live: false` to have the profiles linked instead.

Guarded on `narchy-firefox-live status`, which is the interesting part. A
Firefox update replaces the install directory and takes the loader with it —
upstream's own documented wart, a thing you are otherwise expected to notice and
redo by hand. `status` reports it as gone, so the next `./run.sh` puts it back.

One manual step is left, once: restart Firefox after the loader first goes in.
Profiles are also made by the browser rather than the package, so `link` on a
never-started Firefox has nothing to write into — which matters only if you turn
the loader off.

`narchy_theme` is a source of truth like any other file in here: the role
compares it against `narchy current` and re-applies when they differ, so a
palette picked by hand with `narchy set` or `narchy i` is reverted by the next
`./run.sh`, quietly and by design. Keep one you like by putting it in
`group_vars/all.yml`.

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
- **Wallpapers.** `narchy-backgrounds` is linked into `~/.local/bin` but never
  run: narchy ships none, and it fetches other people's photographs and artwork
  from Omarchy over the network. Name themes in `narchy_backgrounds_themes` to
  have the role pull them, or run it by hand. `aetheria` has none upstream.
- **Restarting Firefox** after the live loader goes in. Once, and only the
  first time; every `narchy set` after that lands in the open windows.

## Rebuild triggers

Source builds are guarded so re-runs are cheap. To force one:

- keyd: bump `keyd_version` in `group_vars/all.yml` (it compares against
  `keyd --version`)
- titdb: bump `titdb_commit`, then delete
  `~/src/trackpad-is-too-damn-big/build/titdb`
- starship: bump `starship_version` and that is all — the task compares against
  `--version` rather than guarding on the file, so there is nothing to delete
- narchy: nothing to force — `narchy_version: main` means `./run.sh narchy`
  fetches the branch every time. Wallpapers are the exception: they are guarded
  on `~/.config/narchy/backgrounds/<theme>/`, so delete that to re-fetch
