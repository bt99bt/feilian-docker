#!/bin/sh
set -eu

printf '\n========== 飞连 Clash/Mihomo 配置开始 ==========\n'
/usr/local/bin/clash-config
printf '========== 飞连 Clash/Mihomo 配置结束 ==========\n'
printf '飞连操作页面：http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale\n'
printf '请先在页面中连接 VPN；SOCKS5 仅在 VPN 网卡就绪后启动。\n'
printf '随时重打配置：docker compose exec -T feilian clash-config\n\n'

mkdir -p /run/dbus /var/run/NetworkManager /tmp/feilian-runtime
# Container restarts keep the writable layer, but not the old processes.
rm -f /run/dbus/pid /run/NetworkManager/NetworkManager.pid /tmp/.X0-lock /tmp/.X11-unix/X0
chown feilian:feilian /tmp/feilian-runtime /home/feilian
chmod 700 /tmp/feilian-runtime
/usr/local/bin/persist-state.sh

dbus-daemon --system --fork
NetworkManager --no-daemon &
Xvfb :0 -screen 0 1280x800x24 -nolisten tcp &
sleep 2

su -s /bin/sh feilian -c 'DISPLAY=:0 openbox-session' &
x11vnc -display :0 -localhost -forever -shared -nopw -quiet &
websockify --web=/usr/share/novnc/ 0.0.0.0:6080 127.0.0.1:5900 &

/opt/apps/com.volcengine.feilian/files/corplink-service &
sleep 3
su -s /bin/sh feilian -c 'DISPLAY=:0 XDG_RUNTIME_DIR=/tmp/feilian-runtime dbus-run-session -- /opt/apps/com.volcengine.feilian/files/corplink --no-sandbox' &

/usr/local/bin/socks-monitor.sh &
wait
