#!/usr/bin/env python3
"""Run prebuilt variants serially in seeded order; preserve and verify raw samples."""
import argparse
import csv
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import random
import subprocess
import tempfile


def rows(text):
    return list(csv.DictReader(io.StringIO("\n".join(line for line in text.splitlines() if not line.startswith("#"))), delimiter="\t"))


def verify(summary, raw, network):
    for row in summary:
        key = row["implementation"] if network else row["cycle"]
        samples = sorted(int(sample["latency_ns"]) for sample in raw if sample["implementation" if network else "cycle"] == key)
        assert len(samples) == int(row["iterations"]), (key, len(samples), row)
        for percentile in (50, 95, 99):
            assert samples[(len(samples) * percentile + 99) // 100 - 1] == int(row[f"p{percentile}_ns"]), row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("variants", nargs="+", help="label=install-prefix (containing bin/)")
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--iterations", type=int, default=2000)
    parser.add_argument("--network-iterations", type=int, default=1000)
    parser.add_argument("--skip-network", action="store_true")
    args = parser.parse_args()
    if min(args.repeats, args.iterations, args.network_iterations) < 1:
        parser.error("counts must be positive")
    variants = dict(item.split("=", 1) for item in args.variants)
    if len(variants) != len(args.variants):
        parser.error("variant labels must be unique")
    root = Path(__file__).resolve().parents[2]
    binaries = {label: {name: str((Path(prefix) / "bin" / name).resolve()) for name in ("zbeam", "zbeam-port-echo", "zbeam-allocator-bench")} for label, prefix in variants.items()}
    hashes = {label: {name: hashlib.sha256(Path(path).read_bytes()).hexdigest() for name, path in files.items()} for label, files in binaries.items()}
    args.output.mkdir(parents=True, exist_ok=False)
    files = [root / "build.zig", root / "benchmarks/port_vs_zbeam.exs", Path(__file__).resolve(), *sorted((root / "benchmarks/memory").glob("*.zig")), *sorted((root / "src").rglob("*.zig"))]
    manifest = {"platform": platform.platform(), "cpu_count": os.cpu_count(), "affinity": sorted(os.sched_getaffinity(0)), "zig": subprocess.check_output(["zig", "version"], text=True).strip(), "base_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(), "source_sha256": {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}, "binaries": binaries, "binary_sha256": hashes, "seed": 260927, "repeats": args.repeats, "iterations": args.iterations, "network_iterations": args.network_iterations, "network": not args.skip_network}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    workloads = ("echo", "handoff") if args.skip_network else ("echo", "handoff", "network")
    jobs = [(repeat, label, workload, size) for repeat in range(1, args.repeats + 1) for label in variants for workload in workloads for size in (32, 4096, 65536)]
    random.Random(manifest["seed"]).shuffle(jobs)
    collected = {"lab": [], "network": []}
    env = dict(os.environ, ERL_FLAGS="+S 2:2")
    if not args.skip_network:
        first = next(iter(binaries.values()))
        for invalid in ("0", "1048577"):
            result = subprocess.run(["elixir", str(root / "benchmarks/port_vs_zbeam.exs"), first["zbeam"], first["zbeam-port-echo"], "1"], capture_output=True, text=True, env=dict(env, ZBEAM_BENCH_PAYLOAD_BYTES=invalid), timeout=30)
            assert result.returncode != 0 and "payload must be between" in result.stderr, result
        subprocess.run(["epmd", "-daemon"], check=True, env=env)
    with tempfile.TemporaryDirectory(prefix="zbeam-matrix-") as temp, gzip.open(args.output / "samples.tsv.gz", "wt") as sample_out, (args.output / "runs.jsonl").open("w") as run_log:
        sample_out.write("run_id\tvariant\trepeat\tworkload\tpayload_bytes\timplementation\tcycle\toperation\tlatency_ns\n")
        for run_id, (repeat, label, workload, size) in enumerate(jobs, 1):
            raw_path = Path(temp) / "raw.tsv"
            raw_path.unlink(missing_ok=True)
            network = workload == "network"
            if network:
                cmd = ["elixir", "--name", f"zbeam_matrix_{os.getpid()}_{run_id}@127.0.0.1", "--cookie", "zbeam_bench_cookie", str(root / "benchmarks/port_vs_zbeam.exs"), binaries[label]["zbeam"], binaries[label]["zbeam-port-echo"], str(args.network_iterations)]
                env.update(ZBEAM_BENCH_SAMPLES=str(raw_path), ZBEAM_BENCH_PAYLOAD_BYTES=str(size))
            else:
                cmd = [binaries[label]["zbeam-allocator-bench"], workload, str(args.iterations), str(size), str(raw_path)]
            result = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=90)
            run_log.write(json.dumps({"run_id": run_id, "variant": label, "repeat": repeat, "workload": workload, "bytes": size, "command": cmd, "exit": result.returncode, "stdout": result.stdout, "stderr": result.stderr}) + "\n")
            run_log.flush()
            result.check_returncode()
            summary, raw = rows(result.stdout), rows(raw_path.read_text())
            assert len(summary) == (2 if network else 3), result.stdout
            verify(summary, raw, network)
            for row in summary:
                collected["network" if network else "lab"].append(dict(run_id=run_id, variant=label, repeat=repeat, **row))
            for sample in raw:
                sample_out.write(f"{run_id}\t{label}\t{repeat}\t{workload}\t{size}\t{sample.get('implementation', workload)}\t{sample.get('cycle', 1)}\t{sample.get('operation', sample.get('iteration'))}\t{sample['latency_ns']}\n")
            print(f"PASS {run_id}/{len(jobs)} {label} {workload} {size} repeat={repeat}", flush=True)
    for name, data in collected.items():
        if not data:
            continue
        with (args.output / f"{name}-summary.tsv").open("w") as out:
            writer = csv.DictWriter(out, fieldnames=list(dict.fromkeys(key for row in data for key in row)), delimiter="\t", lineterminator="\n")
            writer.writeheader()
            writer.writerows(data)
    (args.output / "COMPLETE").write_text(f"{len(jobs)} runs; all recorded percentiles reproduced from raw samples\n")


if __name__ == "__main__":
    main()
