"""Self-checks for the Linux example launcher, independent of Zig/OTP."""
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


def live(pid):
    try:
        return ") Z " not in Path(f"/proc/{pid}/stat").read_text()
    except (FileNotFoundError, ProcessLookupError):
        return False


class WorkerGuardTest(unittest.TestCase):
    def test_owned_child_boundaries(self):
        for action in ("eof", "term", "kill", "child_exit"):
            with self.subTest(action=action):
                guard = subprocess.Popen(
                    [sys.executable, str(ROOT / "examples/worker_guard.py"),
                     sys.executable, "-c",
                     "import os,time; print(os.getpid(),flush=True); time.sleep(60)"],
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                )
                native = None
                try:
                    self.assertTrue(select.select([guard.stdout], [], [], 3)[0])
                    native = int(guard.stdout.readline())
                    self.assertGreater(native, 0)
                    if action == "eof":
                        guard.stdin.close()
                    elif action == "child_exit":
                        os.kill(native, signal.SIGKILL)
                    else:
                        guard.send_signal(signal.SIGTERM if action == "term" else signal.SIGKILL)
                    guard.wait(timeout=3)
                    deadline = time.monotonic() + 3
                    while live(native) and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertFalse(live(native))
                finally:
                    if guard.poll() is None:
                        guard.kill()
                    guard.wait(timeout=3)
                    if native and live(native):
                        try:
                            os.kill(native, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    guard.stdout.close()
                    guard.stdin.close()


if __name__ == "__main__":
    unittest.main()
