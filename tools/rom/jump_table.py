# Decode a GCC Thumb byte switch table (the bytes right after `bl 0x090003C4`, the case helper).
# Usage: python3 -I jump_table.py <rom> <table address> <entries> [first case value]
# Each entry is one byte; the target is table address + 2 * entry. Case values start at the
# given first value (the switch subtracts it before the bounds check), default 0.
import sys

rom = open(sys.argv[1], 'rb').read()
table = int(sys.argv[2], 16)
n = int(sys.argv[3])
first = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0
for i in range(n):
    b = rom[table - 0x08000000 + i]
    print('case %3d -> %08X' % (first + i, table + 2 * b))
