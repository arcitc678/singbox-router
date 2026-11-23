#!/bin/sh
echo "[rollback] 停止 sing-box，恢复 homeproxy"
/etc/init.d/sing-box stop >/dev/null 2>&1
/etc/sing-box/nft-down.sh >/dev/null 2>&1
/etc/init.d/homeproxy start >/dev/null 2>&1
sleep 3
echo "[rollback] homeproxy: $(/etc/init.d/homeproxy status 2>&1 | head -1)"
