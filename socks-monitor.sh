#!/bin/sh
set -eu

current_iface=''
current_bridge_net=''
sockd_pid=''

remove_rules() {
  [ -n "$current_iface" ] || return 0
  iptables -D OUTPUT -m owner --uid-owner socksproxy -o eth0 -d "$current_bridge_net" -j ACCEPT 2>/dev/null || true
  iptables -D OUTPUT -m owner --uid-owner socksproxy -o lo -j ACCEPT 2>/dev/null || true
  iptables -D OUTPUT -m owner --uid-owner socksproxy ! -o "$current_iface" -j REJECT 2>/dev/null || true
}

while :; do
  # The proxy must never start on Docker's normal network interface.
  iface="${VPN_INTERFACE:-}"
  if [ -z "$iface" ]; then
    iface="$(ip -4 -o addr show up | awk '$2 !~ /^(lo|eth0)(@|$)/ {sub(/@.*/, "", $2); print $2; exit}')"
  fi

  if [ -n "$iface" ] && [ "$iface" != eth0 ] && [ "$iface" != lo ] && ip -4 -o addr show up dev "$iface" | grep -q . && ip -4 route show dev "$iface" | grep -q .; then
    if [ "$iface" != "$current_iface" ] || [ -z "$sockd_pid" ] || ! kill -0 "$sockd_pid" 2>/dev/null; then
      if [ -n "$sockd_pid" ]; then
        kill "$sockd_pid" 2>/dev/null || true
        wait "$sockd_pid" 2>/dev/null || true
      fi
      remove_rules
      bridge_net="$(ip -4 -o route show dev eth0 scope link | awk 'NR==1 {print $1}')"
      [ -n "$bridge_net" ] || { sleep 3; continue; }
      # The proxy may reply to the Mac through Docker's bridge and query
      # Feilian's local DNS on loopback. All other egress must use the VPN.
      iptables -I OUTPUT 1 -m owner --uid-owner socksproxy ! -o "$iface" -j REJECT
      iptables -I OUTPUT 1 -m owner --uid-owner socksproxy -o lo -j ACCEPT
      iptables -I OUTPUT 1 -m owner --uid-owner socksproxy -o eth0 -d "$bridge_net" -j ACCEPT
      cat > /tmp/sockd.conf <<EOF
logoutput: stdout
internal: 0.0.0.0 port = 1080
external: $iface
user.privileged: root
user.notprivileged: socksproxy
clientmethod: none
socksmethod: none
client pass { from: 0.0.0.0/0 to: 0.0.0.0/0 }
socks pass { from: 0.0.0.0/0 to: 0.0.0.0/0 command: connect }
EOF
      /usr/sbin/danted -f /tmp/sockd.conf &
      sockd_pid=$!
      current_iface="$iface"
      current_bridge_net="$bridge_net"
    fi
  elif [ -n "$sockd_pid" ]; then
    kill "$sockd_pid" 2>/dev/null || true
    wait "$sockd_pid" 2>/dev/null || true
    remove_rules
    sockd_pid=''
    current_iface=''
    current_bridge_net=''
  fi
  sleep 3
done
