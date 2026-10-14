#!/usr/bin/env python3
"""usage: rec-websocket.py

Test tier T0 for dotfiles/.local/bin/rec (docs/toolchain/profiles/creator.md), any machine with Python 3:
starts a mock obs-websocket v5 server on 127.0.0.1 (RFC 6455 framing, the Hello/Identify
challenge-response with a password, GetRecordStatus/StartRecord/StopRecord) and drives
`rec` against it: a wrong password is refused, start/status/stop/toggle change and report
the state, and a server without the record requests answers with an error. bin/check.sh
runs it.

exit: 0 every check passed · 1 a check failed
"""
import base64, hashlib, json, os, socket, struct, subprocess, sys, tempfile, threading

if len(sys.argv) > 1:
    print(__doc__.strip())
    sys.exit(0 if sys.argv[1] in ("-h", "--help") else 2)

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REC = os.path.join(REPO, "dotfiles", ".local", "bin", "rec")
PASSWORD = "test-password"
STATE = {"active": False}


def frame(data, opcode=1):
    n = len(data)
    head = struct.pack("!BB", 0x80 | opcode, n) if n < 126 else struct.pack("!BBH", 0x80 | opcode, 126, n)
    return head + data


def read_frame(c):
    def rd(n):
        b = b""
        while len(b) < n:
            chunk = c.recv(n - len(b))
            if not chunk:
                raise ConnectionError
            b += chunk
        return b
    b1, b2 = rd(2)
    n = b2 & 0x7F
    if n == 126:
        (n,) = struct.unpack("!H", rd(2))
    elif n == 127:
        (n,) = struct.unpack("!Q", rd(8))
    if not b2 & 0x80:
        raise ValueError("client frame not masked")
    mask = rd(4)
    return b1 & 0x0F, bytes(b ^ mask[i % 4] for i, b in enumerate(rd(n)))


def serve_one(c):
    req = b""
    while b"\r\n\r\n" not in req:
        req += c.recv(1024)
    key = [l.split(":", 1)[1].strip() for l in req.decode().split("\r\n") if l.lower().startswith("sec-websocket-key:")][0]
    acc = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    c.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               "Sec-WebSocket-Accept: %s\r\nSec-WebSocket-Protocol: obswebsocket.json\r\n\r\n" % acc).encode())
    salt, challenge = "c2FsdA==", "Y2hhbGxlbmdl"
    c.sendall(frame(json.dumps({"op": 0, "d": {"obsWebSocketVersion": "5.6.0", "rpcVersion": 1,
                                               "authentication": {"salt": salt, "challenge": challenge}}}).encode()))
    _, data = read_frame(c)
    ident = json.loads(data)
    secret = base64.b64encode(hashlib.sha256((PASSWORD + salt).encode()).digest()).decode()
    want = base64.b64encode(hashlib.sha256((secret + challenge).encode()).digest()).decode()
    if ident["d"].get("authentication") != want:
        c.sendall(frame(struct.pack("!H", 4009) + b"Authentication failed.", opcode=8))
        return
    c.sendall(frame(json.dumps({"op": 2, "d": {"negotiatedRpcVersion": 1}}).encode()))
    while True:
        try:
            op, data = read_frame(c)
        except (ConnectionError, ValueError):
            return
        if op == 8:
            return
        d = json.loads(data)["d"]
        kind, rid, resp, ok = d["requestType"], d["requestId"], {}, True
        if kind == "GetRecordStatus":
            resp = {"outputActive": STATE["active"], "outputPaused": False, "outputTimecode": "00:01:02.000"}
        elif kind == "StartRecord":
            ok = not STATE["active"]
            STATE["active"] = True
        elif kind == "StopRecord":
            ok = STATE["active"]
            STATE["active"] = False
            resp = {"outputPath": "/data/recordings/2026-10-11 10-00-00.mkv"}
        else:
            ok = False
        c.sendall(frame(json.dumps({"op": 7, "d": {"requestType": kind, "requestId": rid, "responseData": resp,
                                                   "requestStatus": {"result": ok, "code": 100 if ok else 501}}}).encode()))


srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0))
srv.listen(8)
PORT = srv.getsockname()[1]


def loop():
    while True:
        c, _ = srv.accept()
        threading.Thread(target=lambda: (serve_one(c), c.close()), daemon=True).start()


threading.Thread(target=loop, daemon=True).start()
fails = 0
home = tempfile.mkdtemp()


def rec(*args, password=PASSWORD):
    env = dict(os.environ, HOME=home, DRAM_OBS_HOST="127.0.0.1", DRAM_OBS_PORT=str(PORT),
               DRAM_OBS_PASSWORD=password, XDG_RUNTIME_DIR=home)
    p = subprocess.run([sys.executable, REC, *args, "--no-spare"], env=env, capture_output=True, text=True, timeout=20)
    return p.returncode, p.stdout + p.stderr


def check(name, cond, out=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        fails += 1
        print("     " + out.strip().replace("\n", "\n     "))


rc, out = rec("status", password="wrong")
check("a wrong password is refused (exit 1)", rc == 1 and ("did not accept" in out or "closed by OBS" in out), out)
rc, out = rec("status")
check("status: not recording", rc == 0 and "not recording" in out, out)
rc, out = rec("start")
check("start: OBS records", rc == 0 and STATE["active"], out)
rc, out = rec("status")
check("status: recording with a timecode", rc == 0 and "recording, 00:01:02" in out, out)
rc, out = rec("start")
check("start while recording changes nothing", rc == 0 and STATE["active"], out)
rc, out = rec("stop")
check("stop: OBS stops and the file is named", rc == 0 and not STATE["active"] and "saved /data/recordings/" in out, out)
rc, out = rec("toggle")
check("toggle from stopped starts", rc == 0 and STATE["active"], out)
rc, out = rec("toggle")
check("toggle from recording stops", rc == 0 and not STATE["active"], out)
rc, out = rec("bogus")
check("an unknown command exits 2", rc == 2, out)
env = dict(os.environ, HOME=home, XDG_RUNTIME_DIR=home)
p = subprocess.run([sys.executable, REC, "status"], env={k: v for k, v in env.items() if not k.startswith("DRAM_OBS")}, capture_output=True, text=True)
check("no recorder configured: a clear message, exit 1", p.returncode == 1 and "no recorder configured" in p.stderr, p.stderr)
p = subprocess.run([sys.executable, REC, "server-setup"], env=env, capture_output=True, text=True)
cfg = os.path.join(home, ".config", "obs-studio", "plugin_config", "obs-websocket", "config.json")
ok = p.returncode == 0 and os.path.isfile(cfg) and oct(os.stat(cfg).st_mode & 0o777) == "0o600"
conf = json.load(open(cfg)) if os.path.isfile(cfg) else {}
check("server-setup writes OBS's websocket config, 0600, auth on, port 4455",
      ok and conf.get("server_enabled") and conf.get("auth_required") and conf.get("server_port") == 4455, p.stdout + p.stderr)
check("server-setup prints the password for cabin", conf.get("server_password", "x") in p.stdout, p.stdout)
p2 = subprocess.run([sys.executable, REC, "server-setup"], env=env, capture_output=True, text=True)
check("a second server-setup leaves the config alone", "left alone" in p2.stdout and json.load(open(cfg)) == conf, p2.stdout)
print("rec-websocket: all checks passed" if not fails else "rec-websocket: %d check(s) failed" % fails)
sys.exit(1 if fails else 0)
