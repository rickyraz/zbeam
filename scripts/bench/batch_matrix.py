#!/usr/bin/env python3
"""Serial, seeded, fresh-VM controls for preformed independent-job batches."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=False)
repeats = 10
iterations = 1000
cases = [(label, count, size) for label in ['nif_dirty', 'port_raw', 'port_etf', 'zbeam']
         for count in [1, 8, 32] for size in [32, 4096, 32768]]
files = [root / 'zig-out/bin/zbeam', root / 'zig-out/bin/zbeam-batch-port', root / 'benchmarks/zigler/mix.lock']
files += list((root / 'benchmarks/zigler/priv').glob('*.so'))
manifest = dict(source=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                seed=1013, repeats=repeats, iterations=iterations, cpu_affinity=sorted(os.sched_getaffinity(0)),
                hashes={str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
                limitations=['WSL2, unloaded BEAM', 'preformed jobs; fill wait excluded', 'no threaded NIF scoring',
                             'NIF uses prepacked equal-size jobs; raw Port packing and ETF serialization remain timed'])
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
rng = random.Random(1013)
rows = []
with gzip.open(out / 'runs.jsonl.gz', 'wt') as raw:
    for repeat in range(repeats):
        rng.shuffle(cases)
        for index, (label, count, size) in enumerate(cases):
            command = ['elixir', '--name', f'batchvm_{os.getpid()}_{repeat}_{index}@127.0.0.1', '--cookie', 'research_cookie',
                       '-S', 'mix', 'run', '--no-compile', '--no-deps-check', 'batch_run.exs', label, str(count), str(size), str(iterations)]
            env = dict(os.environ, MIX_ENV='test', ZBEAM_WORKERS=str(root / 'zig-out/bin'), ERL_FLAGS='+S 2:2 +SDcpu 2 +SDio 1')
            run = subprocess.run(command, cwd=root / 'benchmarks/zigler', env=env, text=True, capture_output=True, timeout=60)
            diagnostics = run.stderr + '\n'.join(x for x in run.stdout.splitlines() if not x.startswith('RESULT '))
            if diagnostics:
                (out / f'{repeat}-{label}-{count}-{size}.log').write_text(diagnostics)
            if run.returncode:
                raise RuntimeError(f'{command}: {diagnostics}')
            result = [json.loads(x[7:]) for x in run.stdout.splitlines() if x.startswith('RESULT ')]
            assert len(result) == 1
            row = result[0]
            values = sorted(row['samples_ns'])
            assert len(values) == iterations and values[499] == row['batch_p50_ns'] and values[989] == row['batch_p99_ns']
            row['repeat'] = repeat
            rows.append(row)
            raw.write(json.dumps(row) + '\n')
            raw.flush()
            print(repeat, label, count, size, row['jobs_s'], flush=True)
summary = []
for label, count, size in sorted(cases):
    selected = [r for r in rows if (r['label'], r['jobs_per_batch'], r['bytes_per_job']) == (label, count, size)]
    assert len(selected) == repeats
    summary.append(dict(label=label, count=count, bytes=size, **{metric: statistics.median(r[metric] for r in selected)
        for metric in ['jobs_s', 'batch_p50_ns', 'batch_p99_ns']}))
(out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
ratios = []
rng = random.Random(1013)
for label in ['nif_dirty', 'port_raw', 'port_etf']:
    for count in [1, 8, 32]:
        for size in [32, 4096, 32768]:
            for metric in ['jobs_s', 'batch_p99_ns']:
                groups = {name: {r['repeat']: r[metric] for r in rows if r['label'] == name and r['jobs_per_batch'] == count and r['bytes_per_job'] == size} for name in [label, 'zbeam']}
                values = [groups['zbeam'][i] / groups[label][i] for i in range(repeats)]
                boot = sorted(statistics.median(rng.choices(values, k=repeats)) for _ in range(10000))
                ratios.append(dict(control=label, count=count, bytes=size, metric=metric, zbeam_ratio=statistics.median(values), ci95=[boot[249], boot[9749]]))
(out / 'paired-ratios.json').write_text(json.dumps(ratios, indent=2) + '\n')
(out / 'COMPLETE').write_text(f'{len(rows)} launches; {len(rows)*iterations} exact-result batches; no promotion claim\n')
