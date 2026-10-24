# Decode a GCC Thumb switch table (the data right after a `bl` to a case helper).
# Usage: python3 -I jump_table.py <rom> <table address> <entries> [first case value] [u8|u16|s16]
# Case helpers in RR 4.1: 0x090003C4 u8 entries, 0x090003D6 u16 entries, 0x090003FC s16 entries.
# The target is table address + 2 * entry. Case values start at the given first value (the switch
# subtracts it before the bounds check), default 0.
import struct, sys

rom = open(sys.argv[1], 'rb').read()
table = int(sys.argv[2], 16)
n = int(sys.argv[3])
first = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0
kind = sys.argv[5] if len(sys.argv) > 5 else 'u8'
o = table - 0x08000000
for i in range(n):
    if kind == 'u8':
        e = rom[o + i]
    elif kind == 'u16':
        e = struct.unpack_from('<H', rom, o + 2 * i)[0]
    else:
        e = struct.unpack_from('<h', rom, o + 2 * i)[0]
    print('case %3d -> %08X' % (first + i, table + 2 * e))
