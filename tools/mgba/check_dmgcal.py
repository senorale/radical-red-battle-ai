# Compare RR's cached AI damage with rr_model's formula from a RR_TEST_DMGCAL=1 log.
# Usage: python3 -I check_dmgcal.py <file with dmgcal lines>
# Model values are capped at the defender's HP, like RR's cache (0x090DEAC4).
import re, sys

rx = re.compile(r'dmgcal (\S+)->(\S+) (.+?) cache (\d+) model (\d+) \((.*) defhp (\d+)\)')
ok = bad = 0
rows = {}
for line in open(sys.argv[1]):
    m = rx.search(line)
    if not m:
        continue
    atk, dfn, move, cache, model, info, defhp = m.groups()
    cache, model, defhp = int(cache), min(int(model), int(defhp)), int(defhp)
    if cache == model:
        ok += 1
    else:
        bad += 1
        rows[(atk, dfn, move, cache, model)] = info
for (atk, dfn, move, cache, model), info in sorted(rows.items()):
    print('%-10s -> %-10s %-13s cache %3d model %3d  ratio %.2f  (%s)' % (atk, dfn, move, cache, model, cache / model if model else 0, info))
print('match %d, mismatch %d' % (ok, bad))
