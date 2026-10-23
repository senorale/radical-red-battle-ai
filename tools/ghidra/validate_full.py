# Validate a full decompile against a region test and the long-call cross-check.
# Usage: python3 -I validate_full.py <build dir> <full dir> <region test dir>
import csv, runpy, sys, io, contextlib, re, collections, os

B, full, region = sys.argv[1:4]


def load(p):
    return {r[0]: r for r in csv.reader(open(p + '/index.tsv'), delimiter='\t') if r[0] != 'addr'}


f = load(full)
r2 = load(region)
reg = {k: x for k, x in f.items() if 0x09060000 <= int(k, 16) < 0x090E8000}
print('functions', len(f), {s: sum(x[3] == s for x in f.values()) for s in ('OK', 'FAILED', 'NOFUNC')})
print('region test missing from full', [k for k in r2 if k not in reg][:5])
print('size diffs vs region test', [(k, r2[k][2], reg[k][2]) for k in r2 if k in reg and r2[k][2] != reg[k][2]][:5])
rows = [(int(x[0], 16), int(x[6], 16), x) for x in f.values() if x[6]]
print('span >> size', [(x[0], x[2], x[6]) for a, e, x in rows if e - a > 4 * int(x[2]) + 0x400])
print('data area entries', [(x[0], x[2]) for x in f.values() if int(x[0], 16) >= 0x090E8000])

sys.argv = ['x', B + '/cfru_all.asm', full, B + '/symbols.txt']
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    g = runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'xcheck_calls.py'))
L = g['L']
idx = {a: i for i, (a, _, _) in enumerate(L)}
c = collections.Counter()
wrong = []
for fk, site, name in g['bad']:
    st = int(re.match(r'0x([0-9a-f]{8})', L[idx[int(site, 16)]][2]).group(1), 16)
    if re.search(r'(func_0x|FUN_)%08x\s*\(' % st, g['text'](fk)):
        c['unresolved (path-dependent)'] += 1
    else:
        c['wrong or dropped'] += 1
        wrong.append((fk, site, name))
print('\n'.join(buf.getvalue().splitlines()[:4]))
print(dict(c), wrong)
