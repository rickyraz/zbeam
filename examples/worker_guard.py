#!/usr/bin/env python3
"""Linux example launcher: stdin belongs only to the controlling BEAM Port."""
import ctypes
import os
import select
import signal
import subprocess
import sys


def run(argv):
    # The native child must not inherit the pipe whose EOF detects owner/VM loss.
    parent = os.getpid()

    def child_setup():
        libc = ctypes.CDLL(None, use_errno=True)
        if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:  # PR_SET_PDEATHSIG
            raise OSError(ctypes.get_errno(), "PR_SET_PDEATHSIG")
        if os.getppid() != parent:
            os.kill(os.getpid(), signal.SIGKILL)

    child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, preexec_fn=child_setup)

    def interrupted(_signum, _frame):
        raise SystemExit(1)

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        while child.poll() is None:
            ready, _, _ = select.select([0], [], [], 0.05)
            if ready and os.read(0, 1) == b"":
                return 0
        return child.returncode
    finally:
        if child.poll() is None:
            child.kill()
        child.wait()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: worker_guard.py EXECUTABLE [ARG ...]")
    raise SystemExit(run(sys.argv[1:]))
