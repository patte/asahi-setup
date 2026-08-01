#!/usr/bin/env bash
# Run the provisioning playbook. With no arguments, runs everything except
# fairydust (a kernel compile is never implicit). Name one or more roles to run
# only those. Any flag is passed straight through to ansible-playbook.
set -euo pipefail
cd "$(dirname "$0")"

ROLES=(base shell rust fonts ghostty claude vscode tailscale keyswaps titdb hyprland fairydust)

usage() {
    cat <<EOF
usage: ./run.sh [role ...] [ansible-playbook flags]

  ./run.sh                     everything except fairydust
  ./run.sh keyswaps            only the keyswaps role
  ./run.sh base ghostty        only those two
  ./run.sh fairydust           the kernel build (asks for confirmation)
  ./run.sh --check             dry run, change nothing
  ./run.sh titdb --diff -v     flags pass through

  -l, --list                   list roles
  -h, --help                   this

roles: ${ROLES[*]}
EOF
}

tags=()
passthru=()

for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        -l|--list) printf '%s\n' "${ROLES[@]}"; exit 0 ;;
        -*)        passthru+=("$arg") ;;
        *)
            found=false
            for r in "${ROLES[@]}"; do [[ $arg == "$r" ]] && found=true && break; done
            if [[ $found == false ]]; then
                echo "run.sh: unknown role '$arg'" >&2
                echo "known roles: ${ROLES[*]}" >&2
                exit 2
            fi
            tags+=("$arg")
            ;;
    esac
done

if ! command -v ansible-playbook >/dev/null; then
    echo "run.sh: ansible-playbook not found — run ./bootstrap.sh first" >&2
    exit 1
fi

# A kernel compile takes a long time and replaces the running kernel. Make it
# a deliberate act even though the tag already gates it.
for t in ${tags[@]+"${tags[@]}"}; do
    if [[ $t == fairydust ]]; then
        read -rp "Build and install the fairydust kernel? [y/N] " reply
        [[ ${reply,,} == y* ]] || { echo "aborted"; exit 0; }
        # The kernel build needs cargo and bindgen. Pull the rust role in rather
        # than failing the preflight check inside the fairydust role.
        already=false
        for u in "${tags[@]}"; do [[ $u == rust ]] && already=true && break; done
        if [[ $already == false ]]; then
            echo "==> fairydust needs rust; adding the rust role"
            tags=(rust "${tags[@]}")
        fi
        # The build script shells out to sudo itself; warm the timestamp.
        sudo -v
        break
    fi
done

cmd=(ansible-playbook site.yml)

if [[ ${#tags[@]} -gt 0 ]]; then
    cmd+=(--tags "$(IFS=,; echo "${tags[*]}")")
fi

# Only ask for a become password if sudo would actually want one.
if ! sudo -n true 2>/dev/null; then
    cmd+=(--ask-become-pass)
fi

# Guard the expansion: "${passthru[@]:-}" on an empty array yields one empty
# argument, which ansible-playbook rejects as an unrecognized positional.
if [[ ${#passthru[@]} -gt 0 ]]; then
    cmd+=("${passthru[@]}")
fi

echo "==> ${cmd[*]}"
exec "${cmd[@]}"
