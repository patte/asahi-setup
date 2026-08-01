#!/usr/bin/env bash
# The edit loop for roles/hyprland/files/hyprland.lua: copy the config into
# place and reload the running compositor. Equivalent to
# `./run.sh hyprland && hyprctl reload`, minus the COPR and package work — this
# gets run after every tweak, and none of that needs re-checking each time.
#
# Runs the `hyprland-config` tag, which is only on the two config tasks in
# roles/hyprland/tasks/main.yml. Use ./run.sh hyprland for the full role.
set -euo pipefail
cd "$(dirname "$0")"

# Gathering facts is most of what is left of the runtime, for the one fact
# these tasks read: user_dir. It cannot simply be turned off — the whole repo
# addresses $HOME as ansible_facts['user_dir'] — so it is cached instead. That
# is configured in ansible.cfg, not here, since ./run.sh wants it just as much;
# see the comment there for why a boot-scoped cache is the safe kind.
cmd=(ansible-playbook site.yml --tags hyprland-config "$@")
echo "==> ${cmd[*]}"
"${cmd[@]}"

# Nothing here needs root, so there is no --ask-become-pass dance: the config
# lands in $HOME. If a become prompt ever appears, a non-config task leaked
# into the tag.

# hyprctl only works from inside a running Hyprland session. Outside one the
# copy above is still the useful half — the next login reads the new file.
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE-} ]]; then
    echo "==> not in a hyprland session; skipping reload"
    exit 0
fi

echo "==> hyprctl reload"
exec hyprctl reload
