ARG BASE_IMAGE=debian:12-slim
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:0 \
    HOME=/home/feilian \
    XDG_RUNTIME_DIR=/tmp/feilian-runtime

ARG APT_MIRROR=http://deb.debian.org/debian
ARG APT_SECURITY_MIRROR=http://deb.debian.org/debian-security
RUN sed -i "s|http://deb.debian.org/debian-security|${APT_SECURITY_MIRROR}|g; s|http://deb.debian.org/debian|${APT_MIRROR}|g" /etc/apt/sources.list.d/debian.sources \
    && apt-get update && apt-get install -y --no-install-recommends \
    auditd ca-certificates curl dbus dbus-x11 dante-server dnsmasq-base \
    fonts-noto-cjk iproute2 iptables iw libasound2 libatk-bridge2.0-0 \
    libgbm1 libgtk-3-0 libnotify4 libnss3 libnss3-tools libsecret-1-0 \
    libxss1 libxtst6 network-manager novnc openbox procps tini \
    websockify x11vnc xterm xvfb xauth \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash feilian \
    && install -d -o feilian -g feilian /home/feilian/.config /tmp/feilian-runtime

ARG TARGETARCH
ARG FEILIAN_ARM64_URL=https://cdn.isealsuite.com/linux/FeiLian_Linux_arm64_v3.2.16_r8362_038591.deb
ARG FEILIAN_ARM64_SHA256=0547fd7a288e397346d413f60d77d16ba61731b361c53c8fa5e40ae29d42c99a
ARG FEILIAN_AMD64_URL=https://cdn.isealsuite.com/linux/FeiLian_Linux_amd64_v3.2.16_r8362_0d182a.deb
ARG FEILIAN_AMD64_SHA256=0ecaf5a41960a35679d1a715b73dadab1703b65decf13dbd689f8e1cc946a9d3
RUN set -eu; \
    case "$TARGETARCH" in \
      arm64) feilian_url="$FEILIAN_ARM64_URL"; feilian_sha256="$FEILIAN_ARM64_SHA256" ;; \
      amd64) feilian_url="$FEILIAN_AMD64_URL"; feilian_sha256="$FEILIAN_AMD64_SHA256" ;; \
      *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fL --retry 3 "$feilian_url" -o /tmp/feilian.deb \
    && echo "$feilian_sha256  /tmp/feilian.deb" | sha256sum -c - \
    && test "$(dpkg-deb -f /tmp/feilian.deb Architecture)" = "$TARGETARCH" \
    && dpkg-deb -x /tmp/feilian.deb / \
    && rm /tmp/feilian.deb \
    && chmod 4755 /opt/apps/com.volcengine.feilian/files/chrome-sandbox

RUN useradd --system --no-create-home --shell /usr/sbin/nologin socksproxy

# Docker owns eth0. Let NetworkManager manage VPN interfaces without changing it.
RUN printf '[keyfile]\nunmanaged-devices=interface-name:eth0\n' > /etc/NetworkManager/conf.d/99-container.conf

COPY start.sh socks-monitor.sh clash-config /usr/local/bin/
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/socks-monitor.sh /usr/local/bin/clash-config

EXPOSE 6080 1080
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/start.sh"]
