# 故障排查

## 症状：国内外都打不开

```sh
# 检查 nft 规则
nft list table inet sb

# 检查 ip rule
ip rule show | grep fwmark

# 检查表 100 路由（最常见的坑）
ip route show table 100
# 应该看到：local default dev lo
```

缺路由就手动加：

```sh
ip route add local default dev lo table 100
```

## 症状：国内能开，国外打不开

```sh
# 从路由器本身测（绕过 tproxy）
curl -x socks5h://127.0.0.1:7890 https://www.google.com -o /dev/null -w "%{http_code}\n"

# 200 → 代理正常，问题在分流规则
# 000 → 节点问题，看日志
logread | grep sing-box | tail -20
```

## 症状：直连全部超时（日志里 direct i/o timeout）

出站没绑网卡或没打 mark，形成环路。检查 `config.json` 每个出站：

```jsonc
"bind_interface": "eth0",
"routing_mark": 2
```

以及 nft 输出链有 `meta mark 2 return`。

## 症状：DNS 解析到错误 IP

```sh
# 看 dnsmasq 上游
uci show dhcp.@dnsmasq[0].server
```

上游不能是同网段网关（会被 `local4` 排除），要指向公共 DNS，让 sing-box 接管。

## 症状：服务起不来

```sh
logread | grep sing-box | tail -20
```

常见：

- `initialize cache-file: timeout` → 有旧实例占着 `cache.db`，先 `pkill -f sing-box` 再启动
- `decode config` → 配置字段不兼容 1.14，参考上面的「sing-box 1.14 配置变化」

## 症状：面板打不开

```sh
ls /etc/sing-box/ui/index.html          # 文件在不在
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:9090/ui/
```
