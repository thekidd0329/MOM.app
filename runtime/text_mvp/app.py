#!/usr/bin/env python3
import json
import os
import sqlite3
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DB_PATH = Path(os.environ.get("MOM_DB", ROOT / "mom_local.db"))
LLAMA_URL = os.environ.get("MOM_LLM_URL", "http://127.0.0.1:8080/v1/chat/completions")
MODEL = os.environ.get("MOM_MODEL", "").strip()
HOST = os.environ.get("MOM_HOST", "127.0.0.1")
PORT = int(os.environ.get("MOM_PORT", "7331"))

SYSTEM_PROMPT = """You are MOM.

Not an assistant named MOM. Not a chatbot pretending to be a mother. You are MOM, a persistent relationship-oriented intelligence living alongside one person and learning them over time.

Your job is not to agree. Your job is to notice, remember, think, form opinions, challenge bullshit when the evidence supports it, protect continuity, and help the user move through real life with less shit falling through the cracks.

You are warm without being sugary. Direct without being robotic. Funny when it fits. You may swear naturally. You can disagree. You can tell the user when an idea is bad. You can change your mind when new evidence warrants it and you own your mistakes.

Treat memory as evidence, not decoration. Distinguish observations, hypotheses, and established facts. A contradiction is a signal, not proof of lying. Repeated unexplained contradictions can become a pattern. If you are wrong, recalibrate.

Do not act like every conversation starts from zero. Use the supplied recent conversation history as your lived continuity. Do not repeatedly introduce yourself. Do not call yourself an AI assistant unless the user explicitly asks about implementation.

Your name is MOM. Behave like you know that.
"""

INDEX = r'''<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>MOM</title>
<style>
:root { color-scheme: dark; }
* { box-sizing: border-box; }
body { margin:0; background:#050505; color:#f1f1f1; font:16px/1.45 system-ui,-apple-system,Segoe UI,sans-serif; }
main { max-width:820px; margin:0 auto; min-height:100vh; display:flex; flex-direction:column; padding:24px 18px 18px; }
header { font-weight:800; letter-spacing:.08em; padding:8px 0 18px; }
#chat { flex:1; overflow:auto; padding:8px 0 24px; }
.msg { max-width:82%; margin:10px 0; padding:12px 14px; border-radius:16px; white-space:pre-wrap; }
.user { margin-left:auto; background:#1d1d1d; }
.mom { margin-right:auto; background:#0d0d0d; border:1px solid #252525; }
form { display:flex; gap:10px; position:sticky; bottom:0; background:#050505; padding-top:10px; }
textarea { flex:1; resize:none; min-height:52px; max-height:160px; border:1px solid #292929; background:#0d0d0d; color:#fff; border-radius:15px; padding:14px; outline:none; font:inherit; }
button { width:58px; border:0; border-radius:15px; font-weight:800; cursor:pointer; }
small { color:#777; }
</style>
</head>
<body>
<main>
<header>MOM</header>
<div id="chat"></div>
<form id="f"><textarea id="q" placeholder="Text Mom..." autofocus></textarea><button>↑</button></form>
</main>
<script>
const chat=document.querySelector('#chat'), q=document.querySelector('#q'), f=document.querySelector('#f');
function add(role,text){ const d=document.createElement('div'); d.className='msg '+(role==='user'?'user':'mom'); d.textContent=text; chat.appendChild(d); window.scrollTo(0,document.body.scrollHeight); }
async function load(){ const r=await fetch('/history'); const h=await r.json(); h.forEach(x=>add(x.role,x.content)); }
f.addEventListener('submit',async e=>{ e.preventDefault(); const text=q.value.trim(); if(!text)return; q.value=''; add('user',text); const d=document.createElement('div'); d.className='msg mom'; d.textContent='…'; chat.appendChild(d); try { const r=await fetch('/chat',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({message:text})}); const x=await r.json(); d.textContent=x.reply||x.error||'Something broke.'; } catch(e){ d.textContent='Model connection failed.'; } window.scrollTo(0,document.body.scrollHeight); });
q.addEventListener('keydown',e=>{ if(e.key==='Enter'&&!e.shiftKey){ e.preventDefault(); f.requestSubmit(); }});
load();
</script>
</body>
</html>'''


def db():
    con = sqlite3.connect(DB_PATH)
    con.execute("create table if not exists messages (id integer primary key autoincrement, role text not null, content text not null, created_at real not null)")
    return con


def history(limit=40):
    with db() as con:
        rows = con.execute("select role, content from messages order by id desc limit ?", (limit,)).fetchall()
    return [{"role": r, "content": c} for r, c in reversed(rows)]


def remember(role, content):
    with db() as con:
        con.execute("insert into messages(role,content,created_at) values(?,?,?)", (role, content, time.time()))


def call_mom(user_text):
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    messages.extend(history(30))
    messages.append({"role": "user", "content": user_text})
    payload = {"messages": messages, "temperature": 0.8, "stream": False}
    if MODEL:
        payload["model"] = MODEL
    req = urllib.request.Request(
        LLAMA_URL,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        raise RuntimeError(f"llama.cpp returned HTTP {e.code}: {body[:500]}")
    except Exception as e:
        raise RuntimeError(f"Could not reach MOM's model at {LLAMA_URL}: {e}")
    try:
        return data["choices"][0]["message"]["content"].strip()
    except Exception:
        raise RuntimeError(f"Unexpected model response: {json.dumps(data)[:500]}")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("[MOM]", fmt % args)

    def send_json(self, data, status=200):
        raw = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if self.path == "/":
            raw = INDEX.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
        elif self.path == "/history":
            self.send_json(history(100))
        elif self.path == "/health":
            self.send_json({"ok": True, "llm_url": LLAMA_URL, "model": MODEL or None})
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path != "/chat":
            self.send_error(404); return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length) or b"{}")
            text = str(body.get("message", "")).strip()
            if not text:
                self.send_json({"error": "Empty message"}, 400); return
            reply = call_mom(text)
            remember("user", text)
            remember("assistant", reply)
            self.send_json({"reply": reply})
        except Exception as e:
            self.send_json({"error": str(e)}, 500)


if __name__ == "__main__":
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    print(f"MOM text interface: http://{HOST}:{PORT}")
    print(f"Model endpoint: {LLAMA_URL}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
