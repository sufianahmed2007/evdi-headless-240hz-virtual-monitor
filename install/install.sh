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

SIDE_BY_SIDE_SRC="$REPO_ROOT/scripts/evdi-side-by-side-watch"
PLASMALOGIN_WATCH_SRC="$REPO_ROOT/scripts/evdi-plasmalogin-watch"
LAYOUT_COMMON_SRC="$REPO_ROOT/scripts/evdi_layout_common.py"
LAYOUT_RESET_SRC="$REPO_ROOT/scripts/evdi-layout-reset"
PERSISTENT_SERVICE_SRC="$REPO_ROOT/systemd/evdi-persistent.service"
PLASMALOGIN_SERVICE_SRC="$REPO_ROOT/systemd/evdi-plasmalogin-watch.service"
SIDE_BY_SIDE_SERVICE_SRC="$REPO_ROOT/systemd/evdi-side-by-side.service"
SUNSHINE_OVERRIDE_SRC="$REPO_ROOT/systemd/sunshine-override.conf"

SIDE_BY_SIDE_BIN="/usr/local/bin/evdi-side-by-side-watch"
PLASMALOGIN_WATCH_BIN="/usr/local/bin/evdi-plasmalogin-watch"
LAYOUT_COMMON_BIN="/usr/local/lib/evdi_layout_common.py"
LAYOUT_RESET_BIN="/usr/local/bin/evdi-layout-reset"
LAYOUT_STATE_DIR="/var/lib/evdi-headless"
LAYOUT_STATE_FILE="$LAYOUT_STATE_DIR/layout-state.json"
SYSTEMD_SYSTEM_DIR="/etc/systemd/system"

INSTALL_USER="${SUDO_USER:-${USER}}"
if [ "$INSTALL_USER" = "root" ]; then
    echo "ERROR: Run this installer with sudo from your normal desktop user." >&2
    exit 1
fi

INSTALL_HOME="$(getent passwd "$INSTALL_USER" | cut -d: -f6)"
if [ -z "$INSTALL_HOME" ] || [ ! -d "$INSTALL_HOME" ]; then
    echo "ERROR: Could not determine home directory for $INSTALL_USER" >&2
    exit 1
fi

USER_SYSTEMD_DIR="$INSTALL_HOME/.config/systemd/user"
SUNSHINE_OVERRIDE_DIR="$USER_SYSTEMD_DIR/app-dev.lizardbyte.app.Sunshine.service.d"

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
install -Dm644 evdi.ko "/lib/modules/$KVER/updates/evdi.ko"
depmod -a "$KVER"

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

echo "==> Installing EVDI services and watchers..."

for f in "$PERSISTENT_SERVICE_SRC" "$PLASMALOGIN_SERVICE_SRC" "$SIDE_BY_SIDE_SERVICE_SRC" "$SUNSHINE_OVERRIDE_SRC" "$SIDE_BY_SIDE_SRC" "$PLASMALOGIN_WATCH_SRC" "$LAYOUT_COMMON_SRC" "$LAYOUT_RESET_SRC"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Required project file not found: $f" >&2
        exit 1
    fi
done

install -Dm755 "$SIDE_BY_SIDE_SRC" "$SIDE_BY_SIDE_BIN"
install -Dm755 "$LAYOUT_COMMON_SRC" "$LAYOUT_COMMON_BIN"
install -Dm755 "$LAYOUT_RESET_SRC" "$LAYOUT_RESET_BIN"

install -d -m 0755 "$LAYOUT_STATE_DIR"
chown "$INSTALL_USER:$INSTALL_USER" "$LAYOUT_STATE_DIR"
if [ -f "$LAYOUT_STATE_FILE" ]; then
    chown "$INSTALL_USER:$INSTALL_USER" "$LAYOUT_STATE_FILE"
    chmod 0644 "$LAYOUT_STATE_FILE"
fi

install -Dm755 "$PLASMALOGIN_WATCH_SRC" "$PLASMALOGIN_WATCH_BIN"
install -Dm644 "$PERSISTENT_SERVICE_SRC" "$SYSTEMD_SYSTEM_DIR/evdi-persistent.service"
install -Dm644 "$PLASMALOGIN_SERVICE_SRC" "$SYSTEMD_SYSTEM_DIR/evdi-plasmalogin-watch.service"
install -Dm644 "$SIDE_BY_SIDE_SERVICE_SRC" "$USER_SYSTEMD_DIR/evdi-side-by-side.service"
install -Dm644 "$SUNSHINE_OVERRIDE_SRC" "$SUNSHINE_OVERRIDE_DIR/override.conf"

chown -R "$INSTALL_USER:$INSTALL_USER" "$USER_SYSTEMD_DIR"

systemctl daemon-reload
systemctl enable --now evdi-persistent.service
systemctl enable --now evdi-plasmalogin-watch.service

if [ -S "/run/user/$(id -u "$INSTALL_USER")/bus" ]; then
    runuser -u "$INSTALL_USER" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$INSTALL_USER")" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$INSTALL_USER")/bus" systemctl --user daemon-reload
    runuser -u "$INSTALL_USER" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$INSTALL_USER")" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$INSTALL_USER")/bus" systemctl --user enable --now evdi-side-by-side.service
    runuser -u "$INSTALL_USER" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$INSTALL_USER")" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$INSTALL_USER")/bus" systemctl --user enable --now app-dev.lizardbyte.app.Sunshine.service || true
else
    echo "WARNING: User session is not available; logged-in watcher and Sunshine will start on the next graphical login."
    runuser -u "$INSTALL_USER" -- systemctl --user enable evdi-side-by-side.service 2>/dev/null || true
fi

echo "==> Installation completed."
echo "==> Installed kernel module:"
modinfo evdi | grep -E "^(filename|vermagic):"

echo "==> Installed daemon dependencies:"
ldd "$DAEMON_BIN"

echo "==> Installed EDID:"
ls -l "$EDID_DST"
