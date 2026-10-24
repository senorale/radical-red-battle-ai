# Find a string (Gen 3 character encoding) in a ROM.
# Usage: python3 -I find_text.py <rom> "Text" ...
import sys

rom = open(sys.argv[1], 'rb').read()
enc = {' ': 0x00, '!': 0xAB, '?': 0xAC, '.': 0xAD, '-': 0xAE, "'": 0xB4, ',': 0xB8, '/': 0xBA}
enc.update({chr(48 + i): 0xA1 + i for i in range(10)})
enc.update({chr(65 + i): 0xBB + i for i in range(26)})
enc.update({chr(97 + i): 0xD5 + i for i in range(26)})
for text in sys.argv[2:]:
    pat = bytes(enc[c] for c in text) + b'\xff'
    start = 0
    hits = []
    while True:
        i = rom.find(pat, start)
        if i < 0:
            break
        hits.append('%08X' % (0x08000000 + i))
        start = i + 1
    print('%r: %s' % (text, ' '.join(hits[:20]) or 'not found'))
