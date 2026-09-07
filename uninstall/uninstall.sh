#!/usr/bin/env bash
set -euo pipefail

INSTALL_USER="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$INSTALL_USER" | cut -d: -f6)"

SYSTEMD_SYSTEM_DIR="/etc/systemd/system"
USER_SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
LAYOUT_STATE_DIR="/var/lib/evdi-headless"
EVDI_LIBDIR="/usr/local/lib"
EDID_FILE="/usr/lib/firmware/edid/vkms-final-30modes-4k240.bin"

echo "Removing EVDI headless virtual monitor project..."

systemctl disable --now evdi-persistent.service 2>/dev/null || true
systemctl disable --now evdi-plasmalogin-watch.service 2>/dev/null || true

if [ "$(id -u)" -eq 0 ]; then
    USER_UID="$(id -u "$INSTALL_USER")"
    if [ -d "/run/user/$USER_UID" ]; then
        runuser -u "$INSTALL_USER" -- systemctl --user disable --now evdi-side-by-side.service 2>/dev/null || true
    fi
fi

echo "==> Removing project-owned userspace files..."

rm -f     /usr/local/bin/evdi-persistent     /usr/local/bin/evdi-side-by-side-watch     /usr/local/bin/evdi-plasmalogin-watch     /usr/local/bin/evdi-layout-reset     /usr/local/lib/evdi_layout_common.py     "$EVDI_LIBDIR/libevdi.so.1.15.0"     "$EVDI_LIBDIR/libevdi.so.1"     "$EVDI_LIBDIR/libevdi.so"     "$EDID_FILE"     "$SYSTEMD_SYSTEM_DIR/evdi-persistent.service"     "$SYSTEMD_SYSTEM_DIR/evdi-plasmalogin-watch.service"     "$USER_SYSTEMD_DIR/evdi-side-by-side.service"     "$USER_SYSTEMD_DIR/sunshine.service.d/override.conf"

echo "==> Removing saved layout state..."

rm -rf "$LAYOUT_STATE_DIR"
rmdir "$USER_SYSTEMD_DIR/sunshine.service.d" 2>/dev/null || true

systemctl daemon-reload

if [ "$(id -u)" -eq 0 ]; then
    USER_UID="$(id -u "$INSTALL_USER")"
    if [ -d "/run/user/$USER_UID" ]; then
        runuser -u "$INSTALL_USER" -- systemctl --user daemon-reload 2>/dev/null || true
    fi
fi

echo "==> Handling EVDI kernel module..."

EVDI_MODULE="/lib/modules/$(uname -r)/updates/evdi.ko"

if [ -f "$EVDI_MODULE" ]; then
    if lsmod | grep -q "^evdi "; then
        echo "    EVDI is currently loaded; attempting to unload it..."
        if modprobe -r evdi 2>/dev/null; then
            echo "    EVDI kernel module unloaded."
        else
            echo "    WARNING: Project EVDI kernel module is still in use."
            echo "    It will NOT be forcibly removed."
            echo "    Reboot after uninstalling, then remove the module if necessary."
            EVDI_MODULE=""
        fi
    fi

    if [ -n "$EVDI_MODULE" ] && [ -f "$EVDI_MODULE" ]; then
        echo "    Removing project-installed EVDI module: $EVDI_MODULE"
        rm -f "$EVDI_MODULE"
        depmod -a "$(uname -r)"
    fi
else
    echo "    Project-installed EVDI module not found; leaving other EVDI modules untouched."
fi

echo
echo "EVDI headless virtual monitor project removed."
echo
echo "The following were NOT removed:"
echo "  - Sunshine"
echo "  - Moonlight"
echo "  - KDE Plasma"
echo "  - Linux kernel"
echo "  - EVDI source trees"
echo "  - unrelated system configuration"
echo
echo "A reboot may be required if EVDI could not be unloaded."
