# Hex-dump bytes from an EWRAM dump (0x02000000 base).
# Usage: python3 -I peek.py <ewram.bin> <hex addr> [hex length, default 0x20] ...more addr/len pairs
import sys

ewram = open(sys.argv[1], 'rb').read()
args = sys.argv[2:]
for i in range(0, len(args), 2):
    addr = int(args[i], 16)
    n = int(args[i + 1], 16) if i + 1 < len(args) else 0x20
    data = ewram[addr - 0x02000000:addr - 0x02000000 + n]
    for o in range(0, len(data), 16):
        print('%08X  %s' % (addr + o, ' '.join('%02X' % b for b in data[o:o + 16])))
