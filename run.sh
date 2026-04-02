#!/bin/bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root." >&2
  exit 1
fi

if [[ -n "${WEBUI_ADMIN_PASSWD:-}" ]]; then
  echo "${WEBUI_ADMIN_PASSWD}" | kvmd-htpasswd set --read-stdin admin
fi

if [[ ! -x /usr/local/bin/vcgencmd-container-shim ]]; then
  mkdir -p /usr/local/bin
  printf '%s\n' '#!/bin/sh' 'echo "throttled=0x0"' > /usr/local/bin/vcgencmd-container-shim
  chmod +x /usr/local/bin/vcgencmd-container-shim
fi

VIDEO_DEV="${VIDEO_DEV:-/dev/video0}"
H264_M2M_DEV="${H264_M2M_DEV:-/dev/video11}"
if [[ ! -e /dev/kvmd-video ]] && [[ -e "$VIDEO_DEV" ]]; then
  ln -sf "$VIDEO_DEV" /dev/kvmd-video
fi

if [[ "${KVMD_JANUS:-1}" == "1" ]]; then
  _src="$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit }}' || true)"
  if [[ -n "$_src" ]] && [[ "$_src" == 172.17.* ]]; then
    echo "pikvm-docker: WebRTC 建议 --network host（当前默认路由源 ${_src}，与官方整机 PiKVM 网络模型不同）。" >&2
  fi
fi

mkdir -p /run/kvmd /tmp/kvmd /tmp/kvmd-nginx /var/log/kvmd/nginx 2>/dev/null || true
if id kvmd &>/dev/null; then
  chown kvmd:kvmd /run/kvmd /tmp/kvmd
  chmod 775 /run/kvmd /tmp/kvmd
  chown -R kvmd:kvmd /var/lib/kvmd 2>/dev/null || true
  getent group video >/dev/null && usermod -a -G video kvmd 2>/dev/null || true
fi
if id kvmd-nginx &>/dev/null; then
  chown kvmd-nginx:root /tmp/kvmd-nginx
  chmod 700 /tmp/kvmd-nginx
  chown -R kvmd-nginx:root /var/log/kvmd/nginx 2>/dev/null || true
  for _g in kvmd kvmd-media kvmd-janus kvmd-certbot; do
    getent group "$_g" >/dev/null && usermod -a -G "$_g" kvmd-nginx 2>/dev/null || true
  done
fi

if [[ -e /dev/gpiochip0 ]]; then
  _gpiogrp="$(stat -c "%G" /dev/gpiochip0)"
  if [[ -n "$_gpiogrp" ]] && [[ "$_gpiogrp" != "UNKNOWN" ]]; then
    usermod -a -G "$_gpiogrp" kvmd 2>/dev/null || true
  fi
fi

if [[ -e /dev/kvmd-video ]]; then
  chown root:video /dev/kvmd-video 2>/dev/null || true
  chmod 660 /dev/kvmd-video 2>/dev/null || true
fi

if [[ -e "$H264_M2M_DEV" ]]; then
  if getent group video >/dev/null; then
    chown root:video "$H264_M2M_DEV" 2>/dev/null || true
    chmod 660 "$H264_M2M_DEV" 2>/dev/null || true
  else
    chmod 666 "$H264_M2M_DEV" 2>/dev/null || true
  fi
fi

if [[ ! -e "$H264_M2M_DEV" ]] && [[ -f /etc/kvmd/override.yaml ]] && grep -qE '^\s+- "--h264-sink=' /etc/kvmd/override.yaml; then
  echo "pikvm-docker: 缺少 ${H264_M2M_DEV}，Direct H.264 需挂载 SoC 编码器。" >&2
fi
for n in /dev/kvmd-hid /dev/kvmd-hid-keyboard /dev/kvmd-hid-mouse; do
  if [[ -e "$n" ]]; then
    chown root:gpio "$n" 2>/dev/null || true
    chmod 660 "$n" 2>/dev/null || true
  fi
done

NGX_PREFIX="/etc/kvmd/nginx"
NGX_EXTRA=()
if [[ -f "$NGX_PREFIX/nginx.conf.mako" ]] && command -v kvmd-nginx-mkconf >/dev/null 2>&1; then
  kvmd-nginx-mkconf "$NGX_PREFIX/nginx.conf.mako" /run/kvmd/nginx.conf
  NGX_CONF="/run/kvmd/nginx.conf"
  NGX_EXTRA=(-g 'pid /run/kvmd/nginx.pid; user kvmd-nginx; error_log stderr; daemon off;')
else
  NGX_CONF="$NGX_PREFIX/nginx.conf"
fi

/usr/sbin/nginx -p "$NGX_PREFIX" -c "$NGX_CONF" "${NGX_EXTRA[@]}" &

if id kvmd-media &>/dev/null && command -v kvmd-media >/dev/null 2>&1; then
  sudo -u kvmd-media /usr/bin/kvmd-media --run &
fi

if id kvmd-janus &>/dev/null; then
  usermod -a -G kvmd kvmd-janus 2>/dev/null || true
fi

_kvmd_term() {
  [[ -n "${_JANUS_PID:-}" ]] && kill -TERM "$_JANUS_PID" 2>/dev/null || true
  [[ -n "${_KVMD_PID:-}" ]] && kill -TERM "$_KVMD_PID" 2>/dev/null || true
  [[ -n "${_KVMD_PID:-}" ]] && wait "$_KVMD_PID" 2>/dev/null || true
  exit 0
}

if [[ "${KVMD_JANUS:-1}" == "1" ]] && command -v kvmd-janus >/dev/null 2>&1 && id kvmd-janus &>/dev/null; then
  trap _kvmd_term TERM INT
  sudo -u kvmd /usr/bin/kvmd --run &
  _KVMD_PID=$!
  for _i in $(seq 1 100); do
    if ! kill -0 "$_KVMD_PID" 2>/dev/null; then
      wait "$_KVMD_PID"
      exit $?
    fi
    [[ -S /run/kvmd/ustreamer.sock ]] && break
    sleep 0.2
  done
  sudo -u kvmd-janus /usr/bin/kvmd-janus --run &
  _JANUS_PID=$!
  (
    while kill -0 "$_JANUS_PID" 2>/dev/null; do
      if [[ -S /run/kvmd/janus-ws.sock ]] && id kvmd-janus &>/dev/null && id kvmd-nginx &>/dev/null; then
        chown kvmd-janus:kvmd-nginx /run/kvmd/janus-ws.sock 2>/dev/null || true
        chmod 0660 /run/kvmd/janus-ws.sock 2>/dev/null || true
      fi
      sleep 1
    done
  ) &
  wait "$_KVMD_PID"
  _st=$?
  [[ -n "${_JANUS_PID:-}" ]] && kill "$_JANUS_PID" 2>/dev/null || true
  wait "$_JANUS_PID" 2>/dev/null || true
  exit "$_st"
fi

exec sudo -u kvmd /usr/bin/kvmd --run
