# OpenWrt 纯 sing-box 透明代理

在 OpenWrt 上用**官方 sing-box 最新内核**接管全屋流量，替代 homeproxy，自带 Web 面板和 LuCI 入口。

## 为什么

homeproxy 把 sing-box 二进制和配置生成器绑死（写这份文档时是 1.12.25），内核升不了，新协议（Snell v6 等）用不了。这套方案：

- 内核用**官方 release**（1.14.x），随时替换二进制即可升级
- 配置是单个 `config.json`，任何字段都能改，不受 UI 限制
- 自带面板（9KB，无依赖）和 LuCI 菜单
- 一键回滚 homeproxy

## 架构

```
局域网客户端 ──tproxy──> sing-box 1.14 ──> 节点（Reality / AnyTLS / hysteria2 / CDN）
                              │
                              ├── clash API :9090（面板 + 脚本）
                              ├── 面板 /ui/
                              └── LuCI 菜单（iframe 嵌入面板）
```

## 目录

| 路径 | 说明 |
|---|---|
| `config/config.example.json` | 配置模板（节点参数用占位符） |
| `scripts/nft-up.sh` | TProxy 规则（nft + ip rule） |
| `scripts/nft-down.sh` | 清理规则 |
| `scripts/watchdog.sh` | 每 2 分钟自检：服务/规则/出口 |
| `scripts/update-rules.sh` | 每周更新 geosite/geoip 规则集 |
| `scripts/rollback.sh` | 回滚到 homeproxy |
| `scripts/switch.sh` | 切换脚本（带探测和自动回滚） |
| `scripts/sing-box.init` | procd 服务脚本 |
| `panel/index.html` | 自写面板（切换节点/测速/模式） |
| `luci/` | LuCI 菜单、ACL、视图 |

## 部署

### 1. 下载内核

```sh
URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
  | grep -oE 'https://[^"]*linux-amd64-musl.tar.gz' | head -1)
curl -sSL "$URL" | tar -xz -C /tmp
mkdir -p /etc/sing-box
cp /tmp/sing-box-*/sing-box /etc/sing-box/
chmod +x /etc/sing-box/sing-box
```

### 2. 放配置

把 `config/config.example.json` 改成真实参数，放到 `/etc/sing-box/config.json`。

关键字段：

```jsonc
"inbounds": [
  { "type": "tproxy", "listen": "::", "listen_port": 7895 },
  { "type": "mixed",  "listen": "127.0.0.1", "listen_port": 7890 }
],
"experimental": {
  "clash_api": { "external_controller": "0.0.0.0:9090", "secret": "改掉", "external_ui": "/etc/sing-box/ui" }
}
```

每个出站需要：

```jsonc
"bind_interface": "eth0",   // 你的 WAN 网卡
"routing_mark": 2           // 防止自己的流量被 tproxy 抓回去
```

### 3. 放规则集

```sh
cd /etc/sing-box
curl -sSL -o geosite-cn.srs https://github.com/SagerNet/sing-geosite/raw/rule-set/geosite-cn.srs
curl -sSL -o geoip-cn.srs   https://github.com/SagerNet/sing-geoip/raw/rule-set/geoip-cn.srs
```

### 4. 放脚本和面板

```sh
cp scripts/nft-up.sh scripts/nft-down.sh scripts/watchdog.sh scripts/update-rules.sh scripts/rollback.sh /etc/sing-box/
chmod +x /etc/sing-box/*.sh
mkdir -p /etc/sing-box/ui /www/luci-static/resources/view/singbox
cp panel/index.html /etc/sing-box/ui/
cp luci/main.js /www/luci-static/resources/view/singbox/main.js
cp luci/menu.json /usr/share/luci/menu.d/luci-app-singbox.json
cp luci/acl.json  /usr/share/rpcd/acl.d/luci-app-singbox.json
cp scripts/sing-box.init /etc/init.d/sing-box
chmod +x /etc/init.d/sing-box
```

### 5. 启动

```sh
/etc/init.d/sing-box enable
/etc/init.d/sing-box start
```

### 6. 定时任务

```sh
crontab -l > /tmp/ct 2>/dev/null
echo "*/2 * * * * /etc/sing-box/watchdog.sh >/dev/null 2>&1" >> /tmp/ct
echo "30 4 * * 1 /etc/sing-box/update-rules.sh" >> /tmp/ct
crontab /tmp/ct
```

## 关键坑

### 1. tproxy 表 100 的路由

`ip rule add fwmark 1 table 100` 之后**必须**加：

```sh
ip route add local default dev lo table 100
```

少了这条，标记的流量不会进 tproxy，表现为「国内外都打不开」。脚本里做了 fallback：

```sh
ip route add local default dev lo table 100 2>/dev/null || \
  ip route add local 0.0.0.0/0 dev lo table 100 2>/dev/null
```

### 2. 出站必须绑网卡 + 打 mark

不设 `bind_interface` 和 `routing_mark`，sing-box 自己的出站会被 output 链标记，然后又被 tproxy 抓回来，形成环路 → 所有直连超时。

nft 输出链要跳过 mark 2：

```
meta mark 1 return
meta mark 2 return
```

### 3. DNS

dnsmasq 指向公共 DNS（如 1.1.1.1），查询会被 tproxy 抓进 sing-box 的 `hijack-dns`，由 sing-box 按域名分流解析。不要指向同网段的上游（会被 `local4` 排除掉，拿不到代理 DNS）。

### 4. sing-box 1.14 配置变化

- inbound 不能再用 `sniff` 字段 → 用 `route.rules` 的 `{"action":"sniff"}`
- 必须设 `route.default_domain_resolver`，否则报 deprecated 并拒绝启动

## 面板

```sh
http://<路由器IP>:9090/ui/
```

- 切换节点、全部测速
- 模式：智能分流 / 全局代理 / 直连
- 实时流量和连接数
- 深色/浅色主题

面板与 API 同源（都在 9090），所以没有 CORS 问题。密钥写在页面里，仅限局域网访问。

## LuCI

```
LuCI → 服务 → Sing-Box
```

页面内嵌面板（iframe），另有链接可新窗口打开。

隐藏 homeproxy 菜单：

```sh
mv /usr/share/luci/menu.d/luci-app-homeproxy.json \
   /usr/share/luci/menu.d/luci-app-homeproxy.json.disabled
```

## 回滚

```sh
/etc/sing-box/rollback.sh
```

停止 sing-box、清 nft 规则、启动 homeproxy。

## 维护命令

| 操作 | 命令 |
|---|---|
| 状态 | `/etc/init.d/sing-box status` |
| 重启 | `/etc/init.d/sing-box restart` |
| 日志 | `logread \| grep sing-box` |
| 更新规则集 | `/etc/sing-box/update-rules.sh` |
| 测节点延迟 | `curl -H "Authorization: Bearer <secret>" "http://127.0.0.1:9090/proxies/<节点名>/delay?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=8000"` |
| 切节点 | `curl -X PUT -H "Authorization: Bearer <secret>" -d '{"name":"<节点名>"}' http://127.0.0.1:9090/proxies/proxy` |

## 注意

- 只有把网关设成这台路由器的设备才走代理
- `config.example.json` 里全是占位符，真实凭据**不要**提交到仓库
- 交换机和 WAN 同网段时，`local4` 要包含该网段，否则内网流量也会被代理
