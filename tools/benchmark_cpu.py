#!/usr/bin/env python3
"""Alternate two existing native benchmark binaries; never opens guest disks."""
import argparse
import json
import platform
import re
import statistics
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('baseline', type=Path)
parser.add_argument('optimized', type=Path)
parser.add_argument('--runs', type=int, default=7)
args = parser.parse_args()
if args.runs < 3:
    parser.error('use at least three runs')
results = {'host': platform.platform(), 'machine': platform.machine(), 'runs': args.runs,
           'scope': 'single-vCPU synthetic code; not Roblox or a 4/6-vCPU VM', 'samples': []}
pattern = re.compile(r'(bench_\w+)\s+native\s+([\d.]+) ms\s+jit\s+([\d.]+) ms')
for run in range(args.runs):
    order = [('baseline', args.baseline), ('optimized', args.optimized)]
    if run % 2:
        order.reverse()
    for label, binary in order:
        out = subprocess.check_output([str(binary.resolve())], text=True)
        matches = pattern.findall(out)
        if len(matches) != 4 or 'WRONG RESULT' in out:
            raise RuntimeError('benchmark failed or returned an unexpected format: ' + out)
        for name, native, jit in matches:
            results['samples'].append(dict(run=run, build=label, benchmark=name,
                                          native_ms=float(native), jit_ms=float(jit)))
results['medians'] = {}
for name in sorted({s['benchmark'] for s in results['samples']}):
    results['medians'][name] = {
        label: {field: statistics.median(s[field] for s in results['samples']
                                        if s['build'] == label and s['benchmark'] == name)
                for field in ('native_ms', 'jit_ms')}
        for label in ('baseline', 'optimized')}
print(json.dumps(results, indent=2))
