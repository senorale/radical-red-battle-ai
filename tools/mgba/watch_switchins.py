# Follow the viewer's decisions.jsonl and print the enemy's switch checks (every turn, both Pokemon:
# STAY or SWITCH and which checks ran) and its switch-ins: who came in and why,
# every party slot's switch-in score and flags, and RR's bench damage cache (gNewBS + 0x3F0).
# Usage: python3 -I watch_switchins.py [decisions.jsonl] [--all]
#   --all  also print the switch-ins already in the file (default: only new ones)
import json, os, sys, time

args = [a for a in sys.argv[1:] if not a.startswith('--')]
path = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'logs', 'decisions.jsonl')
KEEP = ('frame ', '  field', '  reason:', '  pick:', '  tie with', '  PREDICT:', '  MODEL:', '  EXPERIMENT:', '    ')

def show(line):
    try:
        entry = json.loads(line)
    except ValueError:
        return
    sc = entry.get('switch_check')
    if sc:
        print('frame %d  %s switch check -> %s | %s | checks: %s' % (entry['frame'], sc['ai'], sc['result'], sc['why'],
              ' > '.join(sc['checks']) or 'none'), flush=True)
        return
    if 'switch' not in entry:
        return
    for text in entry['switch']:
        if text.startswith(KEEP):
            print(text)
    print('-' * 60, flush=True)

while not os.path.exists(path):
    time.sleep(1)
f = open(path)
if '--all' in sys.argv:
    for line in f:
        show(line)
else:
    f.seek(0, os.SEEK_END)
print('watching %s for switch-ins (Ctrl-C to stop)' % path, flush=True)
while True:
    line = f.readline()
    if not line:
        time.sleep(0.5)
        # The log is replaced when cleared; reopen it from the start.
        if not os.path.exists(path) or os.path.getsize(path) < f.tell():
            while not os.path.exists(path):
                time.sleep(1)
            f = open(path)
        continue
    show(line)
