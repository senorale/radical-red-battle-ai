# Find 4-byte-aligned literal-pool references to given values in a ROM (e.g. RAM addresses).
# Usage: python3 -I find_refs.py <rom> <hex value>... [--compare other.gba]
# Prints each ROM address holding the value; with --compare, also whether the other ROM has the
# same word there (useful to tell vanilla FireRed code from Radical Red changes).
import struct, sys

args = sys.argv[1:]
other = None
if '--compare' in args:
    i = args.index('--compare')
    other = open(args[i + 1], 'rb').read()
    del args[i:i + 2]
rom = open(args[0], 'rb').read()
for v in args[1:]:
    val = int(v, 16)
    hits = [o for o in range(0, len(rom) - 3, 4) if struct.unpack_from('<I', rom, o)[0] == val]
    print('%08X: %d refs' % (val, len(hits)))
    for o in hits:
        note = ''
        if other is not None and o + 4 <= len(other):
            note = '  vanilla same' if struct.unpack_from('<I', other, o)[0] == val else '  vanilla differs'
        print('  %08X%s' % (0x08000000 + o, note))
