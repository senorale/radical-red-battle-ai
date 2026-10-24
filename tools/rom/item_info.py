# Print Radical Red 4.1 items by ID from the item table at 0x093C0000 (44 bytes each; Master
# Ball id 1 at +0x2C and Leftovers id 200 confirm the stride). Fields after the name follow
# vanilla FireRed's struct Item (+0x12 hold effect, +0x13 hold effect parameter); not checked in RR code.
# Usage: python3 -I item_info.py <rom> <id>...
import sys

rom = open(sys.argv[1], 'rb').read()
BASE, SIZE = 0x093C0000, 44
CHARS = {0x00: ' ', 0xAB: '!', 0xAC: '?', 0xAD: '.', 0xAE: '-', 0xB4: "'", 0xB8: ',', 0xBA: '/'}
CHARS.update({0xA1 + i: chr(48 + i) for i in range(10)})
CHARS.update({0xBB + i: chr(65 + i) for i in range(26)})
CHARS.update({0xD5 + i: chr(97 + i) for i in range(26)})
for a in sys.argv[2:]:
    i = int(a, 0)
    o = BASE - 0x08000000 + i * SIZE
    name = ''.join(CHARS.get(c, '?') for c in rom[o:o + 14].split(b'\xff')[0])
    print('%4d  %-14s hold effect 0x%02X param %d  raw %s' % (i, name, rom[o + 0x12], rom[o + 0x13], rom[o:o + SIZE].hex(' ')[42:90]))
