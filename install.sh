#!/bin/sh
# OpenWrt 纯 sing-box 一键安装
# 用法：sh install.sh [配置文件路径]
#   不带参数：从 config/config.example.json 复制（需自己填节点）
#   带参数：  用指定的 config.json

set -e
SB_DIR=/etc/sing-box
GH_RAW="https://raw.githubusercontent.com/SagerNet"
CFG_SRC="${1:-}"

say() { printf "\033[36m==> %s\033[0m\n" "$1"; }
die() { printf "\033[31mERROR: %s\033[0m\n" "$1" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "请用 root 运行"

say "1/8 检测架构"
case "$(uname -m)" in
  x86_64)  ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  armv7l)  ARCH=armv7 ;;
  *) die "不支持的架构: $(uname -m)" ;;
esac
echo "    $ARCH"

say "2/8 下载 sing-box"
TMP=$(mktemp -d)
# 解析最新版本号（没有 latest 别名资产，必须拼版本）
VERSION=$(curl -sSL -m 20 "https://api.github.com/repos/SagerNet/sing-box/releases/latest" \
  | grep -oE '"tag_name"[^"]*"v?[0-9]+\.[0-9]+\.[0-9]+[^"]*"' \
  | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[0-9a-zA-Z.\-]*')
[ -n "$VERSION" ] || die "无法获取最新版本号"
echo "    版本: v$VERSION"
BASE="https://github.com/SagerNet/sing-box/releases/download/v$VERSION"
curl -sSL -m 300 -o "$TMP/sb.tar.gz" "$BASE/sing-box-$VERSION-linux-$ARCH-musl.tar.gz" \
  || curl -sSL -m 300 -o "$TMP/sb.tar.gz" "$BASE/sing-box-$VERSION-linux-$ARCH.tar.gz"
[ -s "$TMP/sb.tar.gz" ] || die "下载失败"
tar -xzf "$TMP/sb.tar.gz" -C "$TMP"
BIN=$(find "$TMP" -name sing-box -type f | head -1)
[ -n "$BIN" ] || die "下载失败"
mkdir -p "$SB_DIR"
cp "$BIN" "$SB_DIR/sing-box"
chmod +x "$SB_DIR/sing-box"
"$SB_DIR/sing-box" version | head -1

say "3/8 配置文件"
if [ -n "$CFG_SRC" ] && [ -f "$CFG_SRC" ]; then
  cp "$CFG_SRC" "$SB_DIR/config.json"
  echo "    已使用 $CFG_SRC"
elif [ -f ./config/config.example.json ]; then
  cp ./config/config.example.json "$SB_DIR/config.json"
  echo "    已复制模板，记得改 /etc/sing-box/config.json 里的占位符"
else
  die "找不到 config.json"
fi

say "4/8 下载规则集"
curl -sSL -m 120 -o "$SB_DIR/geosite-cn.srs" "$GH_RAW/sing-geosite/rule-set/geosite-cn.srs" || true
curl -sSL -m 120 -o "$SB_DIR/geoip-cn.srs"   "$GH_RAW/sing-geoip/rule-set/geoip-cn.srs" || true

say "5/8 安装脚本"
for f in nft-up.sh nft-down.sh watchdog.sh update-rules.sh rollback.sh upgrade.sh; do
  cp "./scripts/$f" "$SB_DIR/$f"
  chmod +x "$SB_DIR/$f"
done
cp ./scripts/sing-box.init /etc/init.d/sing-box
chmod +x /etc/init.d/sing-box

say "6/8 安装面板"
mkdir -p "$SB_DIR/ui"
cp ./panel/index.html "$SB_DIR/ui/index.html"

say "7/8 安装 LuCI 入口"
mkdir -p /www/luci-static/resources/view/singbox /usr/share/luci/menu.d /usr/share/rpcd/acl.d /usr/libexec/rpcd
cp ./luci/main.js   /www/luci-static/resources/view/singbox/main.js
cp ./luci/menu.json /usr/share/luci/menu.d/luci-app-singbox.json
cp ./luci/acl.json  /usr/share/rpcd/acl.d/luci-app-singbox.json
cp ./rpcd/singbox   /usr/libexec/rpcd/singbox
chmod +x /usr/libexec/rpcd/singbox
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
[ -f /usr/share/luci/menu.d/luci-app-homeproxy.json ] && \
  mv /usr/share/luci/menu.d/luci-app-homeproxy.json /usr/share/luci/menu.d/luci-app-homeproxy.json.disabled
rm -f /tmp/luci-indexcache* 2>/dev/null
/etc/init.d/uhttpd reload >/dev/null 2>&1 || true

say "8/8 启动与定时任务"
"$SB_DIR/sing-box" check -c "$SB_DIR/config.json" || die "配置校验失败，请检查 config.json"
/etc/init.d/sing-box enable
/etc/init.d/sing-box start
sleep 5

crontab -l 2>/dev/null | grep -v "sing-box/watchdog\|sing-box/update-rules" > /tmp/ct.$$
echo "*/2 * * * * /etc/sing-box/watchdog.sh >/dev/null 2>&1" >> /tmp/ct.$$
echo "30 4 * * 1 /etc/sing-box/update-rules.sh" >> /tmp/ct.$$
crontab /tmp/ct.$$
rm -f /tmp/ct.$$

rm -rf "$TMP"

echo
say "完成"
echo "    面板:  http://$(uci get network.lan.ipaddr 2>/dev/null || echo '<路由器IP>'):9090/ui/"
echo "    LuCI:  服务 → Sing-Box"
echo "    回滚:  /etc/sing-box/rollback.sh"
echo
echo "    如果国内外都打不开，检查: ip route show table 100"
echo "    应该看到: local default dev lo"
