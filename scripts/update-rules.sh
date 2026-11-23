#!/bin/sh
# 更新 geosite/geoip 规则集（走本地代理下载，失败则保留旧文件）
cd /etc/sing-box || exit 1
LOG=/tmp/sb_rules_update.log
echo "=== $(date) 开始更新规则集 ===" >> $LOG

GH="https://raw.githubusercontent.com/SagerNet"

fetch() {
  name=$1; url=$2
  tmp="/tmp/${name}.new"
  rm -f "$tmp"
  ok=0
  # 依次尝试：代理 socks5 → 代理 http → 直连
  curl -sSL -m 120 --socks5-hostname 127.0.0.1:7890 -o "$tmp" "$url" 2>/dev/null && ok=1
  if [ "$ok" = "0" ]; then
    curl -sSL -m 120 -x http://127.0.0.1:7890 -o "$tmp" "$url" 2>/dev/null && ok=1
  fi
  if [ "$ok" = "0" ]; then
    curl -sSL -m 60 -o "$tmp" "$url" 2>/dev/null && ok=1
  fi
  if [ "$ok" = "1" ] && [ -s "$tmp" ]; then
    sz=$(wc -c < "$tmp")
    if [ "$sz" -gt 1000 ]; then
      mv "$tmp" "/etc/sing-box/${name}.srs"
      echo "  ${name}: 更新成功 ${sz}B" >> $LOG
      return 0
    fi
  fi
  rm -f "$tmp"
  echo "  ${name}: 更新失败，保留旧文件" >> $LOG
  return 1
}

n=0
fetch geosite-cn "$GH/sing-geosite/rule-set/geosite-cn.srs" && n=$((n+1))
fetch geoip-cn   "$GH/sing-geoip/rule-set/geoip-cn.srs"     && n=$((n+1))

if [ "$n" -gt 0 ]; then
  /etc/init.d/sing-box reload >/dev/null 2>&1 || /etc/init.d/sing-box restart >/dev/null 2>&1
  echo "  已重载 sing-box（$n 个规则集）" >> $LOG
fi
echo "=== 完成 ===" >> $LOG
