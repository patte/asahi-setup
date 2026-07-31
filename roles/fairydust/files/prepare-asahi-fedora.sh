#!/usr/bin/env bash
set -euo pipefail

# prepare-asahi-fedora.sh - Install everything needed to build the Asahi
# fairydust kernel on Fedora (C toolchain deps + Rust toolchain).
# Usage: ./prepare-asahi-fedora.sh
#
# NOTE: this script installs the Rust toolchain into ~/.cargo. Because a script
# cannot modify its parent shell, run `source ~/.cargo/env` (or open a new
# shell) afterwards before running fairydust-asahi-fedora.sh.

SRCDIR="$(cd "$(dirname "$0")" && pwd)"

info()  { echo -e "\033[1;35m==>\033[0m \033[1m$*\033[0m"; }
warn()  { echo -e "\033[1;33m==> WARNING:\033[0m $*"; }
error() { echo -e "\033[1;31m==> ERROR:\033[0m $*" >&2; exit 1; }
step()  { echo -e "\033[1;36m  ->\033[0m $*"; }

PACKAGES=(
    git bc bison flex
    make automake gcc gcc-c++
    openssl openssl-devel elfutils-libelf-devel
    ncurses-devel dwarves cpio
    rustup
)

info "Step 1/5: Installing build dependencies"
step "Running: dnf install ${PACKAGES[*]}"
sudo dnf install -y "${PACKAGES[@]}"
echo

info "Step 2/5: Setting up rustup toolchain"
if [[ -x "$HOME/.cargo/bin/rustup" ]]; then
    step "rustup already initialized at $HOME/.cargo"
else
    step "Running: rustup-init -y --no-modify-path"
    rustup-init -y --no-modify-path
fi

step "Sourcing $HOME/.cargo/env"
[[ -f "$HOME/.cargo/env" ]] || error "$HOME/.cargo/env not found - rustup-init did not complete"
# shellcheck disable=SC1091
source "$HOME/.cargo/env"
echo

info "Step 3/5: Selecting Rust toolchain"
step "Running: rustup default stable"
rustup default stable

step "Running: rustup component add rust-src"
rustup component add rust-src
step "rustc: $(rustc --version)"
echo

info "Step 4/5: Installing bindgen-cli"
if command -v bindgen &>/dev/null; then
    step "bindgen already present: $(bindgen --version)"
else
    step "Running: cargo install bindgen-cli"
    cargo install bindgen-cli
    step "bindgen: $(bindgen --version)"
fi
echo

info "Step 5/5: Verifying"
step "openssl: $(openssl version)"
step "cargo:   $(cargo --version)"
if [[ -d "$SRCDIR/linux-fairydust" ]]; then
    step "Running: make rustavailable in linux-fairydust"
    if make -C "$SRCDIR/linux-fairydust" rustavailable; then
        step "Kernel Rust support is available"
    else
        warn "make rustavailable failed - the kernel may need a specific rustc version"
        warn "Check scripts/min-tool-version.sh rustc in the tree and pin it with:"
        warn "  rustup override set <version>"
    fi
else
    step "No linux-fairydust tree yet - skipping make rustavailable"
fi
echo

info "Preparation complete!"
echo
echo "  Before building, load the Rust toolchain into your shell:"
echo "    source ~/.cargo/env"
echo
echo "  Then build the kernel:"
echo "    ./fairydust-asahi-fedora.sh"
echo
