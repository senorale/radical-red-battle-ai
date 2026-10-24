# List aligned u32 values in a file that fall in a range (for locating counters in raw states).
# Usage: python3 -I find_u32.py <file> <min> <max> [max offset, hex]
import struct, sys

data = open(sys.argv[1], 'rb').read()
lo, hi = int(sys.argv[2]), int(sys.argv[3])
end = int(sys.argv[4], 16) if len(sys.argv) > 4 else len(data)
for off in range(0, min(end, len(data)) - 3, 4):
    v = struct.unpack_from('<I', data, off)[0]
    if lo <= v <= hi:
        print('0x%05X  %d' % (off, v))
