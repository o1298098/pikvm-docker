# Pikvm-docker

EN | [中文](README.zh-CN.md)

Deployment Steps

The container runs **PiKVM kvmd**; it ingests video from a capture card and provides an **H.264** encoded stream/output. USB gadget is configured on the host.

### 1) Build Docker image

```bash
docker build -t pikvm-kvmd:local .
```

### 2) Run container

Two optional deployment options:

Option A (recommended): privileged + mount host devices

```bash
docker run --rm -it --privileged --network host \
  -v /dev:/dev -v /sys:/sys -v /run:/run \
  pikvm-kvmd:local
```

Option B: explicit device mapping

```bash
docker run --rm -it \
  --device /dev/hidg1:/dev/kvmd-hid-mouse \
  --device /dev/hidg0:/dev/kvmd-hid-keyboard \
  --device /dev/video0:/dev/kvmd-video \
  --device /dev/video11:/dev/video11 \
  -v /path/to/override.yaml:/etc/kvmd/override.yaml:ro \
  -p 443:443 \
  o1298098/pikvm
```

If your device nodes differ, replace `hidg*` / `video*` accordingly.

### 3) Enable USB Gadget on the host (HID keyboard/mouse)

1. Edit `/boot/config.txt` (in `[all]`):

```ini
dtoverlay=dwc2,dr_mode=peripheral
```

2. Edit `/boot/cmdline.txt` (append to the existing single line):

```txt
modules-load=dwc2,g_ether
```

If you want HID-only, use:

```txt
modules-load=dwc2,g_hid
```

3. Fix the shared gadget script path (run once on the host; replace repo path):

```bash
cd /path/to/pikvm-docker/usb_gadgets.sh
mkdir -p lib
ln -sf "$(pwd)/usb-gadget" lib/usb-gadget.sh
```

4. Activate:

```bash
sudo /path/to/pikvm-docker/usb_gadgets.sh/init-usb-gadgets
```

5. Verify:

```bash
ls /sys/kernel/config/usb_gadget
```

### 4) Disable (optional)

```bash
sudo /path/to/pikvm-docker/usb_gadgets.sh/remove-usb-gadgets
```

Optional: `usb_gadgets.sh/usb-gadget.service` is a `systemd` oneshot example (edit the placeholder `ExecStart/ExecStop` paths if you use it).
