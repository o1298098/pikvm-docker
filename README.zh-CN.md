# Pikvm-docker

中文 | [EN](README.md)

部署步骤

容器主要运行 **PiKVM kvmd**：通过采集卡进行视频采集，并提供 **H.264** 编码后的输出/流。USB gadget 由宿主机完成配置。

### 1）构建镜像

```bash
docker build -t pikvm-kvmd:local .
```

### 2）启动容器

可选两种 Docker 部署方案：

方案 A（推荐）：`--privileged` + 挂载宿主机设备

```bash
docker run --rm -it --privileged --network host \
  -v /dev:/dev -v /sys:/sys -v /run:/run \
  pikvm-kvmd:local
```

方案 B：显式 `--device` 映射

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

如果你的设备节点不同，把 `hidg*` / `video*` 替换成你的实际路径即可。

### 3）在宿主机启用 USB Gadget（HID 键盘/鼠标）

1. 修改 `/boot/config.txt`（`[all]` 部分加入）：

```ini
dtoverlay=dwc2,dr_mode=peripheral
```

1. 修改 `/boot/cmdline.txt`（在现有单行末尾追加，用空格隔开）：

```txt
modules-load=dwc2,g_ether
```

如果你想 HID-only，用：

```txt
modules-load=dwc2,g_hid
```

1. 修正共享脚本路径（宿主机上执行一次；把路径替换成你的仓库路径）：

```bash
cd /path/to/pikvm-docker/usb_gadgets.sh
mkdir -p lib
ln -sf "$(pwd)/usb-gadget" lib/usb-gadget.sh
```

1. 启用：

```bash
sudo /path/to/pikvm-docker/usb_gadgets.sh/init-usb-gadgets
```

1. 验证：

```bash
ls /sys/kernel/config/usb_gadget
```

### 4）关闭（可选）

```bash
sudo /path/to/pikvm-docker/usb_gadgets.sh/remove-usb-gadgets
```

可选：`usb_gadgets.sh/usb-gadget.service` 是 `systemd` oneshot 示例；如果使用，需要把里面的占位符 `ExecStart/ExecStop` 路径改成你的实际路径。