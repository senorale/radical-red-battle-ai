# Locate the move and species name tables in a Gen 3 ROM by searching for consecutive names.
# Usage: python3 -I find_names.py <rom>
# Prints the table address and entry width for each table found.
import sys

rom = open(sys.argv[1], 'rb').read()


def enc(s):
    out = b''
    for c in s:
        if c == ' ': out += b'\x00'
        elif c.isupper(): out += bytes([0xBB + ord(c) - 65])
        else: out += bytes([0xD5 + ord(c) - 97])
    return out + b'\xff'


def find(first, second, index_of_first, widths):
    """Every table where `first` (entry index_of_first) is followed by `second`."""
    hits = []
    for spelled in (first, first.upper()):
        pat = enc(spelled)
        i = rom.find(pat)
        while i >= 0:
            for w in widths:
                nxt = rom[i + w:i + w + len(second) + 1]
                if nxt in (enc(second), enc(second.upper())):
                    base = 0x08000000 + i - index_of_first * w
                    refs = rom.count(base.to_bytes(4, 'little'))
                    hits.append('%08X (width %d, %d pointers to it)' % (base, w, refs))
            i = rom.find(pat, i + 1)
    return hits


# Vanilla FireRed keeps its original tables; CFRU's expanded copies are the ones the game uses.
print('moves  ', find('Pound', 'Karate Chop', 1, (13, 17)))
print('species', find('Bulbasaur', 'Ivysaur', 1, (11, 12)))
