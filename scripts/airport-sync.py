#!/usr/bin/env python3
"""拉机场订阅，合并进路由器 sing-box 配置（ship1..N）"""
import json, subprocess, sys, urllib.request, urllib.parse, base64, re

BASE  = "https://aftermaths.dpdns.org"
CODE  = "85KH-JUFQ-9D6C-8FD4"
DEV   = "router-airport"
ROUTER= ("root@192.168.0.252")
SSHOPT= ["-F","/dev/null","-o","BatchMode=yes","-o","StrictHostKeyChecking=no",
         "-o","UserKnownHostsFile=/dev/null","-o","ConnectTimeout=15"]
CFG   = "/etc/sing-box/config.json"

def sh(cmd, inp=None, timeout=120):
    return subprocess.run(cmd, input=inp, capture_output=True, text=True, timeout=timeout)

def ssh(script, inp=None, timeout=120):
    return sh(["ssh"]+SSHOPT+[ROUTER, script], inp=inp, timeout=timeout)

def log(m): print(m, flush=True)

# 1. 换 token
r = sh(["curl","-sS","-m","20","-X","POST",f"{BASE}/api/redeem",
        "-H","content-type: application/json",
        "-d",json.dumps({"code":CODE,"device":DEV})])
try:
    tok = json.loads(r.stdout).get("token","")
except Exception:
    tok = ""
if not tok:
    log("❌ 取 token 失败: "+r.stdout[:120]); sys.exit(1)
log(f"✅ token 获取成功")

# 2. 拉订阅
q = urllib.parse.urlencode({"token":tok,"device":DEV})
r = sh(["curl","-sS","-m","40",f"{BASE}/api/sub?{q}"])
try:
    sub = json.loads(r.stdout)
except Exception:
    log("❌ 订阅解析失败: "+r.stdout[:120]); sys.exit(1)

nodes = [o for o in sub.get("outbounds",[])
         if o.get("type") not in ("selector","urltest","direct","block","dns")]
log(f"   订阅里 {len(nodes)} 个节点")

# 3. 生成 ship 出站
ship = []
for i, o in enumerate(nodes, 1):
    tag = o.get("tag","node"+str(i))
    short = re.sub(r"^🚢\d+\s*","",tag).strip()
    o = dict(o)
    o["tag"] = f"ship{i} {short}"[:48]
    o["bind_interface"] = "eth0"
    o["routing_mark"] = 2
    ship.append(o)

# 4. 取路由器当前配置
r = ssh(f"cat {CFG}")
if r.returncode != 0 or not r.stdout.strip():
    log("❌ 读取路由器配置失败"); sys.exit(1)
cfg = json.loads(r.stdout)

# 5. 合并：删旧 ship，插入新 ship
outs = [o for o in cfg["outbounds"] if not str(o.get("tag","")).startswith("ship")]
ship_tags = [o["tag"] for o in ship]
outs += ship

# 6. 重建 airport 组，并让 proxy 选择器包含它
outs = [o for o in outs if o.get("tag") != "airport"]
try:
    idx = next(i for i,o in enumerate(outs) if o.get("tag")=="proxy")
except StopIteration:
    idx = len(outs)
outs.insert(idx, {"type":"urltest","tag":"airport","outbounds":ship_tags,
                  "url":"https://www.gstatic.com/generate_204",
                  "interval":"10m","tolerance":80})
for o in outs:
    if o.get("tag")=="proxy":
        keep = [t for t in o.get("outbounds",[]) if t != "airport" and not t.startswith("ship")]
        head = [t for t in keep if t in ("auto","airport")][:1]
        rest = [t for t in keep if t not in head]
        o["outbounds"] = head + ["airport"] + rest + ship_tags
        if not o.get("default"):
            o["default"] = "auto" if "auto" in o["outbounds"] else o["outbounds"][0]
cfg["outbounds"] = outs

payload = json.dumps(cfg, ensure_ascii=False, indent=2)

# 7. 写入 + 校验 + 重启
r = ssh(f"cat > /tmp/newcfg.json && /etc/sing-box/sing-box check -c /tmp/newcfg.json && "
        f"cp /tmp/newcfg.json {CFG} && /etc/init.d/sing-box restart && sleep 5 && "
        f"/etc/init.d/sing-box status", inp=payload, timeout=180)
log("   路由器: " + (r.stdout.strip().replace("\n"," | ")[-120:] or r.stderr.strip()[-120:]))
if r.returncode != 0:
    log("❌ 应用失败"); sys.exit(1)
log(f"✅ 完成：{len(ship)} 个机场节点已合并")
