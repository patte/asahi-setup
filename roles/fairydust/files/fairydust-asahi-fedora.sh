#!/usr/bin/env bash
set -euo pipefail

# fairydust.sh - Build and install the Asahi Linux fairydust kernel on Fedora
# Usage: ./fairydust.sh [build|install|all]
#   build   - clone (if needed) and compile the kernel
#   install - install modules, kernel, fix DTBs, update m1n1
#   all     - do both (default)

BRANCH="fairydust"
REPO="https://github.com/AsahiLinux/linux.git"
LOCALVERSION="-asahi-fairydust"
SRCDIR="$(cd "$(dirname "$0")" && pwd)"
JOBS="$(nproc)"

info()  { echo -e "\033[1;35m==>\033[0m \033[1m$*\033[0m"; }
warn()  { echo -e "\033[1;33m==> WARNING:\033[0m $*"; }
error() { echo -e "\033[1;31m==> ERROR:\033[0m $*" >&2; exit 1; }
step()  { echo -e "\033[1;36m  ->\033[0m $*"; }

build() {
    info "Step 1/4: Installing build dependencies"
    step "Running: dnf install make automake gcc gcc-c++ openssl-devel ncurses-devel flex bison"
    sudo dnf install -y make automake gcc gcc-c++ openssl-devel ncurses-devel flex bison
    echo

    # Clone if we're not already inside the fairydust tree, otherwise pull
    info "Step 2/4: Preparing source tree"
    if ! git -C "$SRCDIR" rev-parse --is-inside-work-tree &>/dev/null || \
       [[ "$(git -C "$SRCDIR" branch --show-current 2>/dev/null)" != "$BRANCH" ]]; then
        if [[ -d "$SRCDIR/linux-fairydust/.git" ]]; then
            SRCDIR="$SRCDIR/linux-fairydust"
            step "Existing tree at $SRCDIR - pulling branch $BRANCH"
            git -C "$SRCDIR" fetch --depth 1 origin "$BRANCH"
            git -C "$SRCDIR" checkout -B "$BRANCH" FETCH_HEAD
        elif [[ -e "$SRCDIR/linux-fairydust" ]]; then
            error "$SRCDIR/linux-fairydust exists but is not a git repository"
        else
            step "Cloning $REPO (branch: $BRANCH)"
            git clone -b "$BRANCH" --single-branch --depth 1 "$REPO" "$SRCDIR/linux-fairydust"
            SRCDIR="$SRCDIR/linux-fairydust"
        fi
    else
        step "Already inside fairydust tree at $SRCDIR - pulling branch $BRANCH"
        git -C "$SRCDIR" pull --depth 1 origin "$BRANCH"
    fi
    echo

    cd "$SRCDIR"

    info "Step 3/4: Configuring kernel"
    if [[ -f /boot/config-$(uname -r) ]]; then
        step "Copying config from /boot/config-$(uname -r)"
        cp /boot/config-"$(uname -r)" .config
    elif [[ -f /proc/config.gz ]]; then
        step "Extracting config from /proc/config.gz"
        gunzip -c /proc/config.gz > .config
    else
        error "No kernel config found to use as base"
    fi

    step "Setting CONFIG_LOCALVERSION=\"${LOCALVERSION}\""
    sed -i "s/CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"${LOCALVERSION}\"/" .config

    step "Running make olddefconfig (accepting defaults for new options)"
    make LOCALVERSION= olddefconfig
    echo

    info "Step 4/4: Compiling kernel with $JOBS parallel jobs"
    step "Running: make LOCALVERSION= -j$JOBS"
    make LOCALVERSION= -j"$JOBS"

    KVER=$(make LOCALVERSION= -s kernelrelease)
    echo
    info "Build complete: $KVER"
    step "Kernel image: $SRCDIR/arch/arm64/boot/Image"
    step "DTBs:         $SRCDIR/arch/arm64/boot/dts/apple/"
    echo
}

install_kernel() {
    # When run standalone, SRCDIR still points at the script dir
    [[ -d "$SRCDIR/linux-fairydust" ]] && SRCDIR="$SRCDIR/linux-fairydust"
    cd "$SRCDIR"
    KVER=$(make LOCALVERSION= -s kernelrelease)
    local MODDIR="/usr/lib/modules/$KVER"

    echo
    info "Installing kernel $KVER"
    echo

    # --- modules ---
    info "Step 1/5: Installing modules (stripped)"
    step "Running: make INSTALL_MOD_STRIP=1 modules_install"
    sudo make LOCALVERSION= INSTALL_MOD_STRIP=1 modules_install
    step "Modules installed to $MODDIR"
    echo

    # --- DTBs into module dir ---
    # update-m1n1 (called by make install via 15-update-m1n1.install) expects
    # DTBs at /usr/lib/modules/$KVER/dtb/apple/*.dtb when the /boot/dtb
    # symlink target doesn't exist yet. Install them there BEFORE make install.
    info "Step 2/5: Installing DTBs into modules directory"
    step "Target: $MODDIR/dtb/apple/"
    sudo mkdir -p "$MODDIR/dtb/apple"
    sudo cp -v "$SRCDIR"/arch/arm64/boot/dts/apple/*.dtb "$MODDIR/dtb/apple/"
    step "$(ls "$MODDIR"/dtb/apple/*.dtb 2>/dev/null | wc -l) DTB files installed"
    echo

    # --- VDSO ---
    info "Step 3/5: Installing VDSO"
    step "Running: make vdso_install"
    sudo make LOCALVERSION= vdso_install
    echo

    # --- kernel image (this also triggers update-m1n1 via install hooks) ---
    info "Step 4/5: Installing kernel image"
    step "Running: make install"
    step "This will also trigger update-m1n1 via /usr/lib/kernel/install.d/15-update-m1n1.install"
    sudo make LOCALVERSION= install
    echo

    # --- dtbs_install for /boot/dtb-$KVER (used by grub/BLS) ---
    info "Step 5/5: Installing DTBs to /boot and fixing paths"
    step "Running: make dtbs_install"
    sudo make LOCALVERSION= dtbs_install

    # Fix the /boot/dtbs/$KVER -> /boot/dtb-$KVER mismatch if needed
    if [[ -d /boot/dtbs/$KVER && ! -d /boot/dtb-$KVER ]]; then
        step "Fixing DTB path: /boot/dtbs/$KVER -> /boot/dtb-$KVER"
        sudo mv "/boot/dtbs/$KVER" "/boot/dtb-$KVER"
    elif [[ -d /boot/dtb-$KVER ]]; then
        step "DTB path /boot/dtb-$KVER already correct"
    else
        warn "Could not find DTB directory at /boot/dtbs/$KVER or /boot/dtb-$KVER - verify manually!"
    fi
    echo

    # Set as default boot kernel
    if command -v grubby &>/dev/null && [[ -f /boot/vmlinuz-$KVER ]]; then
        step "Setting $KVER as default boot kernel via grubby"
        sudo grubby --set-default "/boot/vmlinuz-$KVER"
    fi

    echo
    info "Installation complete!"
    echo
    echo "  Verify everything looks correct:"
    echo "    ls -la /boot/vmlinuz-$KVER"
    echo "    ls -la /boot/dtb-$KVER/apple/"
    echo "    ls -la $MODDIR/dtb/apple/"
    echo "    ls -la /boot/dtb"
    echo
    echo "  When ready:"
    echo "    sudo reboot"
    echo
}

ACTION="${1:-all}"
case "$ACTION" in
    build)   build ;;
    install) install_kernel ;;
    all)     build; install_kernel ;;
    *)       echo "Usage: $0 [build|install|all]"; exit 1 ;;
esac
