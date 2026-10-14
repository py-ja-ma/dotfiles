#!/usr/bin/env python3
"""usage: case-display.py

Test tier T0 for pkgs/dram-case-display (docs/platforms/arch/case-display.md), on any machine with Python 3
and no panel: the frame encoder against the protocol's four test vectors; the usbfs ioctl
numbers against linux/usbdevice_fs.h on x86_64; the panel and k10temp's Tctl found in a fake
sysfs (revision A: OUT 0x03, no driver; revision B: IN 0x81 + OUT 0x02, usbhid); NVML through
a fake library; and the loop against a fake usbfs: disconnect-claim, a 12-byte frame a beat,
64 bytes after a stall, the panel found again after an unplug, a busy panel left alone, and
at the stop a blank frame, the interface released and usbhid given it back. bin/check.sh
runs it (section 20) as `python3 -I tests/case-display.py`.

exit: 0 every check passed · 1 a check failed
"""
import contextlib
import ctypes
import errno
import fcntl
import importlib.machinery
import importlib.util
import io
import os
import sys
import tempfile
import threading
import types

if len(sys.argv) > 1:
    print(__doc__.strip())
    sys.exit(0 if sys.argv[1] in ("-h", "--help") else 2)

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROG = os.path.join(REPO, "pkgs", "dram-case-display", "case-display")
sys.dont_write_bytecode = True  # no __pycache__ beside the package's sources
loader = importlib.machinery.SourceFileLoader("case_display", PROG)
cd = importlib.util.module_from_spec(importlib.util.spec_from_loader("case_display", loader))
loader.exec_module(cd)
said = []
cd.say = lambda topic, msg, warning=False: said.append(msg)
cd.PERIOD = cd.RETRY = 0.001
fails = 0


def check(name, cond, got=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        fails += 1
        print("     got: %s" % (got,))


# --- the frame ---------------------------------------------------------------------
VECTORS = [((24.0, 16.0), "55 aa 01 01 06 02 04 00 01 06 00 14"),  # nishtahir's own test
           ((24.0, None), "55 aa 01 01 06 02 04 00 ee ee ee d7"),
           ((44.3, 52.0), "55 aa 01 01 06 04 04 03 05 02 00 19"),
           ((None, None), "55 aa 01 01 06 ee ee ee ee ee ee 9b")]
for (c, g), want in VECTORS:
    got = cd.frame(c, g).hex(" ")
    check("frame(%s, %s) = %s" % (c, g, want), got == want, got)
check("67.375 (k10temp's millidegrees / 1000) shows 67.4", cd.digits(67.375) == [6, 7, 4], cd.digits(67.375))
got = cd.frame(120.0, -3.0).hex(" ").split()[5:11]
check("out of range: 99.9 and 00.0, never a digit above 9", got == "09 09 09 00 00 00".split(), got)
check("NaN blanks its field", cd.digits(float("nan")) == [0xEE] * 3, cd.digits(float("nan")))

# --- usbfs: the ioctl numbers, and fcntl.ioctl takes them ----------------------------
if ctypes.sizeof(ctypes.c_void_p) == 8:
    for name, want in (("USBDEVFS_BULK", 0xC0185502), ("USBDEVFS_RELEASEINTERFACE", 0x80045510),
                       ("USBDEVFS_IOCTL", 0xC0105512), ("USBDEVFS_CLEAR_HALT", 0x80045515),
                       ("USBDEVFS_CONNECT", 0x5517), ("USBDEVFS_DISCONNECT_CLAIM", 0x8108551B)):
        check("%s = 0x%X" % (name, want), getattr(cd, name) == want, hex(getattr(cd, name)))
with tempfile.TemporaryFile() as tf:
    try:
        fcntl.ioctl(tf.fileno(), cd.USBDEVFS_BULK, cd.Bulk(2, 12, 1000, None))
        err = "no error"
    except OSError as e:
        err = e.errno
    except (TypeError, OverflowError, ValueError) as e:
        err = repr(e)
check("fcntl.ioctl takes USBDEVFS_BULK and its struct (a plain file answers ENOTTY)", err == errno.ENOTTY, err)

# --- sysfs: the panel's two revisions, k10temp --------------------------------------
tmp = tempfile.TemporaryDirectory()


def tree(name, files, links=()):
    root = os.path.join(tmp.name, name)
    for path, content in files.items():
        os.makedirs(os.path.dirname(os.path.join(root, path)), exist_ok=True)
        with open(os.path.join(root, path), "w") as f:
            f.write(content + "\n")
    for path, target in links:
        os.makedirs(os.path.dirname(os.path.join(root, path)), exist_ok=True)
        os.symlink(target, os.path.join(root, path))
    return root


def usb(name, vid, pid, bus, dev, bcd, eps):
    d = "sys/bus/usb/devices/%s/" % name
    files = {d + "idVendor": vid, d + "idProduct": pid, d + "busnum": bus, d + "devnum": dev, d + "bcdDevice": bcd}
    for addr, direction, kind in eps:
        e = "%s%s:1.0/ep_%02x/" % (d, name, addr)
        files.update({e + "bEndpointAddress": "%02x" % addr, e + "direction": direction, e + "type": kind})
    return files


HUB = usb("usb1", "1d6b", "0002", "1", "1", "0617", [])
REV_A = usb("1-4", "2022", "0522", "1", "4", "0006", [(0x03, "out", "Interrupt")])
REV_B = usb("3-2", "2022", "0522", "3", "2", "0100", [(0x81, "in", "Interrupt"), (0x02, "out", "Interrupt")])
USBHID = [("sys/bus/usb/devices/3-2/3-2:1.0/driver", "../../../../../bus/usb/drivers/usbhid")]
HWMON = {"sys/class/hwmon/hwmon0/name": "nvme", "sys/class/hwmon/hwmon0/temp1_label": "Composite",
         "sys/class/hwmon/hwmon0/temp1_input": "40850", "sys/class/hwmon/hwmon3/name": "k10temp",
         "sys/class/hwmon/hwmon3/temp1_label": "Tctl", "sys/class/hwmon/hwmon3/temp1_input": "67375",
         "sys/class/hwmon/hwmon3/temp3_label": "Tccd1", "sys/class/hwmon/hwmon3/temp3_input": "55000"}
A = tree("a", dict(HUB, **REV_A, **HWMON), [("sys/bus/usb/devices/1-4:1.0", "1-4/1-4:1.0")])
B = tree("b", dict(HUB, **REV_B, **HWMON), USBHID)

cd.SYS = A + "/sys"
p = cd.find_panel()
check("revision A: /dev/bus/usb/001/004, OUT 0x03, no driver",
      p == {"node": "/dev/bus/usb/001/004", "ep": 0x03, "bcd": "0006", "driver": "none"}, p)
check("the log line names revision A", p and "revision A (bcdDevice 0006)" in cd.describe(p), p and cd.describe(p))
check("the CPU: k10temp's Tctl, not the NVMe's sensor (67.375)", cd.Cpu().read() == 67.375)
cd.SYS = B + "/sys"
p = cd.find_panel()
check("revision B: /dev/bus/usb/003/002, OUT 0x02 (not IN 0x81), usbhid",
      p == {"node": "/dev/bus/usb/003/002", "ep": 0x02, "bcd": "0100", "driver": "usbhid"}, p)
cd.SYS = tree("none", HUB) + "/sys"
check("no panel, no k10temp: None and a blank CPU field", cd.find_panel() is None and cd.Cpu().read() is None)

# --- NVML, through a fake library ---------------------------------------------------
class FakeNvml:
    def __init__(self, init_rc=0, temp_rc=0):
        self.init_rc, self.temp_rc, self.inits, self.shutdowns, self.version = init_rc, temp_rc, 0, 0, None

    def nvmlInit_v2(self):
        self.inits += 1
        return self.init_rc

    def nvmlShutdown(self):
        self.shutdowns += 1
        return 0

    def nvmlErrorString(self, rc):
        return b"Driver Not Loaded"

    def nvmlDeviceGetHandleByIndex_v2(self, index, ref):
        ref._obj.value = 0x1000
        return 0

    def nvmlDeviceGetName(self, dev, buf, n):
        buf.value = b"NVIDIA GeForce RTX 3080 Ti"
        return 0

    def nvmlDeviceGetTemperature(self, dev, sensor, ref):
        ref._obj.value = 36
        return self.temp_rc

    def nvmlDeviceGetTemperatureV(self, dev, ref):
        self.version = ref._obj.version
        ref._obj.temperature = 41
        return 0


gpu = cd.Gpu()
gpu.nvml = FakeNvml()
check("GPU: 36.0 from nvmlDeviceGetTemperature", gpu.read() == 36.0 and said[-1].startswith("GPU: NVIDIA GeForce"),
      said[-1:])
gpu.nvml.temp_rc = 15
check("GPU: a failed reading blanks the field and shuts NVML down", gpu.read() is None and gpu.nvml.shutdowns == 1)
gpu = cd.Gpu()
gpu.nvml = FakeNvml(init_rc=9)
first, again = gpu.read(), gpu.read()
check("GPU: NVML not ready: blank, and one nvmlInit per NVML_RETRY, not per second",
      first is None and again is None and gpu.nvml.inits == 1 and "Driver Not Loaded" in said[-1], said[-1:])
gpu.nvml.init_rc, gpu.next_try = 0, 0
check("GPU: NVML ready at the next try", gpu.read() == 36.0)
gpu = cd.Gpu()
gpu.nvml, gpu.v = FakeNvml(), True
check("GPU: nvmlDeviceGetTemperatureV with version word 0x0100000C",
      gpu.read() == 41.0 and gpu.nvml.version == 0x0100000C, hex(gpu.nvml.version or 0))
check("GPU: no libnvidia-ml (no NVIDIA driver here): blank", cd.Gpu(lib="libnvidia-ml-nowhere.so.1").read() is None)


# --- the loop, against a fake usbfs -------------------------------------------------
class FakeUsbfs:
    """fcntl.ioctl on the panel's node, recorded; the stop event is set after `frames` frames."""

    def __init__(self, frames, stall=False, unplug_at=None, busy=False):
        self.stop, self.frames, self.stall = threading.Event(), frames, stall
        self.unplug_at, self.busy = unplug_at, busy
        self.log, self.sent = [], []  # every ioctl in order; the bytes of every frame sent

    def ioctl(self, fd, req, arg=0, mutate=True):
        if req == cd.USBDEVFS_DISCONNECT_CLAIM:
            self.log.append(("claim", arg.interface, arg.flags, arg.driver))
            if self.busy:
                raise OSError(errno.EBUSY, os.strerror(errno.EBUSY))
        elif req == cd.USBDEVFS_RELEASEINTERFACE:
            self.log.append(("release", arg.value))
        elif req == cd.USBDEVFS_IOCTL:
            self.log.append(("ioctl", arg.ifno, arg.ioctl_code))
        elif req == cd.USBDEVFS_CLEAR_HALT:
            self.log.append(("clear-halt", arg.value))
        elif req == cd.USBDEVFS_BULK:
            self.log.append(("bulk", arg.ep, arg.len, arg.timeout))
            if self.stall and arg.len == 12:
                raise OSError(errno.EPIPE, os.strerror(errno.EPIPE))
            if len(self.sent) == self.unplug_at:
                self.unplug_at = None
                raise OSError(errno.ENODEV, os.strerror(errno.ENODEV))
            self.sent.append(ctypes.string_at(arg.data, arg.len))
            if len(self.sent) >= self.frames:
                self.stop.set()
            return arg.len
        else:
            raise AssertionError("unexpected ioctl 0x%x" % req)
        return 0


class FakeGpu:
    def read(self):
        return 36.0

    def stop(self):
        pass


cd.Gpu = FakeGpu
for root, node in ((A, "001/004"), (B, "003/002")):
    os.makedirs(os.path.dirname(os.path.join(root, "dev", node)), exist_ok=True)
    open(os.path.join(root, "dev", node), "w").close()


def loop(root, fake, **kw):
    cd.SYS, cd.DEV, cd.fcntl = root + "/sys", root + "/dev", types.SimpleNamespace(ioctl=fake.ioctl)
    timer = threading.Timer(10, fake.stop.set)  # a hang fails the checks instead of the run
    timer.start()
    try:
        with contextlib.redirect_stdout(io.StringIO()) as out:
            rc = cd.run(fake.stop, **kw)
        return rc, out.getvalue()
    finally:
        timer.cancel()


F = cd.frame(67.375, 36.0)
BLANK = cd.frame(None, None)
CLAIM = ("claim", 0, cd.EXCEPT_DRIVER, b"usbfs")
fake = FakeUsbfs(3)
rc, _ = loop(B, fake)
want = [CLAIM] + [("bulk", 0x02, 12, 1000)] * 4 + [("release", 0), ("ioctl", 0, cd.USBDEVFS_CONNECT)]
check("revision B: disconnect-claim (never from another usbfs program), 12-byte frames to 0x02, "
      "then the blank frame, release, usbhid back", rc == 0 and fake.log == want, fake.log)
check("revision B: the frames carry Tctl and the GPU, the last one blanks both",
      fake.sent == [F, F, F, BLANK], [s.hex(" ") for s in fake.sent])
fake = FakeUsbfs(2)
rc, _ = loop(A, fake)
want = [CLAIM] + [("bulk", 0x03, 12, 1000)] * 3 + [("release", 0)]
check("revision A: frames to 0x03, no kernel driver to give it back to", rc == 0 and fake.log == want, fake.log)
said.clear()
fake = FakeUsbfs(2, stall=True)
rc, _ = loop(A, fake)
check("a stall on 12 bytes: clear the halt, then 64-byte reports from then on",
      fake.log[1:5] == [("bulk", 3, 12, 1000), ("clear-halt", 3), ("bulk", 3, 64, 1000), ("bulk", 3, 64, 1000)]
      and fake.sent[0] == F + bytes(52) and any("12-byte" in m for m in said), fake.log)
fake = FakeUsbfs(3, unplug_at=1)
rc, _ = loop(A, fake)
check("an unplug (ENODEV): release, find the panel again, carry on",
      rc == 0 and [x[0] for x in fake.log].count("claim") == 2 and fake.log[3] == ("release", 0)
      and len(fake.sent) == 4, fake.log)
said.clear()
fake = FakeUsbfs(1, busy=True)
rc, _ = loop(B, fake, once=True)
check("--once with the service running: EBUSY, the panel left alone, exit 1",
      rc == 1 and fake.log == [CLAIM] and "systemctl stop" in said[-1], (rc, fake.log, said[-1:]))
fake = FakeUsbfs(1)
rc, out = loop(A, fake, once=True, size=64)
check("--once --pad: one 64-byte frame, printed, exit 0",
      rc == 0 and fake.sent == [F + bytes(52)] and out.strip() == "cpu 67.4 gpu 36.0 frame " + F.hex(" "), out)

# --- the command line ---------------------------------------------------------------
with contextlib.redirect_stdout(io.StringIO()) as out, contextlib.redirect_stderr(io.StringIO()):
    codes = [cd.main(["--help"]), cd.main(["--bogus"]), cd.main(["--print", "--once"])]
check("--help exits 0 with a usage: line; a bogus flag and --print --once exit 2",
      codes == [0, 2, 2] and out.getvalue().startswith("usage: case-display"), codes)

tmp.cleanup()
print("case-display: all checks passed" if not fails else "case-display: %d check(s) failed" % fails)
sys.exit(1 if fails else 0)
