#!/usr/bin/env bash
set -euo pipefail

EVDI_VERSION="1.15.0"
EVDI_SRC="/usr/local/src/evdi-${EVDI_VERSION}"
EVDI_LIBDIR="/usr/local/lib"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON_SRC="$REPO_ROOT/scripts/evdi-persistent-good.c"
DAEMON_BIN="/usr/local/bin/evdi-persistent"
EDID_SRC="$REPO_ROOT/edid/vkms-final-30modes-4k240.bin"
EDID_DST="/usr/lib/firmware/edid/vkms-final-30modes-4k240.bin"

KVER="$(uname -r)"
KDIR="/lib/modules/${KVER}/build"

echo "==> Checking EVDI source..."
if [ ! -d "$EVDI_SRC" ]; then
    echo "ERROR: EVDI source not found at $EVDI_SRC" >&2
    exit 1
fi

PATCH_FILE="$REPO_ROOT/patches/evdi-pr562-vblank.patch"

if [ ! -f "$PATCH_FILE" ]; then
    echo "ERROR: EVDI patch not found at $PATCH_FILE" >&2
    exit 1
fi

echo "==> Checking EVDI vblank patch..."
if grep -q "struct hrtimer vblank_timer;" "$EVDI_SRC/module/evdi_drm_drv.h"    && grep -q "evdi_vblank_timer_fn" "$EVDI_SRC/module/evdi_modeset.c"    && ! grep -q "evdi_painter_set_vblank" "$EVDI_SRC/module/evdi_painter.c"; then
    echo "    EVDI vblank patch already applied."
else
    echo "    Applying EVDI vblank patch..."
    cd "$EVDI_SRC"
    git apply --check "$PATCH_FILE"
    git apply "$PATCH_FILE"
    echo "    EVDI vblank patch applied successfully."
fi

echo "==> Checking kernel build tree..."
if [ ! -d "$KDIR" ]; then
    echo "ERROR: Kernel build tree not found at $KDIR" >&2
    exit 1
fi

echo "==> Checking Clang..."
if ! command -v clang >/dev/null 2>&1; then
    echo "ERROR: clang is required to build EVDI for this kernel." >&2
    exit 1
fi

echo "==> Building patched EVDI kernel module..."
cd "$EVDI_SRC/module"
make clean
make CC=clang LLVM=1 module

echo "==> Installing EVDI kernel module..."
make RUN_DEPMOD=1 install

echo "==> Building libevdi ${EVDI_VERSION}..."
cd "$EVDI_SRC/library"
make clean
make

echo "==> Installing libevdi ${EVDI_VERSION}..."
install -Dm755 "libevdi.so.${EVDI_VERSION}" "$EVDI_LIBDIR/libevdi.so.${EVDI_VERSION}"
ln -sfn "libevdi.so.${EVDI_VERSION}" "$EVDI_LIBDIR/libevdi.so.1"
ln -sfn "libevdi.so.1" "$EVDI_LIBDIR/libevdi.so"

echo "==> Updating dynamic linker cache..."
ldconfig

echo "==> Building persistent EVDI daemon..."
if [ ! -f "$DAEMON_SRC" ]; then
    echo "ERROR: daemon source not found: $DAEMON_SRC" >&2
    exit 1
fi

gcc -I"$REPO_ROOT/scripts" -I"$EVDI_SRC/module" "$DAEMON_SRC" -L"$EVDI_LIBDIR" -levdi -o /tmp/evdi-persistent-build

echo "==> Installing persistent EVDI daemon..."
install -Dm755 /tmp/evdi-persistent-build "$DAEMON_BIN"
rm -f /tmp/evdi-persistent-build

echo "==> Installing EDID..."
if [ ! -f "$EDID_SRC" ]; then
    echo "ERROR: EDID not found: $EDID_SRC" >&2
    exit 1
fi

install -Dm644 "$EDID_SRC" "$EDID_DST"

echo "==> Installation completed."
echo "==> Installed kernel module:"
modinfo evdi | grep -E "^(filename|vermagic):"

echo "==> Installed daemon dependencies:"
ldd "$DAEMON_BIN"

echo "==> Installed EDID:"
ls -l "$EDID_DST"
