"""Self-checks for the Linux example launcher, independent of Zig/OTP."""
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def live(pid):
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
    except (FileNotFoundError, ProcessLookupError):
        return False
    _, separator, tail = stat.rpartition(") ")
    if not separator or not tail:
        raise ValueError("invalid procfs stat record")
    return tail.split()[0] not in ("Z", "X", "x")


def wait_not_live(pid, timeout=3):
    deadline = time.monotonic() + timeout
    while live(pid):
        if time.monotonic() >= deadline:
            raise TimeoutError(f"owned child {pid} remained live")
        time.sleep(0.01)


class WorkerGuardTest(unittest.TestCase):
    def test_procfs_terminal_states_and_embedded_parentheses(self):
        for state in ("Z", "X", "x", "R", "S", "D", "T", "t", "I"):
            with self.subTest(state=state), patch.object(
                Path, "read_text", return_value=f"123 (name) Z inside) {state} 1 2 3"
            ):
                self.assertEqual(live(123), state not in ("Z", "X", "x"))
        for failure in (FileNotFoundError(), ProcessLookupError()):
            with patch.object(Path, "read_text", side_effect=failure):
                self.assertFalse(live(123))
        with patch.object(Path, "read_text", side_effect=PermissionError()):
            with self.assertRaises(PermissionError):
                live(123)
        with patch.object(Path, "read_text", return_value="invalid"):
            with self.assertRaises(ValueError):
                live(123)

    def test_terminal_observation_is_not_reprobed_and_live_child_times_out(self):
        with patch(__name__ + ".live", side_effect=[True, False, True]) as probe:
            with patch.object(time, "sleep"):
                wait_not_live(123)
            self.assertEqual(probe.call_count, 2)
        with patch(__name__ + ".live", return_value=True):
            with patch.object(time, "monotonic", side_effect=[0, 4]):
                with self.assertRaises(TimeoutError):
                    wait_not_live(123)

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
                native_done = False
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
                    wait_not_live(native)
                    native_done = True
                finally:
                    if guard.poll() is None:
                        guard.kill()
                    guard.wait(timeout=3)
                    if native and not native_done and live(native):
                        try:
                            os.kill(native, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    guard.stdout.close()
                    guard.stdin.close()


if __name__ == "__main__":
    unittest.main()
