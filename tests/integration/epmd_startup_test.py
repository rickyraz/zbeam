"""Bounded launcher readiness; no shared EPMD or native retry contract changes."""
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import unittest


HELPER = Path(__file__).resolve().parents[2] / "scripts/interop/ensure_epmd.sh"
REAL_EPMD = shutil.which("epmd")


class EpmdStartupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        stub = self.path / "epmd"
        stub.write_text('''#!/bin/sh
set -eu
case "$1" in
    -daemon)
        [ "$MODE" != fail ] || exit 23
        : > "$TEST_DIR/started"
        ;;
    -names)
        : > "$TEST_DIR/probed"
        case "$MODE" in
            real) exec "$REAL_EPMD" -port "$PRIVATE_PORT" -names ;;
            hang) exec sleep 30 ;;
            stubborn) trap '' TERM; exec sleep 30 ;;
            *) [ -f "$TEST_DIR/ready" ] ;;
        esac
        ;;
    *) exit 24 ;;
esac
''')
        stub.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.path}:{os.environ['PATH']}",
                        TEST_DIR=str(self.path), MODE="delayed")

    def start(self):
        process = subprocess.Popen(["sh", str(HELPER)], env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(self.finish, process)
        return process

    def finish(self, process):
        # The helper's outer timeout also bounds a hung epmd probe and its children.
        if process.poll() is None:
            process.communicate(timeout=8)

    def wait_for_probe(self, process):
        deadline = time.monotonic() + 2
        while not (self.path / "probed").exists():
            self.assertIsNone(process.poll(), "launcher returned before a readiness probe")
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.01)
        self.assertIsNone(process.poll())

    def test_waits_for_delayed_readiness(self):
        process = self.start()
        self.wait_for_probe(process)
        (self.path / "ready").touch()
        process.communicate(timeout=8)
        self.assertEqual(process.returncode, 0)
        self.assertTrue((self.path / "started").exists())

    def test_existing_ready_daemon(self):
        (self.path / "ready").touch()
        process = self.start()
        process.communicate(timeout=8)
        self.assertEqual(process.returncode, 0)
        self.assertTrue((self.path / "probed").exists())

    def test_start_failure_propagates(self):
        self.env["MODE"] = "fail"
        process = self.start()
        _, error = process.communicate(timeout=8)
        self.assertEqual(process.returncode, 23)
        self.assertIn(b"FAIL EPMD startup/readiness", error)
        self.assertFalse((self.path / "probed").exists())

    def test_failed_and_hanging_probes_are_bounded(self):
        for mode in ("never", "hang", "stubborn"):
            with self.subTest(mode=mode):
                self.env["MODE"] = mode
                process = self.start()
                _, error = process.communicate(timeout=8)
                self.assertEqual(process.returncode, 137)
                self.assertIn(b"FAIL EPMD startup/readiness", error)

    @unittest.skipUnless(REAL_EPMD, "real EPMD unavailable; stub regressions still run")
    def test_real_private_epmd_starts_after_first_probe(self):
        # Reserve a non-listening port: a native TCP connect demonstrably refuses.
        reservation = socket.socket()
        self.addCleanup(reservation.close)
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
        with self.assertRaises(ConnectionRefusedError):
            socket.create_connection(("127.0.0.1", port), timeout=1)
        self.env.update(MODE="real", REAL_EPMD=REAL_EPMD, PRIVATE_PORT=str(port))
        process = self.start()
        self.wait_for_probe(process)
        reservation.close()
        daemon = subprocess.Popen([REAL_EPMD, "-port", str(port), "-address", "127.0.0.1"],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            process.communicate(timeout=8)
            self.assertEqual(process.returncode, 0)
            self.assertIsNone(daemon.poll())
        finally:
            daemon.terminate()
            daemon.wait(timeout=3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
