# Find Thumb BL instructions anywhere in a ROM that call a given address.
# Usage: python3 -I find_bl.py <rom> <hex target>...
# A Thumb BL is two halfwords: 0xF000 | offset_hi(11 bits), then 0xF800 | offset_lo(11 bits);
# target = pc + 4 + sign_extend(offset_hi << 12 | offset_lo << 1). Scans every halfword.
import struct, sys

rom = open(sys.argv[1], 'rb').read()
targets = {int(t, 16) & ~1 for t in sys.argv[2:]}
n = len(rom) // 2
hw = struct.unpack('<%dH' % n, rom[:n * 2])
for i in range(n - 1):
    a, b = hw[i], hw[i + 1]
    if (a & 0xF800) != 0xF000 or (b & 0xF800) != 0xF800:
        continue
    off = ((a & 0x7FF) << 12) | ((b & 0x7FF) << 1)
    if off & 0x400000:
        off -= 0x800000
    pc = 0x08000000 + i * 2
    t = pc + 4 + off
    if t in targets:
        print('%08X  bl %08X' % (pc, t))
