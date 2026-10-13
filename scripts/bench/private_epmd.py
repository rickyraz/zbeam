#!/usr/bin/env python3
"""Exercise registration loss using a private foreground daemon, not the shared EPMD."""
import os
from pathlib import Path
import socket
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[2]
with socket.socket() as reservation:
    reservation.bind(('127.0.0.1', 0))
    port = reservation.getsockname()[1]


def start_epmd():
    child = subprocess.Popen(['epmd', '-address', '127.0.0.1', '-port', str(port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(100):
        if child.poll() is not None:
            raise RuntimeError('private EPMD failed to bind')
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=.1):
                return child
        except OSError:
            time.sleep(.01)
    child.terminate()
    child.wait(timeout=5)
    raise TimeoutError('private EPMD startup')


daemon = start_epmd()
vm = None
try:
    env = dict(os.environ, ERL_EPMD_PORT=str(port), ERL_FLAGS='+S 2:2 +SDcpu 2 +SDio 1')
    vm = subprocess.Popen(['elixir', '--name', f'recovery_{os.getpid()}@127.0.0.1', '--cookie', 'research_cookie',
        str(root / 'benchmarks/worker_recovery.exs'), str(root / 'zig-out/bin/zbeam-research-peer'), 'epmd', sys.argv[1] if len(sys.argv) > 1 else '10'],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in vm.stdout:
        print(line, end='', flush=True)
        if line.strip() == 'DROP_PRIVATE_EPMD':
            daemon.terminate()
            daemon.wait(timeout=5)
            daemon = start_epmd()
    if vm.wait() != 0:
        raise RuntimeError('private EPMD recovery failed')
finally:
    if vm is not None and vm.poll() is None:
        vm.terminate()
        vm.wait(timeout=5)
    if daemon.poll() is None:
        daemon.terminate()
    daemon.wait(timeout=5)
