# Find the species base stats table: locate a known species' 8-byte stat/type run (HP, Atk, Def,
# Spe, SpA, SpD, type1, type2) and derive the table start for a given entry size.
# Usage: python3 -I find_base_stats.py <rom> <species id> <hp> <atk> <def> <spe> <spa> <spd> <type1> <type2>
import sys

rom = open(sys.argv[1], 'rb').read()
sid = int(sys.argv[2])
pat = bytes(int(x) for x in sys.argv[3:11])
start = 0
while True:
    i = rom.find(pat, start)
    if i < 0:
        break
    for size in (28, 32, 36):
        base = i - sid * size
        if base > 0:
            print('match at %08X; entry size %d -> table %08X' % (0x08000000 + i, size, 0x08000000 + base))
    start = i + 1
