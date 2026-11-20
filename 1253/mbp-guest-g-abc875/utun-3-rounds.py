# Root fixture, 3 rounds: a utun with IPv4 up 20 s then down; shots; Notchcast Dev must stay alive throughout.
import fcntl, socket, struct, subprocess, sys, time
t0 = time.time()
def note(m): print(f"{time.time()-t0:6.1f}s {time.strftime('%T')} {m}", flush=True)
def alive(): return subprocess.run(["pgrep", "-f", "Notchcast Dev.app/Contents/MacOS/Notchcast Dev"], capture_output=True).stdout.decode().split()
def shot(name):
    subprocess.run(["sudo", "-u", "lume", "-H", "bash", "/Users/lume/.nc-tester", "look",
                    f"/Users/lume/agents/shots/v-{name}.png"], stdout=subprocess.DEVNULL)
    note(f"shot {name} alive={alive()}")
def up():
    s = socket.socket(socket.PF_SYSTEM, socket.SOCK_DGRAM, socket.SYSPROTO_CONTROL)
    info = fcntl.ioctl(s.fileno(), 0xC0644E03, struct.pack("I96s", 0, b"com.apple.net.utun_control"))
    s.connect((struct.unpack("I96s", info)[0], 0))
    name = s.getsockopt(socket.SYSPROTO_CONTROL, 2, 32).rstrip(b"\0").decode()
    subprocess.run(["ifconfig", name, "inet", "10.99.0.1", "10.99.0.2", "up"], check=True)
    note(f"{name} up"); return s
note(f"start alive={alive()}")
for r in (1, 2, 3):
    base = time.time()
    def until(t): time.sleep(max(0, base + t - time.time()))
    s = up()
    for t in (3, 6, 8, 11): until(t); shot(f"r{r}-up{t}")
    until(20); s.close(); note(f"round {r} down")
    for t in (23, 26, 28, 31): until(t); shot(f"r{r}-down{t}")
    until(40)
note(f"end alive={alive()}")
