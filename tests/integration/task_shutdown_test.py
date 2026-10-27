#!/usr/bin/env python3
"""Bounded, test-owned subprocess proof that cancel/join cannot preempt a spin."""
import os
import signal
import subprocess
import sys


def check_stalled_join(executable):
    env = dict(os.environ, ZBEAM_M2_SPIN_PROBE="1")
    child = subprocess.Popen(
        [executable], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    try:
        try:
            output, _ = child.communicate(timeout=8)
        except subprocess.TimeoutExpired:
            child.kill()
            output, _ = child.communicate(timeout=2)
            assert b"M2_SPIN_ENTERED\n" in output, output.decode(errors="replace")
            assert b"M2_JOIN_WAIT\n" in output, output.decode(errors="replace")
            assert child.returncode == -signal.SIGKILL, child.returncode
            sys.stdout.buffer.write(output)
            sys.stdout.flush()
            print("PASS noncooperative task: join stalled; owned process killed/reaped")
            return
        raise AssertionError(
            f"probe returned {child.returncode}, expected blocked join:\n"
            + output.decode(errors="replace")
        )
    finally:
        if child.poll() is None:
            child.kill()
        child.wait(timeout=2)


if __name__ == "__main__":
    if not sys.platform.startswith("linux"):
        raise SystemExit("task shutdown probe requires Linux; target not verified")
    if len(sys.argv) != 2:
        raise SystemExit("usage: task_shutdown_test.py TEST_BINARY")
    check_stalled_join(sys.argv[1])
