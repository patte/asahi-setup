# asahi-setup

Rebuild this machine — MacBook Air (M2, J415), Fedora Asahi Remix 44
Workstation, GNOME/Wayland — from a fresh install, without remembering
anything.

Ansible, run locally against `localhost`. Idempotent: running it on a working
box should report zero changes, which is how you check that the rebuild still
works *without* rebuilding.

## Usage

```sh
./bootstrap.sh          # once, on a fresh box: installs ansible, then stop
./run.sh                # everything except the kernel
./run.sh keyswaps       # one role
./run.sh base ghostty   # several roles
./run.sh --check        # dry run, changes nothing
./run.sh --list         # list roles
./run.sh fairydust      # the kernel build, deliberately
```

Flags pass through to `ansible-playbook`, so `./run.sh titdb --diff -v` works.

## Where this starts

**Not** at bare metal. Reproducing the Asahi install itself — the upstream
installer, partitioning, m1n1 and the initial bootloader setup — is manual and
documented by upstream. This playbook assumes:

1. Fedora Asahi Remix 44 Workstation is installed and booted.
2. You are logged in as `patte` with working network and sudo.

From there `./run.sh` should get everything else back.

## Roles

| Role | What it does |
|---|---|
| `base` | The packages actually installed by hand, `~/src` |
| `shell` | zsh + login shell, `.zshrc` / `.zshenv`, atuin and its config |
| `rust` | rustup, the default toolchain, `rust-src`, `bindgen-cli` |
| `ghostty` | scottames COPR, ghostty, config + custom Ayu theme |
| `vscode` | Microsoft repo + key, `code` |
| `tailscale` | Tailscale repo + key, daemon enabled |
| `keyswaps` | Builds keyd from source into `/usr/local`, installs the mac-style keymap, enables it |
| `titdb` | Builds trackpad-is-too-damn-big, installs binary + unit, enables it |
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

## Source of truth

Config files live **here**, in `roles/*/files/`, and are copied out to the
system. After a change, edit the copy in this repo and re-run the role — do not
edit `/etc/keyd/default.conf` or `~/.config/ghostty/config.ghostty` directly, or
the next run will quietly revert you.

`~/src/keyswaps/` and the notes in the titdb checkout stay where they are as
documentation, but the files this playbook installs are the ones in here.

## Package list

`base_packages` in `group_vars/all.yml` is only what was installed by hand,
recovered from `dnf history` filtered to `Reason=User`. Dependencies are left
to dnf. Build dependencies are declared in whichever role needs them, not in
the base list.

To see what has been added by hand since:

```sh
for id in $(seq 5 99); do
  dnf history info $id 2>/dev/null | awk '$1=="Install" && $3=="User" {print $2}'
done | sed 's/-[0-9]*:.*$//' | sort -u
```

## What is deliberately not automated

- **`tailscale up`** — needs interactive browser auth. Run once by hand.
- **The kernel, by default.** `fairydust` is tagged `never`; only an explicit
  `./run.sh fairydust` reaches it. It also skips itself if you are already
  running a `-asahi-fairydust` kernel, so it will not pick up new upstream
  commits on its own. That is intentional — an unattended kernel rebuild is not
  something a config run should decide to do.
- **Signal** and **Hyprland** — deliberately out of scope for now.

## Rebuild triggers

Source builds are guarded so re-runs are cheap. To force one:

- keyd: bump `keyd_version` in `group_vars/all.yml` (it compares against
  `keyd --version`)
- titdb: bump `titdb_commit`, then delete
  `~/src/trackpad-is-too-damn-big/build/titdb`

## Not in here

Secrets and identity, deliberately. `~/.ssh` keys (including the FIDO
`id_ed25519_sk`), the atuin sync key, and any tokens are not captured — the
`shell` role only creates `~/.ssh` with the right mode so the agent-socket
symlink in `.zshrc` works. Restore those from wherever you keep them.

## Known drift

`LOCAL-SETUP.md` in the titdb checkout says the unit is installed but not
enabled. It is enabled on this machine, and this playbook enables it. The note
is stale; the playbook is right.
