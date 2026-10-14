#!/usr/bin/env python3
"""usage: u2f-selftest.py --authfile FILE --user NAME [--service NAME]

Asks pam_u2f, through a real PAM transaction, whether a YubiKey listed in FILE
answers for NAME on this machine. It writes a one-line PAM service (default
dram-u2f-test) with the pam_u2f options of system/pam-u2f.conf, minus nouserok and
with FILE as the authfile, runs pam_authenticate, prints the module's messages
("Please touch the device."), and removes the service again. system/yubikey-setup.sh
runs it before it switches the second factor on, so a host never asks for a key that
cannot answer there (root is locked: a sudo that cannot pass is a lockout). Root.

  --authfile FILE   the candidate pam-u2f mapping file (`user:credential:...`)
  --user NAME       the login the mapping is for
  --service NAME    the PAM service to create and use (default dram-u2f-test)
  -h, --help        this text

needs:  Python 3 (standard library), Linux-PAM, pam-u2f; root
alone:  yes, with system/pam-u2f.conf beside it in system/ (or your own pam_u2f line)
here:   system/yubikey-setup.sh runs it before it switches the second factor on;
        tests/yubikey-t1.sh shows it failing fast without a key
exit:   0 a listed key answered · 1 it did not (no key here, no touch, a wrong
        credential) or not root · 2 bad usage
see:    docs/security/identity/yubikeys.md, decisions/0019-yubikeys.md
"""

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

import ctypes
import ctypes.util
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINE_SRC = os.path.join(REPO, "system", "pam-u2f.conf")

PAM_PROMPT_ECHO_OFF, PAM_PROMPT_ECHO_ON, PAM_ERROR_MSG, PAM_TEXT_INFO = 1, 2, 3, 4
PAM_SUCCESS, PAM_BUF_ERR, PAM_CONV_ERR = 0, 5, 19


def usage(code):
    if code == 0:
        print(__doc__.strip())
    else:
        print(__doc__.splitlines()[0], file=sys.stderr)
    sys.exit(code)


def parse_args(argv):
    opts = {"--authfile": None, "--user": None, "--service": "dram-u2f-test"}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            usage(0)
        elif a in opts and i + 1 < len(argv):
            opts[a] = argv[i + 1]
            i += 1
        else:
            usage(2)
        i += 1
    if not opts["--authfile"] or not opts["--user"]:
        usage(2)
    if not re.fullmatch(r"[a-z0-9-]{1,32}", opts["--service"]):
        usage(2)
    return opts["--authfile"], opts["--user"], opts["--service"]


def module_line(authfile):
    """The tracked pam_u2f line's options, with this authfile, without nouserok."""
    with open(LINE_SRC, encoding="utf-8") as f:
        for line in f:
            if line.lstrip().startswith("#") or " pam_u2f.so" not in line:
                continue
            args = line.split(" pam_u2f.so", 1)[1].split()
            args = [w for w in args if w != "nouserok" and not w.startswith("authfile=")]
            return " ".join(["auth", "required", "pam_u2f.so", "authfile=" + authfile] + args)
    raise SystemExit(f"no pam_u2f.so line in {LINE_SRC}")


class PamMessage(ctypes.Structure):
    _fields_ = [("msg_style", ctypes.c_int), ("msg", ctypes.c_char_p)]


class PamResponse(ctypes.Structure):
    _fields_ = [("resp", ctypes.c_char_p), ("resp_retcode", ctypes.c_int)]


CONV = ctypes.CFUNCTYPE(
    ctypes.c_int,
    ctypes.c_int,
    ctypes.POINTER(ctypes.POINTER(PamMessage)),
    ctypes.POINTER(ctypes.POINTER(PamResponse)),
    ctypes.c_void_p,
)


class PamConv(ctypes.Structure):
    _fields_ = [("conv", CONV), ("appdata_ptr", ctypes.c_void_p)]


def authenticate(service, user):
    libpam = ctypes.CDLL(ctypes.util.find_library("pam") or "libpam.so.0")
    libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6")
    libc.calloc.restype = ctypes.c_void_p
    libc.calloc.argtypes = [ctypes.c_size_t, ctypes.c_size_t]
    libpam.pam_start.restype = ctypes.c_int
    libpam.pam_start.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.POINTER(PamConv), ctypes.POINTER(ctypes.c_void_p)]
    libpam.pam_authenticate.restype = ctypes.c_int
    libpam.pam_authenticate.argtypes = [ctypes.c_void_p, ctypes.c_int]
    libpam.pam_end.restype = ctypes.c_int
    libpam.pam_end.argtypes = [ctypes.c_void_p, ctypes.c_int]
    libpam.pam_strerror.restype = ctypes.c_char_p
    libpam.pam_strerror.argtypes = [ctypes.c_void_p, ctypes.c_int]

    def conv(n, msgs, resp, _data):
        # PAM frees the responses itself, so they come from libc's allocator
        arr = libc.calloc(n, ctypes.sizeof(PamResponse))
        if not arr:
            return PAM_BUF_ERR
        resp[0] = ctypes.cast(arr, ctypes.POINTER(PamResponse))
        for i in range(n):
            m = msgs[i].contents
            text = (m.msg or b"").decode("utf-8", "replace")
            if m.msg_style in (PAM_TEXT_INFO, PAM_ERROR_MSG):
                print(f"  pam_u2f: {text}", flush=True)
            else:  # pam_u2f must not need an answer here (no PIN, no ENTER)
                print(f"  pam_u2f asked '{text}' — this test answers no prompts", flush=True)
                return PAM_CONV_ERR
        return PAM_SUCCESS

    cb = CONV(conv)  # both stay referenced until pam_end
    conv_struct = PamConv(cb, None)
    handle = ctypes.c_void_p()
    rc = libpam.pam_start(service.encode(), user.encode(), ctypes.byref(conv_struct), ctypes.byref(handle))
    if rc != PAM_SUCCESS:
        return rc, "pam_start failed"
    rc = libpam.pam_authenticate(handle, 0)
    why = (libpam.pam_strerror(handle, rc) or b"").decode()
    libpam.pam_end(handle, rc)
    return rc, why


def main():
    authfile, user, service = parse_args(sys.argv[1:])
    if os.geteuid() != 0:
        print("run as root (sudo)", file=sys.stderr)
        return 1
    if not os.path.isfile(authfile):
        print(f"no such file: {authfile}", file=sys.stderr)
        return 1
    path = os.path.join("/etc/pam.d", service)
    if os.path.exists(path):
        print(f"{path} exists already — refusing to overwrite it", file=sys.stderr)
        return 1
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write("#%PAM-1.0\n# temporary: system/u2f-selftest.py (removed when it ends)\n")
            f.write(module_line(authfile) + "\n")
        os.chmod(path, 0o644)
        print(f"  touch the flashing YubiKey (one listed for {user} in {authfile})", flush=True)
        rc, why = authenticate(service, user)
    finally:
        if os.path.exists(path):
            os.remove(path)
    if rc == PAM_SUCCESS:
        print("  a listed YubiKey answered")
        return 0
    print(f"  no listed YubiKey answered ({why})")
    return 1


if __name__ == "__main__":
    sys.exit(main())
