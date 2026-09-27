# Omarchy testing handoff

You are the dedicated maintainer/test agent for Scarlett Gain Overlay on `omarchy`.

## Current state

- Source: `~/Applications/scarlett-gain-overlay`
- Installed binary: `~/.local/bin/scarlett-gain-overlay`
- Hyprland launcher: `~/.local/bin/scarlett-gain-overlay-launch`
- User service: `~/.config/systemd/user/scarlett-gain-overlay.service`
- Theme hook: `~/.config/omarchy/hooks/theme-set.d/scarlett-gain-overlay`
- Service is enabled and retries when the device is absent.
- UI demo has been verified on Hyprland at 174x88, floating and pinned.
- Omarchy theme loading has been verified against the active `colors.toml`.
- As of 2026-09-28 01:43 CEST, no Focusrite USB device was present in `/sys/bus/usb/devices`; the service correctly reported `DeviceNotFound`. Live gain detection therefore remains to be tested on this host.

## Hardware/protocol

- Focusrite Scarlett 2i2 4th Gen
- USB VID:PID `1235:8219`
- Vendor interface 3, interrupt endpoint `0x83`
- Two gain bytes at FCP offset `0x4b`
- Gain notification mask `0x40000000`
- Tested firmware on macOS: 2417

## Test procedure after the Scarlett is physically connected

1. Confirm detection without relying on `lsusb`:

   ```sh
   for d in /sys/bus/usb/devices/*; do
     [ -r "$d/idVendor" ] || continue
     [ "$(cat "$d/idVendor")" = 1235 ] || continue
     echo "$(cat "$d/idVendor"):$(cat "$d/idProduct") $(cat "$d/product" 2>/dev/null) $d"
   done
   ```

2. Restart and inspect the service:

   ```sh
   systemctl --user restart scarlett-gain-overlay.service
   systemctl --user status scarlett-gain-overlay.service
   journalctl --user -u scarlett-gain-overlay.service -f
   ```

3. Turn input gain for both channels and verify the HUD appears.
4. Capture proof with:

   ```sh
   WAYLAND_DISPLAY=wayland-1 grim ~/Pictures/scarlett-gain-overlay-live.png
   ```

## Likely Linux issue: USB permissions

If the device is found but the app reports `DeviceNotFound` or `InterfaceBusy`, inspect `/dev/bus/usb/BBB/DDD` ownership/ACL. Install the included rule if needed:

```sh
sudo install -m 0644 packaging/linux/70-scarlett-gain-overlay.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Reconnect the Scarlett afterward. The app calls `libusb_set_auto_detach_kernel_driver` only for vendor interface 3; audio streaming interfaces should stay with ALSA. Also ensure no Focusrite control process is claiming the vendor interface.

## Useful commands

```sh
./scripts/run-hyprland.sh --demo
systemctl --user stop scarlett-gain-overlay.service
cd ~/Applications/scarlett-gain-overlay && zig build -Doptimize=ReleaseSafe
```

Do not declare Linux hardware support verified until a physical knob change has produced the correct channel/gain overlay.
