#!/usr/bin/env python3
"""AfterMathsV 订阅同步：机场域名节点 + 自有美国节点 + CDN 节点 → 推送到 Worker"""
import json, re, sys, time, urllib.request, yaml

SUB_URL = "https://api6.nimenshishangdi.cc/dazhutou/4349f2e77891915e6c89a59d35d1bc21"
API     = "https://aftermaths.dpdns.org/api/admin/config"
ADMIN   = "Cheng789@"
UA      = "clash.meta/1.19.0"
BAD     = ("失效", "重新复制", "如果只显示", "剩余", "过期")
LOG     = "/home/arctic/amv-sync.log"

# 自有美国 VPS（给没有 IPv6 的用户）
US = [
 {"type":"hysteria2","tag":"🇺🇸美国hy2","server":"192.227.148.58","server_port":8882,
  "password":"UShy2_5107eca0b6ee",
  "tls":{"enabled":True,"server_name":"addons.mozilla.org","insecure":True,"alpn":["h3"]}},
 {"type":"vless","tag":"🇺🇸美国Reality","server":"192.227.148.58","server_port":9443,
  "uuid":"8983205a-b972-4e97-bdd9-5ea8e8ceb2c8","flow":"xtls-rprx-vision",
  "tls":{"enabled":True,"server_name":"www.sjsu.edu","utls":{"enabled":True,"fingerprint":"chrome"},
         "reality":{"enabled":True,"public_key":"rJtZCIQppSjCGT5yJcFnlLQRWfWZ6L8N_YWBuRyHAhw","short_id":"bbe5f0cd"}}},
 {"type":"tuic","tag":"🇺🇸美国TUIC","server":"192.227.148.58","server_port":8883,
  "uuid":"456c8c6f-b1b9-466f-9c42-0fa435eb5e25","password":"l+dW7SaCj7Wg2rDVvaHWZA==",
  "congestion_control":"bbr",
  "tls":{"enabled":True,"server_name":"addons.mozilla.org","insecure":True,"alpn":["h3"]}},
 {"type":"anytls","tag":"🇺🇸美国AnyTLS","server":"192.227.148.58","server_port":2096,
  "password":"us_anytls_9d4f71","tls":{"enabled":True,"server_name":"www.sjsu.edu","insecure":True}},
 {"type":"vless","tag":"🇺🇸美国AnyReality","server":"192.227.148.58","server_port":2097,
  "uuid":"a2b3c4d5-e6f7-4a8b-9c0d-e1f2a3b4c5d6","flow":"xtls-rprx-vision",
  "tls":{"enabled":True,"server_name":"www.cloudflare.com","utls":{"enabled":True,"fingerprint":"chrome"},
         "reality":{"enabled":True,"public_key":"mWHnxUyJOo2IVpOglm138hJ2BkurpXjkhCqrR3uWNxw","short_id":"c3d4e5f6"}}},
]

# Cloudflare CDN（隐藏源站，IPv4 可用）
CDN = [
 {"type":"vmess","tag":"🇺🇸CDN-美国","server":"c3.aftermaths.online","server_port":443,
  "uuid":"f2a3b4c5-d6e7-4f80-91a2-b3c4d5e6f708","security":"auto",
  "transport":{"type":"ws","path":"/argo","headers":{"Host":"c3.aftermaths.online"}},
  "tls":{"enabled":True,"server_name":"c3.aftermaths.online"}},
 {"type":"vmess","tag":"🇲🇾CDN-马来","server":"b2.aftermaths.online","server_port":443,
  "uuid":"e1f2a3b4-c5d6-4e7f-8091-a2b3c4d5e6f7","security":"auto",
  "transport":{"type":"ws","path":"/argo","headers":{"Host":"b2.aftermaths.online"}},
  "tls":{"enabled":True,"server_name":"b2.aftermaths.online"}},
 {"type":"vmess","tag":"🇯🇵CDN-日本","server":"a1.aftermaths.online","server_port":443,
  "uuid":"c32302b1-65da-40bf-a29b-0294883cdb37","security":"auto",
  "transport":{"type":"ws","path":"/argo","headers":{"Host":"a1.aftermaths.online"}},
  "tls":{"enabled":True,"server_name":"a1.aftermaths.online"}},
]

def log(m):
    line = f"[{time.strftime('%H:%M:%S')}] {m}"
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")

def conv(p):
    t=p.get("type"); srv=p.get("server"); port=int(p.get("port",0))
    if not srv or not port: return None
    tag=re.sub(r"[|｜].*$","",p.get("name","")).strip()[:38]
    base={"tag":tag,"server":srv,"server_port":port}
    sni=p.get("servername") or p.get("sni") or ""
    ins=bool(p.get("skip-cert-verify"))
    if t=="vless":
        o={**base,"type":"vless","uuid":p.get("uuid","")}
        if p.get("flow"): o["flow"]=p["flow"]
        tls={"enabled":True}
        if sni: tls["server_name"]=sni
        ro=p.get("reality-opts")
        if ro:
            tls["utls"]={"enabled":True,"fingerprint":p.get("client-fingerprint","chrome")}
            tls["reality"]={"enabled":True,"public_key":ro.get("public-key",""),"short_id":ro.get("short-id","")}
        elif ins: tls["insecure"]=True
        o["tls"]=tls; return o
    if t in ("anytls","hysteria2"):
        o={**base,"type":t,"password":p.get("password","")}
        tls={"enabled":True}
        if sni: tls["server_name"]=sni
        if ins: tls["insecure"]=True
        o["tls"]=tls; return o
    if t=="vmess":
        o={**base,"type":"vmess","uuid":p.get("uuid",""),"security":"auto"}
        if p.get("network")=="ws":
            ws=p.get("ws-opts") or {}
            o["transport"]={"type":"ws","path":ws.get("path","/"),"headers":ws.get("headers") or {}}
        if p.get("tls"):
            tls={"enabled":True}
            if sni: tls["server_name"]=sni
            if ins: tls["insecure"]=True
            o["tls"]=tls
        return o
    return None

def main():
    log("开始同步")
    try:
        req=urllib.request.Request(SUB_URL, headers={"User-Agent":UA,"Accept":"*/*"})
        raw=urllib.request.urlopen(req, timeout=60).read().decode("utf-8","ignore")
        d=yaml.safe_load(raw)
    except Exception as e:
        log(f"❌ 机场订阅下载失败: {e}"); return 1

    air=[]; seen=set()
    for p in d.get("proxies",[]):
        if any(b in (p.get("name") or "") for b in BAD): continue
        o=conv(p)
        if not o: continue
        t=o["tag"]; i=2
        while t in seen: t=f"{o['tag']}-{i}"; i+=1
        o["tag"]=t; seen.add(t); air.append(o)
    log(f"机场节点 {len(air)} 个")

    nodes = US + CDN + air
    tags = [n["tag"] for n in nodes]
    SEL = "✈️ 代理｜ver" + time.strftime("%m.%d")

    cfg = {
      "log":{"level":"warn","timestamp":True},
      "experimental":{"cache_file":{"enabled":True,"store_fakeip":True,"store_rdrc":True},
                      "clash_api":{"external_controller":"127.0.0.1:9090","default_mode":"rule"}},
      "dns":{
        "servers":[
          {"type":"tls","tag":"google","server":"8.8.8.8","detour":SEL},
          {"type":"https","tag":"local","server":"223.5.5.5"},
          {"type":"fakeip","tag":"fakeip","inet4_range":"198.18.0.0/15"}
        ],
        "rules":[
          {"query_type":["A"],"server":"fakeip"},
          {"domain_suffix":[".cn"],"server":"local"},
          {"rule_set":["geosite-cn"],"server":"local"}
        ],
        "final":"google",
        "strategy":"prefer_ipv4"
      },
      "inbounds":[
        {"type":"tun","tag":"tun-in","address":["172.19.0.1/30"],"auto_route":True,"strict_route":True,"stack":"gvisor"},
        {"type":"mixed","tag":"mixed-in","listen":"127.0.0.1","listen_port":2080}
      ],
      "outbounds": nodes + [
        {"type":"selector","tag":SEL,"outbounds":tags,"default":tags[0]},
        {"type":"direct","tag":"🎯 direct"},
        {"type":"block","tag":"block"}
      ],
      "route":{
        "rules":[{"action":"sniff"},{"protocol":"dns","action":"hijack-dns"}],
        "rule_set":[{"tag":"geosite-cn","type":"remote","format":"binary",
                     "url":"https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
                     "download_detour":SEL,"update_interval":"7d"}],
        "final":SEL,
        "auto_detect_interface":True,
        "default_domain_resolver":{"server":"local"}
      }
    }

    payload=json.dumps(cfg, ensure_ascii=False).encode()
    req=urllib.request.Request(API, data=payload,
        headers={"x-admin-token":ADMIN,"content-type":"application/json",
                 "User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"},
        method="POST")
    try:
        r=urllib.request.urlopen(req, timeout=60).read().decode()
        log(f"推送: {r[:120]}")
    except Exception as e:
        log(f"❌ 推送失败: {e}"); return 1
    log(f"✅ 完成：{len(nodes)} 个节点（美国 {len(US)} + CDN {len(CDN)} + 机场 {len(air)}）")
    return 0

if __name__=="__main__":
    sys.exit(main())
