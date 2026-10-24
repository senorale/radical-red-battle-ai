# Check repeat_switch_test.lua results against ShouldSwitch's RR-only 25% roll
# (0x090D82CE-0x090D82DE: if Random2() % 4 == 0, return FALSE before any check runs).
# Random2 (0x0808322C): state = state * 0x41C64E6D + 0x3039, returns state >> 16.
# Usage: python3 -I check_random2.py tools/mgba/logs/repeat.log
import re, sys

agree = disagree = 0
for line in open(sys.argv[1]):
    m = re.search(r'random2_at_ShouldSwitch 0x([0-9A-F]+) checks_entered \[(.*?)\] => (\w+)', line)
    if not m:
        continue
    state = (int(m.group(1), 16) * 0x41C64E6D + 0x3039) & 0xFFFFFFFF
    predicted_skip = (state >> 16) % 4 == 0
    skipped = m.group(2) == ''
    if predicted_skip == skipped:
        agree += 1
    else:
        disagree += 1
        print('MISMATCH', line.strip())
print('runs matching the 25%% roll: %d, mismatching: %d' % (agree, disagree))
