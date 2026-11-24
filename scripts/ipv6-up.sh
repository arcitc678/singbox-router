#!/bin/sh
# 确保 eth0 启用 IPv6 并通过 SLAAC 拿到地址（252 自身用，不代理 v6）
IF=${1:-eth0}
sysctl -w net.ipv6.conf.$IF.disable_ipv6=0 >/dev/null 2>&1
sysctl -w net.ipv6.conf.$IF.accept_ra=2 >/dev/null 2>&1
sysctl -w net.ipv6.conf.$IF.accept_ra_defrtr=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.$IF.autoconf=1 >/dev/null 2>&1

# 等最多 10 秒拿地址
i=0
while [ $i -lt 10 ]; do
    ip -6 addr show "$IF" 2>/dev/null | grep -q "scope global" && break
    sleep 1; i=$((i+1))
done
exit 0
