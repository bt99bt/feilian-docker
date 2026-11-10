#!/bin/sh
set -eu

current_iface=''
current_bridge_net=''
sockd_pid=''
original_resolv="$(cat /etc/resolv.conf)"
vpn_dns_server="${VPN_DNS_SERVER:-}"
if [ -z "$vpn_dns_server" ] && [ -f /home/feilian/.vpn-dns-server ]; then
  vpn_dns_server="$(head -n 1 /home/feilian/.vpn-dns-server)"
fi

set_vpn_dns() {
  dns_changed=0
  [ -n "$vpn_dns_server" ] || return 0
  desired_resolv="$original_resolv"
  if ip -4 route get "$vpn_dns_server" 2>/dev/null | grep -q " dev $1 "; then
    desired_resolv="nameserver $vpn_dns_server"
  fi
  if [ "$(cat /etc/resolv.conf)" != "$desired_resolv" ]; then
    printf '%s\n' "$desired_resolv" > /etc/resolv.conf
    dns_changed=1
  fi
}

restore_dns() {
  [ -n "$vpn_dns_server" ] || return 0
  if [ "$(cat /etc/resolv.conf)" != "$original_resolv" ]; then
    printf '%s\n' "$original_resolv" > /etc/resolv.conf
  fi
}

remove_rules() {
  [ -n "$current_iface" ] || return 0
  iptables -D OUTPUT -m owner --uid-owner socksproxy -o eth0 -d "$current_bridge_net" -j ACCEPT 2>/dev/null || true
  iptables -D OUTPUT -m owner --uid-owner socksproxy -o lo -j ACCEPT 2>/dev/null || true
  iptables -D OUTPUT -m owner --uid-owner socksproxy ! -o "$current_iface" -j REJECT 2>/dev/null || true
}

cleanup() {
  if [ -n "$sockd_pid" ]; then
    kill "$sockd_pid" 2>/dev/null || true
    wait "$sockd_pid" 2>/dev/null || true
  fi
  remove_rules
  restore_dns
}
trap cleanup EXIT
trap 'exit 0' INT TERM

while :; do
  # The proxy must never start on Docker's normal network interface.
  iface="${VPN_INTERFACE:-}"
  if [ -z "$iface" ]; then
    iface="$(ip -4 -o addr show up | awk '$2 !~ /^(lo|eth0)(@|$)/ {sub(/@.*/, "", $2); print $2; exit}')"
  fi

  if [ -n "$iface" ] && [ "$iface" != eth0 ] && [ "$iface" != lo ] && ip -4 -o addr show up dev "$iface" | grep -q . && ip -4 route show dev "$iface" | grep -q .; then
    set_vpn_dns "$iface"
    if [ "$iface" != "$current_iface" ] || [ "$dns_changed" -eq 1 ] || [ -z "$sockd_pid" ] || ! kill -0 "$sockd_pid" 2>/dev/null; then
      if [ -n "$sockd_pid" ]; then
        kill "$sockd_pid" 2>/dev/null || true
        wait "$sockd_pid" 2>/dev/null || true
      fi
      remove_rules
      bridge_net="$(ip -4 -o route show dev eth0 scope link | awk 'NR==1 {print $1}')"
      [ -n "$bridge_net" ] || { sleep 3; continue; }
      # The proxy may reply to the Mac through Docker's bridge and query
      # DNS on loopback. All other egress, including corporate DNS, uses the VPN.
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
    restore_dns
  else
    restore_dns
  fi
  sleep 3
done
