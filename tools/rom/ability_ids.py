# Radical Red 4.1 ability IDs by name, from the ability name table at 0x090E32C0 (17 bytes each;
# Stench 1, Huge Power 37, Blaze 66, Sand Rush 124, Strong Jaw 129, Storm Drain 131 checked against
# values read in battle). Usage: python3 -I ability_ids.py <rom> ["Name" ...]   (no names: list all)
import sys

rom = open(sys.argv[1], 'rb').read()
BASE, SIZE = 0x090E32C0, 17
CHARS = {0x00: ' ', 0xAB: '!', 0xAC: '?', 0xAD: '.', 0xAE: '-', 0xB4: "'", 0xB8: ',', 0xBA: '/'}
CHARS.update({0xA1 + i: chr(48 + i) for i in range(10)})
CHARS.update({0xBB + i: chr(65 + i) for i in range(26)})
CHARS.update({0xD5 + i: chr(97 + i) for i in range(26)})
names = {}
for i in range(320):
    o = BASE - 0x08000000 + i * SIZE
    n = ''.join(CHARS.get(c, '?') for c in rom[o:o + SIZE].split(b'\xff')[0]).strip()
    names[i] = n
want = [a.lower() for a in sys.argv[2:]]
for i, n in names.items():
    if not want or n.lower() in want:
        print(i, hex(i), n)
