#!/bin/sh
LOG=/tmp/sb_switch.log
exec >$LOG 2>&1
echo "=== $(date) 开始切换 ==="

/etc/init.d/homeproxy stop
sleep 2
/etc/init.d/sing-box start
sleep 6

OK=0
for i in 1 2 3; do
  out=$(curl -s -m 10 https://1.1.1.1/cdn-cgi/trace 2>/dev/null)
  ip=$(echo "$out" | grep -oE "^ip=[0-9.]+" | cut -d= -f2)
  echo "  第 $i 次: 出口=${ip:-空}"
  if [ -n "$ip" ] && [ "$ip" != "192.168.0.252" ]; then OK=1; break; fi
  sleep 4
done

if [ "$OK" = "1" ]; then
  echo "=== 切换成功，出口 $ip ==="
  /etc/init.d/sing-box enable
  /etc/init.d/homeproxy disable 2>/dev/null
  # dnsmasq 指向 sing-box 的 DNS（tproxy 会劫持 53）
  uci set dhcp.@dnsmasq[0].noresolv='1' 2>/dev/null
  uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5353' 2>/dev/null
  uci commit dhcp 2>/dev/null
  /etc/init.d/dnsmasq restart 2>/dev/null
else
  echo "=== 探测失败，自动回滚 ==="
  /etc/sing-box/rollback.sh
fi
