#!/usr/bin/env python3
"""Feeds the app without touching ~/.claude/settings.json: runs claude in a pty with a --settings override whose
statusLine command is a copy of the hook script pointed at the app's data folder, sends one prompt, waits, exits.
No screen emulation; the raw output goes to a log.

  scripts/pty-feed.py <hook.sh path> <work dir> [log file]
"""
import os, pty, sys, time, select, fcntl, termios, struct, json, signal

HOOK = os.path.abspath(sys.argv[1])
WORK = os.path.abspath(sys.argv[2]); os.makedirs(WORK, exist_ok=True)
LOG = sys.argv[3] if len(sys.argv) > 3 else os.path.join(WORK, "pty.log")
# the command runs in a shell: the path is single quoted, Application Support has a space in it
SETTINGS = json.dumps({"statusLine": {"type": "command", "command": "'" + HOOK.replace("'", "'\\''") + "'", "refreshInterval": 5}})

pid, fd = pty.fork()
if pid == 0:
    os.chdir(WORK)
    os.environ["TERM"] = "xterm-256color"
    for k in [k for k in os.environ if k.startswith("CLAUDE")]:
        os.environ.pop(k, None)
    os.execvp("claude", ["claude", "--settings", SETTINGS])

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 96, 0, 0))
log = open(LOG, "wb")

def pump(seconds):
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if fd in r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return
            log.write(data); log.flush()

def send(s, wait):
    os.write(fd, s.encode()); pump(wait)

print("start", time.strftime("%H:%M:%S"), flush=True)
pump(8)
send("\x1b[B", 1); send("\r", 6)          # the trust prompt: Down, Enter
send("say ok", 1); send("\r", 30)         # one prompt; the feed carries rate_limits after the first reply
pump(30)
send("/exit", 1); send("\r", 4)
try:
    os.kill(pid, signal.SIGTERM)
except Exception:
    pass
print("done", time.strftime("%H:%M:%S"), flush=True)
