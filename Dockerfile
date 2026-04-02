# PiKVM kvmd on Arch Linux ARM. Build: docker build --build-arg ARCH=aarch64 -t pikvm-kvmd:local .
FROM menci/archlinuxarm:latest

ARG BOARD=rpi4
ENV BOARD=${BOARD}

ARG ARCH=aarch64
ENV ARCH=${ARCH}

ARG PLATFORM=v2-hdmiusb
ENV PLATFORM=${PLATFORM}

ARG PIKVM_REPO_KEY=912C773ABBD1B584

ARG PIKVM_REPO_URL=https://files.pikvm.org/repos/arch
ENV PIKVM_REPO_URL=${PIKVM_REPO_URL}

RUN sed -i '/CheckSpace/d' /etc/pacman.conf \
    && sed -i 's/^#DisableSandbox$/DisableSandbox/' /etc/pacman.conf \
    && grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf \
    && pacman -Sy --noconfirm --disable-sandbox archlinux-keyring \
    && pacman-key --init \
    && pacman-key --populate archlinux

RUN mkdir -p /etc/gnupg \
    && echo "standard-resolver" >> /etc/gnupg/dirmngr.conf \
    && ( pacman-key --keyserver hkps://keyserver.ubuntu.com:443 -r ${PIKVM_REPO_KEY} \
        || pacman-key --keyserver hkps://keys.openpgp.org:443 -r ${PIKVM_REPO_KEY} \
        || pacman-key --keyserver hkps://pgp.mit.edu:443 -r ${PIKVM_REPO_KEY} ) \
    && pacman-key --lsign-key ${PIKVM_REPO_KEY}

RUN printf '\n[pikvm]\nSigLevel = Required DatabaseOptional\nServer = %s/%s-%s\n' \
        "${PIKVM_REPO_URL}" "${BOARD}" "${ARCH}" >> /etc/pacman.conf

RUN pacman -Syu --noconfirm --disable-sandbox

RUN pacman -S --noconfirm --disable-sandbox \
        "kvmd-platform-${PLATFORM}-${BOARD}" \
        git base-devel libjpeg-turbo libevent libbsd libgpiod python-setuptools python-pip

RUN test -f /usr/lib/sysusers.d/kvmd.conf && command -v systemd-sysusers >/dev/null 2>&1 \
    && systemd-sysusers /usr/lib/sysusers.d/kvmd.conf || true

RUN python3 -c "import ustreamer; print('ustreamer python OK:', ustreamer)"

RUN printf '%s\n' '#!/bin/sh' 'echo "throttled=0x0"' > /usr/local/bin/vcgencmd-container-shim \
    && chmod +x /usr/local/bin/vcgencmd-container-shim

EXPOSE 443/tcp

COPY override.yaml /etc/kvmd/override.yaml

RUN kvmd-gencert --do-the-thing \
    && kvmd-gencert --do-the-thing --vnc

COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
