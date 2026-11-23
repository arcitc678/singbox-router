#!/bin/sh
# 升级 sing-box 内核到最新版
# 用法: upgrade.sh [版本号]   不带参数则取最新
LOG=/tmp/sb_upgrade.log

say() { echo "$1"; echo "$1" >> $LOG; }
fail() { say "❌ $1"; exit 1; }

case "$(uname -m)" in
  x86_64)  ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  armv7l)  ARCH=armv7 ;;
  *) fail "不支持的架构: $(uname -m)" ;;
esac

CUR=$(/etc/sing-box/sing-box version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[0-9a-zA-Z.\-]*')
say "当前版本: ${CUR:-未知}    架构: $ARCH"

VER="$1"
if [ -z "$VER" ]; then
  VER=$(curl -sSL -m 20 "https://api.github.com/repos/SagerNet/sing-box/releases/latest" \
    | grep -oE '"tag_name"[^"]*"v?[0-9]+\.[0-9]+\.[0-9]+[^"]*"' | head -1 \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[0-9a-zA-Z.\-]*')
  [ -n "$VER" ] || fail "获取最新版本失败（网络问题？）"
fi
say "目标版本: v$VER"

[ "$VER" = "$CUR" ] && { say "已经是最新版本，无需升级"; exit 0; }

TMP=$(mktemp -d)
BASE="https://github.com/SagerNet/sing-box/releases/download/v$VER"
say "下载中…"
curl -sSL -m 300 -o "$TMP/sb.tar.gz" "$BASE/sing-box-$VER-linux-$ARCH-musl.tar.gz" 2>/dev/null \
  || curl -sSL -m 300 -o "$TMP/sb.tar.gz" "$BASE/sing-box-$VER-linux-$ARCH.tar.gz" 2>/dev/null
[ -s "$TMP/sb.tar.gz" ] || { rm -rf "$TMP"; fail "下载失败"; }

tar -xzf "$TMP/sb.tar.gz" -C "$TMP" 2>/dev/null
NEW=$(find "$TMP" -name sing-box -type f | head -1)
[ -n "$NEW" ] || { rm -rf "$TMP"; fail "解压失败"; }
NEWVER=$("$NEW" version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[0-9a-zA-Z.\-]*')
[ "$NEWVER" = "$VER" ] || { rm -rf "$TMP"; fail "版本不符：下载到 $NEWVER"; }
say "校验通过: $NEWVER"

cp /etc/sing-box/sing-box "/etc/sing-box/sing-box.$CUR.bak" 2>/dev/null
cp "$NEW" /etc/sing-box/sing-box
chmod +x /etc/sing-box/sing-box

if ! /etc/sing-box/sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1; then
  say "⚠️ 新版本不认当前配置，回滚"
  cp "/etc/sing-box/sing-box.$CUR.bak" /etc/sing-box/sing-box
  rm -rf "$TMP"
  fail "配置不兼容，已回滚到 $CUR"
fi

/etc/init.d/sing-box restart >/dev/null 2>&1
sleep 6
rm -rf "$TMP"

if pgrep -f "/etc/sing-box/sing-box run" >/dev/null 2>&1; then
  say "✅ 升级成功: $CUR → $NEWVER"
else
  say "⚠️ 服务未起来，回滚"
  cp "/etc/sing-box/sing-box.$CUR.bak" /etc/sing-box/sing-box
  /etc/init.d/sing-box restart >/dev/null 2>&1
  fail "启动失败，已回滚到 $CUR"
fi
