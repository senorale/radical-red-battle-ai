# Summarize the viewer's decisions.jsonl: how often the predictor got each move score and the choice
# right, and list the misses (move decisions) and the switch blocks.
# Usage: python3 -I check_decisions.py tools/mgba/logs/decisions.jsonl [--switches]
import json, sys

moves_total = scores_ok = choice_ok = 0
misses = []
switches = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if 'switch' in d:
        switches.append(d['switch'])
        continue
    if 'predicted' not in d:
        continue
    moves_total += 1
    bad = []
    for i, (name, act, pred) in enumerate(zip(d['moves'], d['actual'], d['predicted'])):
        if pred is None or name == '-':
            continue
        ok = act in pred if isinstance(pred, list) else act == pred
        if not ok:
            bad.append('%s %s!=%d' % (name, pred, act))
    if not bad:
        scores_ok += 1
    p_choice = d['odds'][d['choice']] if d['choice'] < 4 else 0
    if p_choice > 0:
        choice_ok += 1
    if bad or p_choice == 0:
        misses.append('frame %d %s vs %s (role %s): chose %s, model gave it %d%%; %s' % (
            d['frame'], d['ai'], d.get('target', '?'), d.get('role'), d['moves'][d['choice']] if d['choice'] < 4 else d['choice'],
            round(p_choice * 100), '; '.join(bad) or 'scores right'))
print('move decisions: %d, all scores right: %d, chosen move had odds > 0: %d' % (moves_total, scores_ok, choice_ok))
for m in misses:
    print('  ' + m)
print('switch blocks: %d' % len(switches))
if '--switches' in sys.argv:
    for sw in switches:
        print('  ' + ' | '.join(l.strip() for l in sw if 'switch-in scores' not in l and not l.startswith('    ')))
