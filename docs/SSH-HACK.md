# SSH 连不上服务器时的排查与跳板方案

记录于 2026-11-25，适用：RackNerd / Evoxt / BAGE Cloud 这类海外 VPS。

## 症状

- `ping` 正常、延迟正常
- `ssh` 连不上，或连上后立刻 `Connection closed`
- 云厂商 VNC 能登录，机器内部看 `sshd` 正在监听

## 排查顺序

### 1. 先分清 ICMP 和 TCP

`ping` 通只说明 IP 活着。真正的可用性要看 TCP：

```sh
nc -z -w 5 IP 22          # 通/不通
nmap -Pn -p 22 IP         # open / closed / filtered
```

- `closed` = 端口没监听（服务没跑）
- `filtered` = 被防火墙丢包

### 2. 第三方多地点检测

```text
https://check-host.net/check-tcp?host=IP:PORT
https://ping.pe/IP
https://www.itdog.cn/tcping/     # 国内各省
```

判断矩阵：

| 境外 | 国内 | 结论 |
|---|---|---|
| 通 | 不通 | 被墙（换端口） |
| 不通 | 不通 | 服务/防火墙问题 |
| 通 | 通 | 正常 |

### 3. 关键坑：跳板机自己可能封出站 22

BAGE Cloud 的日本机**出站 22 全封**（连 github.com:22、1.1.1.1:22 都不通）。
用它去测别人 22 端口，结论全错。测之前先验证：

```sh
nc -z -w 5 github.com 22     # 如果不通，说明这台机器不能测 22
```

### 4. Ubuntu 改 SSH 端口不生效

Ubuntu 22.10+ 用 socket 激活，改 `sshd_config` 的 `Port` 无效；
而且 `sshd_config.d/` 里的文件可能把 Port 写回 22（sshd 取**第一个** Port）。

正确做法：

```sh
systemctl disable --now ssh.socket
printf 'Port 2222\n' > /etc/ssh/sshd_config.d/00-port.conf
systemctl enable --now ssh
ss -tlnp | grep ssh          # 确认 :2222
```

`00-` 前缀保证字母序最前，最先加载。

### 5. 代理回连自身（nc 代理握手不稳）

```sh
ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:7890 127.0.0.1 22" root@127.0.0.1
```

思路：让代理在服务器上连 `127.0.0.1:22`。
**注意**：busybox 的 `nc` 做 socks5 代理时容易在 SSH 握手阶段断开，
表现为只看到 banner 就断。能连不等于能用。

## 最终可用的跳板链

```text
本机 → VM(192.168.0.23) → 日本 209.33.173.96 → 美国 192.227.148.58:2222
```

日本机到美国 2222 通（出站 22 封，但 2222 不封）。
具体命令：

```sh
ssh root@192.168.0.23
# VM 上：
SSH_ASKPASS=... setsid ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:1124 %h %p" root@209.33.173.96
# 日本上：
ssh -p 2222 root@192.227.148.58
```

## 结论

1. 新 VPS 第一件事：把 SSH 改到 2222（或 8443），别用 22
2. 测别人端口前，先确认自己这台能不能出站该端口
3. 云厂商 VNC 只用于救急，日常用跳板
