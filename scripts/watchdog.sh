#!/bin/sh
LOG=/tmp/sb_watchdog.log
ts=$(date '+%m-%d %H:%M')

# 服务没跑 → 拉起
if ! pgrep -f "/etc/sing-box/sing-box run" >/dev/null 2>&1; then
  echo "$ts sing-box 未运行，拉起" >> $LOG
  /etc/init.d/sing-box start >/dev/null 2>&1
  sleep 5
fi

# nft 表不存在 → 重建
if ! nft list table inet sb >/dev/null 2>&1; then
  echo "$ts nft 表丢失，重建" >> $LOG
  /etc/sing-box/nft-up.sh >/dev/null 2>&1
fi

# ip rule 丢失 → 重建
if ! ip rule show 2>/dev/null | grep -q "fwmark 0x1 lookup 100"; then
  echo "$ts ip rule 丢失，重建" >> $LOG
  /etc/sing-box/nft-up.sh >/dev/null 2>&1
fi

# 出口探测（走本地代理）
code=$(curl -s -m 8 -x socks5h://127.0.0.1:7890 -o /dev/null -w "%{http_code}" https://www.gstatic.com/generate_204 2>/dev/null)
if [ "$code" != "204" ]; then
  echo "$ts 探测失败($code)，重启 sing-box" >> $LOG
  /etc/init.d/sing-box restart >/dev/null 2>&1
fi
