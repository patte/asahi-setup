# Local setup notes (Fedora Asahi Remix 44, GNOME/Wayland, MacBook Air J415)

Not part of upstream. Records how TITDB is installed on this machine.

## Paths

| What | Where |
|---|---|
| Source checkout | `/home/patte/src/trackpad-is-too-damn-big` |
| Built binary | `/home/patte/src/trackpad-is-too-damn-big/build/titdb` |
| Installed binary | `/usr/local/bin/titdb` |
| Unit source (edit here, tracked with the repo) | `/home/patte/src/trackpad-is-too-damn-big/titdb.service` |
| Installed unit | `/etc/systemd/system/titdb.service` |
| Trackpad device | `/dev/input/by-path/platform-24eb30000.input-event-mouse` (→ `event0`) |

The `by-path` symlink is used instead of `/dev/input/event0` because evdev numbering
can change across boots.

## Control

The unit is installed but **not enabled**, so it does nothing at boot until told to.

```bash
sudo systemctl start titdb      # on  - trackpad edges masked
sudo systemctl stop titdb       # off - instantly back to stock, no reboot
systemctl status titdb          # is it running?
journalctl -u titdb -e          # logs
```

Stopping ungrabs the physical device and destroys the virtual one immediately.
The same is true if the process is killed or crashes: the kernel releases the
`EVIOCGRAB` and tears down the uinput device when the fds close. There is no
state that outlives the process.

Optional, only if it should survive reboots:

```bash
sudo systemctl enable titdb     # start at boot
sudo systemctl disable titdb    # stop starting at boot
```

## Retuning the dead zones

Current settings, in `ExecStart`: flex mode, 10% left/right, 15% bottom, 0% top.
On this 143 x 85 mm trackpad that is roughly 14 mm side strips and a 13 mm bottom
strip.

Flags: `-m` mode (`p` print / `s` strict / `f` flex), `-l -r -t -b` edge
percentages. To pick numbers from real data, run print mode - it does **not**
grab the device, so the trackpad keeps working while events are dumped:

```bash
sudo titdb -d /dev/input/by-path/platform-24eb30000.input-event-mouse -m p
```

To change the running config:

```bash
sudoedit /etc/systemd/system/titdb.service     # edit ExecStart
sudo systemctl daemon-reload
sudo systemctl restart titdb
```

Keep `titdb.service` in the checkout in sync with the installed copy.

## Rebuilding after a `git pull`

```bash
cd /home/patte/src/trackpad-is-too-damn-big/build
cmake .. && make
sudo systemctl stop titdb
sudo install -m755 titdb /usr/local/bin/titdb
sudo systemctl start titdb
```

## Uninstall

```bash
sudo systemctl disable --now titdb
sudo rm /etc/systemd/system/titdb.service
sudo systemctl daemon-reload
sudo rm /usr/local/bin/titdb
rm -rf /home/patte/src/trackpad-is-too-damn-big
```

Build dependencies installed for this, removable if nothing else needs them:

```bash
sudo dnf remove cmake libevdev-devel
```

Nothing else was touched - no udev rules, no group changes, no `/etc` files
beyond the unit itself.

## Gotchas

- While TITDB runs, anything watching the *original* device (`event0`) sees a
  dead device; it must watch the virtual clone instead.
- The clone inherits the source device name, so two `Apple MTP multi-touch`
  entries show up in device listings.
- The hardening block in the unit is untested against SELinux here. If the unit
  fails to start, comment that block out first to rule it out.
