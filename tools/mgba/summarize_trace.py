# Summarize a multi-turn repeat test traced with the score helpers, one block per enemy decision.
# Usage: python3 -I summarize_trace.py tools/mgba/logs/repeat.log
# Expects the run made with
#   RR_TEST_TRACE=090C4618:r0,090C46F4:r0,090E1380:r1,090E1380:r14,090E1394:r1,090E1394:r14
# 0x090E1380 adds r1 to a move's score, 0x090E1394 subtracts r1; r14 is the caller (return address).
# 0x090C46F4 stores the role just computed (r0). Entries with no move name or script 3 come from the
# AI's move prediction pass, not the real choice, and are left out of the score lines.
import re, sys

# Known callers (return addresses) of the score helpers, from the RR 4.1 traces.
CALLERS = {
    0x090CA2E9: 'Negatives shared -10 (healing at full HP, useless move, ...)',
    0x090CB83D: 'Negatives -9',
    0x090C911F: 'Negatives',
    0x090C5CF9: 'status move bonus by role (IncreaseStatusViability)',
    0x090C6A31: 'slow KO bonus by role (KOs but goes second)',
    0x090D67AB: 'strongest move / KO bonus (Positives)',
    0x090D2A6B: 'Speed-drop side effect (50% coin)',
    0x090CB2FD: 'Negatives -15: move has no effect on you (immune)',
    0x090CB111: 'Negatives -9: healing at 90-99% HP',
    0x090C5F2B: 'stat-boosting move bonus by role',
}
ROLES = {0: 'none', 1: 'pure attacker (sweeper kill)', 2: 'setup stats sweeper', 3: 'setup status sweeper',
         4: 'setup screens sweeper', 5: 'stall', 6: 'Baton Pass support', 7: 'cleric', 8: 'screens support',
         9: 'phazing support', 10: 'entry hazards'}

for line in open(sys.argv[1]):
    if not line.startswith('run'):
        continue
    turns = re.findall(r'\[turn (\d+): (.*?)\](?= \[turn|  scores|$|\s)', line)
    final_scores = re.search(r'\]  scores: (.*?)  trace:', line)
    trace = line.split('trace: ', 1)[1] if 'trace: ' in line else ''
    segs = trace.split('| end of turn')
    print(line.split(' delay')[0])
    for i, seg in enumerate(segs):
        head = turns[i][1] if i < len(turns) else '(no decision recorded)'
        print('\n== turn %d: %s' % (i + 1, head))
        if i == len(turns) - 1 and final_scores and 'scores:' not in head:
            print('   final scores: ' + final_scores.group(1))
        entries = [e.strip() for e in seg.split(';') if e.strip()]
        roles = []
        last_battler = None
        pending = {}
        for e in entries:
            m = re.match(r'(\w+) (r\d+)=(\w+) \((.*), script (\d+)\)', e)
            if not m:
                continue
            addr, reg, val, move, script = m.groups()
            if addr == '090C4618':
                last_battler = int(val)
            elif addr == '090C46F4':
                roles.append('battler %s: %s' % (last_battler, ROLES.get(int(val), val)))
            elif addr in ('090E1380', '090E1394'):
                key = (addr, move, script)
                pending.setdefault(key, {})[reg] = val
                if len(pending[key]) == 2:
                    d = pending.pop(key)
                    if move == '-' or script == '3':
                        continue
                    sign = '+' if addr == '090E1380' else '-'
                    caller = int(d['r14'], 16)
                    print('   %-13s %s%-3s %s' % (move, sign, d['r1'], CALLERS.get(caller, 'caller %08X' % caller)))
        if roles:
            print('   roles computed: ' + '; '.join(dict.fromkeys(roles)))
