#!/bin/sh
# 看门狗：优先切节点，避免重启进程断连接
LOG=/tmp/sb_watchdog.log
API=http://127.0.0.1:9090
SECRET=$(grep -oE '"secret"[[:space:]]*:[[:space:]]*"[^"]*"' /etc/sing-box/config.json 2>/dev/null | head -1 | cut -d'"' -f4)
AUTH="Authorization: Bearer $SECRET"
ts=$(date '+%m-%d %H:%M')

# 1. 进程存活（procd 负责拉起，这里只补一刀）
if ! pgrep -f "/etc/sing-box/sing-box run" >/dev/null 2>&1; then
    echo "$ts 进程不存在，启动" >> $LOG
    /etc/init.d/sing-box start >/dev/null 2>&1
    exit 0
fi

# 2. nft 规则存活
if ! nft list table inet sb >/dev/null 2>&1; then
    echo "$ts nft 表丢失，重建" >> $LOG
    /etc/sing-box/nft-up.sh >/dev/null 2>&1
fi

# 3. 出口探测
code=$(curl -s -m 8 -x socks5h://127.0.0.1:7890 -o /dev/null -w "%{http_code}" \
       https://www.gstatic.com/generate_204 2>/dev/null)
[ "$code" = "204" ] && exit 0

# 4. 探测失败 → 找可用节点切换（不重启）
for n in jp-hy2 jp-tuic us-reality us-anytls us-hy2 my-reality443 my-anytls us-cdn jp-cdn; do
    d=$(curl -s -m 10 -H "$AUTH" \
        "$API/proxies/$n/delay?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=5000" 2>/dev/null \
        | grep -oE '"delay":[0-9]+' | cut -d: -f2)
    if [ -n "$d" ] && [ "$d" -gt 0 ] 2>/dev/null; then
        curl -s -m 5 -X PUT -H "$AUTH" -H "Content-Type: application/json" \
             -d "{\"name\":\"$n\"}" "$API/proxies/proxy" >/dev/null 2>&1
        echo "$ts 出口故障($code)，切到 $n (${d}ms)" >> $LOG
        exit 0
    fi
done

# 5. 全部不可用 → 重启（最后手段）
echo "$ts 全部节点不可用，重启" >> $LOG
/etc/init.d/sing-box restart >/dev/null 2>&1
