# EVDI Headless 240Hz Virtual Monitor

A reproducible headless Linux virtual-monitor setup using **EVDI**, a custom EDID, a persistent userspace EVDI daemon, high-refresh DRM vblank timing, KDE Plasma/Wayland, Sunshine, and Moonlight.

The project creates a persistent virtual DRM display that can be used as a remote-monitor target without requiring a physical monitor to be connected to the virtual output.

> **Project type:** tutorial / reproducibility project
> **Version:** 1.0.0

---

## 1. What this project does

This project provides:

* EVDI 1.15.0 kernel module setup
* A local vblank timing fix based on EVDI PR #562
* A custom 1152-byte EDID containing high-refresh modes
* A persistent EVDI userspace daemon
* Automatic EVDI module loading during boot
* KDE Plasma/Wayland display positioning
* A Plasma Login Manager watcher
* A logged-in Plasma side-by-side watcher
* Sunshine/Moonlight compatibility
* An installer
* An uninstaller
* Reproducible verification commands

The intended display arrangement is:

```text
┌──────────────────────────┐  ┌──────────────────────────┐
│                          │  │                          │
│      Physical HDMI       │  │       EVDI DVI-I-1       │
│                          │  │                          │
│      card1 / amdgpu      │  │       card0 / EVDI       │
│                          │  │                          │
└──────────────────────────┘  └──────────────────────────┘
```

The EVDI display is automatically positioned immediately to the right of the physical HDMI display.

---

## 2. Tested environment

The known-good configuration used while developing this repository was:

| Component          | Tested configuration  |
| ------------------ | --------------------- |
| Distribution       | Arch Linux / CachyOS  |
| Kernel             | `7.2.2-1-cachyos`     |
| GPU                | AMD Radeon RX 6700 XT |
| Desktop            | KDE Plasma            |
| Session            | Wayland               |
| EVDI               | 1.15.0                |
| Compiler           | Clang 22.1.8          |
| LTO                | ThinLTO               |
| Virtual connector  | `DVI-I-1`             |
| Physical connector | `HDMI-A-1`            |
| Tested active mode | `2560x1440@239.91 Hz` |
| EDID               | 1152 bytes / 9 blocks |
| Streaming          | Sunshine + Moonlight  |

Other distributions, kernels, GPUs, and desktop environments may work, but they are not part of the known-good test configuration.

---

## 3. Important distinction: EDID vs tested refresh rate

The repository contains a custom EDID with high-resolution/high-refresh modes, including:

```text
3840x2160 @ 239.887814 Hz
```

However, the actively tested EVDI configuration used:

```text
2560x1440 @ 239.91 Hz
```

The presence of a 4K240 mode in the EDID does **not** mean that 4K240 streaming was validated.

The project should therefore not be described as a tested 4K240 streaming solution.

---

## 4. EVDI vblank timing fix

The repository contains:

```text
patches/evdi-pr562-vblank.patch
```

This is based on EVDI pull request #562:

> `drm: implement hrtimer-based vblank for proper frame pacing`

At the time this project was tested, PR #562 had **not been merged upstream**.

The patch is therefore deliberately kept in this repository.

If PR #562 is eventually merged upstream, do not automatically remove this patch. A newer EVDI version should first be tested independently.

---

## 5. Repository layout

```text
.
├── edid/
│   └── vkms-final-30modes-4k240.bin
│
├── install/
│   └── install.sh
│
├── patches/
│   └── evdi-pr562-vblank.patch
│
├── scripts/
│   ├── evdi-persistent
│   ├── evdi-persistent-good.c
│   ├── evdi_lib.h
│   ├── evdi_layout_common.py
│   ├── evdi-layout-reset
│   ├── evdi-plasmalogin-watch
│   └── evdi-side-by-side-watch
│
├── systemd/
│   ├── evdi-persistent.service
│   ├── evdi-plasmalogin-watch.service
│   ├── evdi-side-by-side.service
│   └── sunshine-override.conf
│
├── uninstall/
│   └── uninstall.sh
│
├── VERSION
└── README.md
```

---

## 6. EVDI daemon

The persistent daemon creates and maintains the EVDI virtual display.

The daemon is installed as:

```text
/usr/local/bin/evdi-persistent
```

The systemd service is:

```text
evdi-persistent.service
```

The service starts before the display manager and restarts automatically if the daemon exits.

---

## 7. Kernel module installation

The installer builds EVDI for the currently running kernel.

The resulting module is installed as:

```text
/lib/modules/<kernel-version>/updates/evdi.ko
```

For example:

```text
/lib/modules/7.2.2-1-cachyos/updates/evdi.ko
```

The installer intentionally does not use EVDI's hard-coded `modules_install` destination.

This avoids placing the module under an unexpected kernel DRM path and avoids interfering with an existing module installation.

---

## 8. External EVDI configuration

The following files may exist outside this repository:

```text
/etc/modules-load.d/evdi.conf
/etc/modprobe.d/evdi.conf
```

These are system configuration files and are not owned by this project.

The installer does not replace them.

The uninstaller does not remove them.

---

## 9. Plasma Login Manager watcher

The Login Manager watcher is:

```text
/usr/local/bin/evdi-plasmalogin-watch
```

with:

```text
evdi-plasmalogin-watch.service
```

It operates in the Plasma Login Manager Wayland session.

Its current purpose is simple:

**Keep the EVDI output disabled while the login screen is displayed.**

The EVDI kernel module is not unloaded.

Only the display output is disabled.

This allows the EVDI device to remain available for the logged-in Plasma session.

---

## 10. Logged-in Plasma watcher

The logged-in watcher is:

```text
/usr/local/bin/evdi-side-by-side-watch
```

and is run by:

```text
evdi-side-by-side.service
```

It monitors the KDE display layout.

When using the default layout, the EVDI output is placed immediately to the right of the physical display.

For example:

```text
Physical HDMI:
0,0 1920x1080

EVDI:
1920,0 2560x1440
```

The watcher does not continuously overwrite a manually selected custom layout.

A custom layout can therefore be preserved.

---

## 11. Layout state

Layout state is stored at:

```text
/var/lib/evdi-headless/layout-state.json
```

The shared Python helper is installed as:

```text
/usr/local/lib/evdi_layout_common.py
```

The helper provides common:

* KScreen parsing
* DRM connector discovery
* EVDI detection
* layout state handling

The reset utility is:

```text
/usr/local/bin/evdi-layout-reset
```

---

## 12. Sunshine and Moonlight

Sunshine is used as the streaming server and Moonlight as the remote client.

Sunshine remains responsible for:

* screen capture
* encoding
* streaming

Moonlight remains responsible for:

* connecting to Sunshine
* receiving the stream
* displaying the remote desktop

The project does **not** currently attempt to automatically enable or disable EVDI based on Sunshine streaming-session state.

This is intentional.

Sunshine may select a display independently of the EVDI output state, so tying EVDI state directly to connection events is not considered sufficiently reliable for the core reproducibility setup.

Automatic Sunshine/EVDI coordination may be investigated separately in the future.

---

## 13. Sunshine service

The expected user service is:

```text
app-dev.lizardbyte.app.Sunshine.service
```

The repository contains:

```text
systemd/sunshine-override.conf
```

which provides the required early-session ordering.

The override intentionally does not bind Sunshine to:

```text
graphical-session.target
```

This allows Sunshine to remain available as intended by the tested configuration.

---

## 14. Installation

Clone the repository:

```fish
git clone https://github.com/sufianahmed2007/evdi-headless-240hz-virtual-monitor.git
cd evdi-headless-240hz-virtual-monitor
```

Run:

```fish
sudo bash install/install.sh
```

The installer:

1. Checks the environment.
2. Locates EVDI 1.15.0.
3. Applies the local vblank patch when required.
4. Builds EVDI.
5. Installs the kernel module.
6. Runs `depmod`.
7. Installs the persistent EVDI daemon.
8. Installs the EDID.
9. Installs the shared layout helper.
10. Installs the Plasma watchers.
11. Installs the systemd services.
12. Enables the required services.
13. Configures the Sunshine user-service override.

---

## 15. Verify the installation

Check the kernel module:

```fish
uname -r
modinfo evdi | grep -E 'filename|version|vermagic'
```

Expected module location:

```text
/lib/modules/<kernel-version>/updates/evdi.ko
```

Check the persistent service:

```fish
systemctl status evdi-persistent.service --no-pager
```

Check the Login Manager watcher:

```fish
systemctl status evdi-plasmalogin-watch.service --no-pager
```

Check the logged-in watcher:

```fish
systemctl --user status evdi-side-by-side.service --no-pager
```

Check the DRM connectors:

```fish
kscreen-doctor -o
```

The virtual connector should appear as:

```text
DVI-I-1
```

---

## 16. Verify the high-refresh mode

Run:

```fish
kscreen-doctor -o
```

Look for:

```text
2560x1440@239.91
```

The exact formatting may differ between KDE/KScreen versions.

The kernel-side mode can also be inspected through DRM debugfs.

The tested timing was approximately:

```text
2560x1440
pixel clock: 1056510 kHz
htotal: 2720
vtotal: 1619
refresh: ~239 Hz
```

The corresponding vblank period was approximately:

```text
4168138 ns
```

---

## 17. Verify the EVDI vblank timing

Kernel logs should contain an EVDI vblank message similar to:

```text
evdi: [I] vblank: mode=2560x1440 clock=1056510 htotal=2720 vtotal=1619 period=4168138 ns
```

This confirms that the high-refresh vblank timing path is active.

---

## 18. Default display layout

The default layout is:

```text
┌──────────────────┐┌──────────────────────┐
│                  ││                      │
│   HDMI physical  ││     EVDI virtual     │
│                  ││                      │
└──────────────────┘└──────────────────────┘
```

The EVDI display starts at:

```text
physical_x + physical_width
```

and uses the same Y coordinate as the physical display.

---

## 19. Custom layouts

The logged-in watcher detects manual layout changes.

Once a custom layout is detected, it is saved in:

```text
/var/lib/evdi-headless/layout-state.json
```

The watcher then stops enforcing the default automatic position.

To reset the saved layout state:

```fish
sudo /usr/local/bin/evdi-layout-reset
```

After resetting, restart the logged-in watcher:

```fish
systemctl --user restart evdi-side-by-side.service
```

---

## 20. Login-screen behavior

The Login Manager watcher operates independently from the logged-in Plasma watcher.

At the Plasma login screen:

```text
EVDI module: loaded
EVDI output: disabled
```

After logging in:

```text
EVDI module: loaded
EVDI output: available
```

The project does not unload the EVDI kernel module merely because the display is not currently being used.

---

## 21. Reboot persistence

The intended result after reboot is:

1. The EVDI kernel module is available.
2. The persistent EVDI daemon starts.
3. The EVDI DRM connector exists.
4. The Login Manager watcher keeps the virtual output disabled at the login screen.
5. Plasma starts normally.
6. The logged-in watcher maintains the configured layout.
7. Sunshine can use the display when configured for remote streaming.

A full reboot should therefore be used as the final persistence test.

---

## 22. Uninstallation

Run:

```fish
sudo bash uninstall/uninstall.sh
```

The uninstaller removes files installed by this repository, including:

```text
/usr/local/bin/evdi-persistent
/usr/local/bin/evdi-plasmalogin-watch
/usr/local/bin/evdi-side-by-side-watch
/usr/local/bin/evdi-layout-reset
/usr/local/lib/evdi_layout_common.py
/lib/modules/<kernel-version>/updates/evdi.ko
```

It also removes the systemd units and project state owned by the installer.

It intentionally leaves external EVDI configuration files such as:

```text
/etc/modules-load.d/evdi.conf
/etc/modprobe.d/evdi.conf
```

untouched.

---

## 23. Troubleshooting

### EVDI connector is disconnected

Check:

```fish
lsmod | grep evdi
```

Then:

```fish
systemctl status evdi-persistent.service --no-pager
```

Check the connector:

```fish
kscreen-doctor -o
```

---

### EVDI service is not running

Check:

```fish
journalctl -u evdi-persistent.service -b --no-pager
```

Then:

```fish
systemctl restart evdi-persistent.service
```

---

### EVDI is on the wrong side

Check:

```fish
systemctl --user status evdi-side-by-side.service --no-pager
```

Then:

```fish
systemctl --user restart evdi-side-by-side.service
```

---

### Login screen shows the virtual display

Check:

```fish
systemctl status evdi-plasmalogin-watch.service --no-pager
```

Check the greeter Wayland socket:

```fish
sudo find /run/user -maxdepth 2 -type s -name 'wayland-*' -ls
```

The watcher requires the Plasma Login Manager Wayland session to be available.

---

### High-refresh mode is missing

Check the EDID:

```fish
edid-decode edid/vkms-final-30modes-4k240.bin
```

Then check:

```fish
kscreen-doctor -o
```

Also verify the EVDI module was built for the currently running kernel:

```fish
uname -r
modinfo evdi | grep vermagic
```

---

### Vblank timing is incorrect

Check:

```fish
journalctl -k -b | grep -i evdi
```

Look for the high-refresh vblank message.

Verify that:

```text
patches/evdi-pr562-vblank.patch
```

was applied during the build.

---

### Sunshine is not running

Check:

```fish
systemctl --user status app-dev.lizardbyte.app.Sunshine.service --no-pager
```

Restart:

```fish
systemctl --user restart app-dev.lizardbyte.app.Sunshine.service
```

Check the logs:

```fish
journalctl --user -u app-dev.lizardbyte.app.Sunshine.service -n 100 --no-pager
```

---

## 24. Known-good Sunshine capture

When Sunshine successfully captures the EVDI display, its logs should identify the EVDI DRM device and connector.

A successful configuration previously produced messages similar to:

```text
/dev/dri/card0 -> evdi
/dev/dri/card1 -> amdgpu
Screencasting with KMS
Mapped 'DVI-I-1' to kmsgrab monitor index 0
```

The exact monitor index may vary depending on the current display configuration.

---

## 25. What this project does not promise

This repository does not promise:

* 4K240 streaming
* identical behavior on every GPU
* identical behavior on every kernel
* automatic support for future EVDI versions
* automatic upstream patch removal
* automatic Sunshine/EVDI session switching
* automatic Tailscale configuration
* automatic Wake-on-LAN configuration
* router configuration

The tested configuration is the reference implementation.

---

## 26. Updating EVDI

This is a reproducibility project rather than a package manager.

It intentionally does not:

* track the newest EVDI release automatically
* automatically rebuild whenever EVDI changes
* automatically remove local patches
* provide an `evdi-headless-update` command

When changing EVDI versions, test the new version deliberately.

In particular, if PR #562 becomes part of upstream EVDI, verify the upstream implementation before removing the local patch.

---

## 27. Verification before committing changes

Run:

```fish
bash -n install/install.sh
```

Then:

```fish
python3 -m py_compile \
    scripts/evdi_layout_common.py \
    scripts/evdi-side-by-side-watch \
    scripts/evdi-plasmalogin-watch
```

Then:

```fish
sh -n scripts/evdi-layout-reset
```

Then:

```fish
git diff --check
```

Finally:

```fish
git status
```

Do not commit until the complete diff has been reviewed.

---

## 28. Project status

Current known-good configuration:

```text
EVDI:                  1.15.0
Vblank fix:            PR #562 applied locally
EDID:                  1152 bytes / 9 blocks
Tested mode:           2560x1440 @ 239.91 Hz
4K240 EDID mode:       present
4K240 streaming:       not validated
Physical connector:    HDMI-A-1
Virtual connector:     DVI-I-1
Desktop:               KDE Plasma Wayland
Streaming server:      Sunshine
Streaming client:      Moonlight
```

The core EVDI virtual-monitor setup has been tested across reboot and successfully used for remote Moonlight streaming.

---

## 29. Future work

Possible future improvements include:

* automatic EVDI enable/disable based on remote-session state
* more robust display-target selection for Sunshine
* additional GPU/kernel testing
* newer EVDI compatibility testing
* upstream PR #562 retesting after merge
* additional display layouts
* automated regression tests

These are intentionally outside the current known-good core.

---

## License and upstream components

This project integrates and patches third-party software.

EVDI is developed by DisplayLink and its contributors.

Sunshine and Moonlight are separate projects.

Users should consult the respective upstream repositories and licenses for those components.

---

## Summary

The project provides a persistent EVDI virtual DRM display with a custom high-refresh EDID and corrected vblank timing.

The tested configuration provides:

```text
Physical HDMI
      │
      ├── AMDGPU
      │
      └── KDE Plasma
             │
             └── EVDI DVI-I-1
                    │
                    └── Sunshine
                           │
                           └── Moonlight
```

The setup is designed to be reproducible, inspectable, and removable without modifying unrelated system configuration.
