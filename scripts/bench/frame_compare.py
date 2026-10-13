#!/usr/bin/env python3
"""Paired fresh-VM original/candidate distribution measurements using the shared NIF harness."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import sys

original = Path(sys.argv[1]).resolve()
root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=False)
variants = {'original': original / 'zig-out/bin', 'append': root / 'zig-out/bin'}
manifest = {'source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
            'binaries': {name: hashlib.sha256((path / 'zbeam').read_bytes()).hexdigest() for name, path in variants.items()},
            'cpu_affinity': sorted(os.sched_getaffinity(0)), 'seed': 1013, 'repeats': 10, 'iterations': 1000,
            'limitation': 'WSL2; same process allocator and deadlines; no native-host replication'}
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
rng = random.Random(1013)
with gzip.open(out / 'runs.jsonl.gz', 'wt') as raw:
    for repeat in range(10):
        cases = [(name, job, size) for name in variants for job in ['echo', 'sha256'] for size in [32, 65536]]
        rng.shuffle(cases)
        for index, (name, job, size) in enumerate(cases):
            env = dict(os.environ, MIX_ENV='test', ZBEAM_WORKERS=str(variants[name]), ERL_FLAGS='+S 2:2 +SDcpu 2 +SDio 1')
            command = ['elixir', '--name', f'frame_{os.getpid()}_{repeat}_{index}@127.0.0.1', '--cookie', 'research_cookie',
                       '-S', 'mix', 'run', '--no-compile', '--no-deps-check', 'run.exs', 'zbeam_distribution', job, str(size), '1000']
            run = subprocess.run(command, cwd=original / 'benchmarks/zigler', env=env, capture_output=True, text=True, timeout=60)
            diagnostics = run.stderr + '\n'.join(x for x in run.stdout.splitlines() if not x.startswith('RESULT '))
            if diagnostics:
                (out / f'{repeat}-{name}-{job}-{size}.log').write_text(diagnostics)
            if run.returncode:
                raise RuntimeError(f'failed {command}: {run.stderr}')
            results = [json.loads(x[7:]) for x in run.stdout.splitlines() if x.startswith('RESULT ')]
            assert len(results) == 1
            row = results[0]
            values = sorted(row['samples_ns'])
            assert len(values) == 1000 and row['p50_ns'] == values[499] and row['p99_ns'] == values[989]
            row.update(variant=name, repeat=repeat, command=command)
            raw.write(json.dumps(row) + '\n')
            raw.flush()
            print(repeat, name, job, size, row['p50_ns'], flush=True)
rows = [json.loads(line) for line in gzip.open(out / 'runs.jsonl.gz', 'rt')]
assert len(rows) == 80
summary = []
rng = random.Random(1013)
for job in ['echo', 'sha256']:
    for size in [32, 65536]:
        for metric in ['p50_ns', 'p99_ns', 'operations_s']:
            values = {name: {r['repeat']: r[metric] for r in rows if r['variant'] == name and r['job'] == job and r['bytes'] == size} for name in variants}
            ratios = [values['append'][i] / values['original'][i] for i in range(10)]
            boot = sorted(statistics.median(rng.choices(ratios, k=10)) for _ in range(10000))
            summary.append(dict(job=job, bytes=size, metric=metric, original=statistics.median(values['original'].values()),
                append=statistics.median(values['append'].values()), paired_ratio=statistics.median(ratios), ratio_ci95=[boot[249], boot[9749]]))
(out / 'paired-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
(out / 'COMPLETE').write_text('80 launches, 80000 exact-result samples; paired variants, no promotion claim\n')
