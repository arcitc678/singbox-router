#!/bin/sh
# TProxy 规则：国内 IP 直接放行（不经过 sing-box），其余进 tproxy
SB=/etc/sing-box

/etc/sing-box/nft-down.sh >/dev/null 2>&1

nft -f - <<'NFT'
table inet sb {
  set local4 { type ipv4_addr; flags interval; elements = { 0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 } }
  set local6 { type ipv6_addr; flags interval; elements = { ::1/128, fc00::/7, fe80::/10, ff00::/8 } }
  set cn4 { type ipv4_addr; flags interval; auto-merge; }

  chain pre {
    type filter hook prerouting priority mangle; policy accept;
    ip daddr @local4 return
    ip6 daddr @local6 return
    ip daddr @cn4 return
    meta l4proto { tcp, udp } tproxy ip to :7895 meta mark set 1 accept
    meta l4proto { tcp, udp } tproxy ip6 to :7895 meta mark set 1 accept
  }
  chain out {
    type route hook output priority mangle; policy accept;
    ip daddr @local4 return
    ip6 daddr @local6 return
    ip daddr @cn4 return
    meta mark 1 return
    meta mark 2 return
    meta l4proto { tcp, udp } meta mark set 1
  }
}
NFT

# 灌入国内 IP 段
[ -s "$SB/cn4-load.nft" ] && nft -f "$SB/cn4-load.nft" 2>/dev/null

ip rule add fwmark 1 table 100 2>/dev/null
ip route add local default dev lo table 100 2>/dev/null || \
  ip route add local 0.0.0.0/0 dev lo table 100 2>/dev/null
ip -6 rule add fwmark 1 table 106 2>/dev/null
ip -6 route add local default dev lo table 106 2>/dev/null || \
  ip -6 route add local ::/0 dev lo table 106 2>/dev/null
exit 0
