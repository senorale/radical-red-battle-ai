# Find a type-effectiveness table in a ROM: N x N bytes (N types, attacker row, defender column)
# with only the values 0, 5, 10, 20 (x0, x0.5, x1, x2) and a few known matchups.
# Usage: python3 -I find_type_chart.py <rom> [N, default 24]
# Type IDs (RR 4.1, from gBattleMons type bytes and CFRU numbering): Normal 0, Fighting 1, Flying 2,
# Poison 3, Ground 4, Rock 5, Bug 6, Ghost 7, Steel 8, ??? 9, Fire 10, Water 11, Grass 12,
# Electric 13, Psychic 14, Ice 15, Dragon 16, Dark 17, Fairy 23.
import sys

rom = open(sys.argv[1], 'rb').read()
N = int(sys.argv[2]) if len(sys.argv) > 2 else 24
CHECKS = [(10, 12, 20), (11, 10, 20), (12, 11, 20), (0, 7, 0), (13, 4, 0), (4, 2, 0),
          (7, 0, 0), (1, 0, 20), (14, 17, 0), (10, 10, 5), (16, 23, 0), (8, 23, 20)]
ok = {0, 5, 10, 20}
size = N * N
for off in range(0, len(rom) - size):
    if any(rom[off + a * N + d] != v for a, d, v in CHECKS):
        continue
    block = rom[off:off + size]
    if all(b in ok for b in block):
        print('candidate at %08X' % (0x08000000 + off))
