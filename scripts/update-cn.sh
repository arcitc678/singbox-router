#!/bin/sh
# 更新国内 IPv4 段并热更新 nft 集合（不重启 sing-box，不断连接）
SB=/etc/sing-box
LIST=/tmp/cn4.list
LOG=/tmp/sb_cn_update.log

echo "=== $(date) 更新国内 IP 段 ===" >> $LOG
curl -sS -m 120 -o /tmp/apnic.txt "https://ftp.apnic.net/stats/apnic/delegated-apnic-latest" 2>/dev/null
[ -s /tmp/apnic.txt ] || { echo "  下载失败" >> $LOG; exit 1; }

grep "|CN|ipv4|" /tmp/apnic.txt | awk -F"|" '{n=$5; c=0; while(n>1){n=n/2; c++} print $4"/"(32-c)}' > $LIST
N=$(wc -l < $LIST)
[ "$N" -gt 1000 ] || { echo "  段数异常: $N" >> $LOG; exit 1; }

{
  echo "flush set inet sb cn4"
  echo -n "add element inet sb cn4 { "
  awk '{printf "%s%s", (NR>1?", ":""), $0} END{print ""}' $LIST
  echo " }"
} > "$SB/cn4-load.nft"

# 只更新集合，不动链
nft -f "$SB/cn4-load.nft" 2>/dev/null && echo "  已更新 $N 个段" >> $LOG || echo "  应用失败" >> $LOG
rm -f /tmp/apnic.txt
