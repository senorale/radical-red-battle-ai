# Print gBattleMoves entries (RR 4.1: 0x091521D0, 12 bytes per move) for moves found by name.
# Usage: python3 -I move_info.py <rom> "Move Name" ...
# Fields shown raw: +0 effect, +1 power, +2 type, +3 accuracy, +4 pp, +5 secondary chance,
# +6..+7 target, +8 priority, +9 flags, +10 split (0 physical, 1 special, 2 status), +11 extra.
# Only +0 effect and +10 split are confirmed in RR code so far; the rest follow vanilla's order.
import sys

rom = open(sys.argv[1], 'rb').read()
MOVES, NAMES, NAME_LEN = 0x091521D0, 0x090F3188, 13
CHARS = {0x00: ' ', 0xAB: '!', 0xAC: '?', 0xAD: '.', 0xAE: '-', 0xB4: "'", 0xB8: ',', 0xBA: '/'}
CHARS.update({0xA1 + i: chr(48 + i) for i in range(10)})
CHARS.update({0xBB + i: chr(65 + i) for i in range(26)})
CHARS.update({0xD5 + i: chr(97 + i) for i in range(26)})

def name(i):
    o = NAMES - 0x08000000 + i * NAME_LEN
    out = []
    for c in rom[o:o + NAME_LEN]:
        if c == 0xFF:
            break
        out.append(CHARS.get(c, '?'))
    return ''.join(out).strip()

wanted = {n.lower() for n in sys.argv[2:]}
for i in range(1, 1000):
    n = name(i)
    if n.lower() in wanted:
        e = rom[MOVES - 0x08000000 + i * 12:MOVES - 0x08000000 + i * 12 + 12]
        print('%-13s id %3d (0x%03X)  effect 0x%02X  raw %s' % (n, i, i, e[0], e.hex(' ')))
