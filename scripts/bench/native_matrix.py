#!/usr/bin/env python3
"""Serial, seeded, independent-VM comparison. No third-party Python packages."""
import argparse
import gzip
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import platform
import random
import signal
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
LABELS = ['zigler_sync', 'zigler_dirty_cpu', 'zigler_threaded', 'port_raw', 'port_etf', 'zbeam_distribution']


def percentile(values, q):
    return sorted(values)[max(0, math.ceil(len(values) * q) - 1)]


def ratio_ci(pairs, seed=20261002):
    rng = random.Random(seed)
    ratios = [a / b for a, b in pairs]
    resampled = [statistics.median(rng.choices(ratios, k=len(ratios))) for _ in range(2000)]
    return [statistics.median(ratios), percentile(resampled, .025), percentile(resampled, .975)]


def tree_rss(pid):
    """Sample live descendants, including children spawned by nonleader threads."""
    seen, pending, total = set(), [pid], 0
    while pending:
        current = pending.pop()
        if current in seen:
            continue
        seen.add(current)
        try:
            for line in Path(f'/proc/{current}/status').read_text().splitlines():
                if line.startswith('VmRSS:'):
                    total += int(line.split()[1])
            for task in Path(f'/proc/{current}/task').iterdir():
                try:
                    pending.extend(map(int, (task / 'children').read_text().split()))
                except (FileNotFoundError, ProcessLookupError):
                    pass
        except (FileNotFoundError, ProcessLookupError):
            pass
    return total


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summarize(rows):
    groups = {}
    for row in rows:
        groups.setdefault((row['job'], row['bytes'], row['label']), []).append(row)
    summary = []
    for (job, size, label), runs in sorted(groups.items()):
        record = dict(job=job, bytes=size, label=label, launches=len(runs))
        for field in ['p50_ns', 'p95_ns', 'p99_ns', 'operations_s', 'rss_idle_1s_kib', 'sampled_launch_peak_rss_kib']:
            record[field] = statistics.median(r[field] for r in runs)
        reference = groups.get((job, size, 'zbeam_distribution'))
        if reference:
            by_repeat = {r['repeat']: r for r in reference}
            for field in ['operations_s', 'p99_ns', 'rss_idle_1s_kib']:
                pairs = [(by_repeat[r['repeat']][field], r[field]) for r in runs if r['repeat'] in by_repeat]
                record[f'zbeam_over_this_{field}_median_ci95'] = ratio_ci(pairs)
        summary.append(record)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, nargs='?')
    parser.add_argument('--repeats', type=int, default=10)
    parser.add_argument('--iterations', type=int, default=1000)
    parser.add_argument('--sizes', default='32,4096,65536,1048576')
    parser.add_argument('--labels', default=','.join(LABELS))
    parser.add_argument('--jobs', default='echo,sha256')
    parser.add_argument('--workers', type=Path, default=ROOT / 'zig-out/bin')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        assert percentile([4, 1, 3, 2], .5) == 2
        assert percentile([4, 1, 3, 2], .99) == 4
        assert ratio_ci([(2, 1)] * 10) == [2, 2, 2]
        assert tree_rss(os.getpid()) > 0
        print('PASS percentile, paired resampling and real procfs sampler')
        return
    if args.output is None or args.repeats < 1 or args.iterations < 1:
        parser.error('output and positive repeats/iterations required')
    sizes = list(map(int, args.sizes.split(',')))
    labels, jobs = args.labels.split(','), args.jobs.split(',')
    if not all(1 <= s <= 1048576 for s in sizes) or not set(labels) <= set(LABELS) or not set(jobs) <= {'echo', 'sha256'}:
        parser.error('invalid workload or comparator')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    workers = args.workers.resolve()
    env = dict(os.environ, MIX_ENV='test', ERL_FLAGS='+S 2:2 +SDcpu 2 +SDio 1', ZBEAM_WORKERS=str(workers))
    binaries = [workers / name for name in ['zbeam', 'zbeam-port-echo', 'zbeam-port-etf']]
    nif = ROOT / 'benchmarks/zigler/_build/test/lib/zbeam_research/priv/lib/Elixir.ZbeamResearch.Native.so'
    source_files = [ROOT / 'build.zig', ROOT / 'benchmarks/port_etf.zig', ROOT / 'benchmarks/zigler/mix.lock',
                    *sorted((ROOT / 'src').rglob('*.zig')), *sorted((ROOT / 'benchmarks/zigler/lib').glob('*.ex')), Path(__file__)]
    manifest = dict(date=time.strftime('%Y-%m-%dT%H:%M:%S%z'), kernel=platform.platform(),
                    cpu_affinity=sorted(os.sched_getaffinity(0)), cpu_ticks_per_second=os.sysconf('SC_CLK_TCK'),
                    source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                    zig=subprocess.check_output(['zig', 'version'], text=True).strip(), options=vars(args).copy(),
                    files={str(p): sha(p) for p in binaries + [nif] + source_files},
                    rss_sampling_ms=10, warmup=100, seed=20261002,
                    caveats=['WSL2 host; not native-host replication', 'sampled launch peak includes VM startup, not an exact simultaneous HWM',
                             '1000 samples per launch gives only ten upper-1% observations; tail intervals remain exploratory',
                             'unloaded sequential workload; no universal or production performance conclusion'])
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2, default=str) + '\n')
    subprocess.run(['epmd', '-daemon'], check=True)
    cases = list(itertools.product(labels, jobs, sizes))
    skipped = [c for c in cases if c[0] == 'zigler_sync' and c[1] == 'sha256' and c[2] > 65536]
    cases = [c for c in cases if c not in skipped]
    (output / 'excluded.json').write_text(json.dumps({'cases': skipped, 'reason': 'large SHA-256 work uses dirty/threaded schedulers; synchronous eligibility not established'}) + '\n')
    rng, rows = random.Random(20261002), []
    with gzip.open(output / 'runs.jsonl.gz', 'wt') as raw:
        for repeat in range(args.repeats):
            rng.shuffle(cases)
            for index, (label, job, size) in enumerate(cases):
                log = output / f'{repeat}-{label}-{job}-{size}.log'
                command = ['elixir', '--name', f'bench_{os.getpid()}_{repeat}_{index}@127.0.0.1', '--cookie', 'research_cookie',
                           '-S', 'mix', 'run', '--no-compile', '--no-deps-check', 'run.exs', label, job, str(size), str(args.iterations)]
                with log.open('w') as stream:
                    process = subprocess.Popen(command, cwd=ROOT / 'benchmarks/zigler', env=env,
                                               stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
                    peak, deadline = 0, time.monotonic() + 180
                    try:
                        while process.poll() is None:
                            peak = max(peak, tree_rss(process.pid))
                            if time.monotonic() > deadline:
                                raise TimeoutError(f'timed out: {command}')
                            time.sleep(.01)
                    finally:
                        if process.poll() is None:
                            os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                if process.returncode:
                    raise RuntimeError(f'comparator failed ({process.returncode}): {log}')
                lines = [line[7:] for line in log.read_text().splitlines() if line.startswith('RESULT ')]
                if len(lines) != 1:
                    raise RuntimeError(f'missing or duplicate result: {log}')
                row = json.loads(lines[0])
                assert row['count'] == len(row['samples_ns']) == args.iterations
                for field, q in [('p50_ns', .5), ('p95_ns', .95), ('p99_ns', .99)]:
                    assert row[field] == percentile(row['samples_ns'], q)
                row.update(repeat=repeat, sampled_launch_peak_rss_kib=peak, command=command)
                raw.write(json.dumps(row) + '\n')
                raw.flush()
                # Raw samples already live in compressed evidence; retain diagnostics only.
                log.write_text('\n'.join(line for line in log.read_text().splitlines() if not line.startswith('RESULT ')) + '\n')
                rows.append(row)
                print(f'{repeat + 1}/{args.repeats} {label} {job} {size}: {row["p50_ns"]} ns', flush=True)
    (output / 'summary.json').write_text(json.dumps(summarize(rows), indent=2) + '\n')
    (output / 'COMPLETE').write_text(f'{len(rows)} successful launches; no skipped run counted as a pass\n')


if __name__ == '__main__':
    main()
