# Extract the raw GBA state from an mGBA savestate (.ss*) and optionally dump its EWRAM.
# Usage: python3 -I extract_state.py <state.ssN> <out.raw> [out_ewram.bin]
# mGBA savestates are PNG files; the raw state (0x61000 bytes, zlib-compressed) sits in a
# private chunk named 'gbAs'. In the raw state EWRAM (0x02000000) starts at offset 0x21000
# and IWRAM (0x03000000) at 0x19000 (mGBA src/gba/serialize.h layout).
import struct, sys, zlib

STATE_SIZE, EWRAM_OFF, EWRAM_SIZE = 0x61000, 0x21000, 0x40000

data = open(sys.argv[1], 'rb').read()
if data[:8] != b'\x89PNG\r\n\x1a\n':
    sys.exit('not a PNG savestate')
pos, raw = 8, None
while pos < len(data):
    length, kind = struct.unpack_from('>I4s', data, pos)
    body = data[pos + 8:pos + 8 + length]
    if kind == b'gbAs':
        raw = zlib.decompress(body)
    pos += 12 + length
if raw is None:
    sys.exit('no gbAs chunk found')
if len(raw) != STATE_SIZE:
    print('warning: raw state is 0x%X bytes, expected 0x%X' % (len(raw), STATE_SIZE))
open(sys.argv[2], 'wb').write(raw)
print('raw state 0x%X bytes, version 0x%08X, rom crc32 %08X' % ((len(raw),) + struct.unpack_from('<I4xI', raw, 0)))
if len(sys.argv) > 3:
    open(sys.argv[3], 'wb').write(raw[EWRAM_OFF:EWRAM_OFF + EWRAM_SIZE])
    print('ewram written')
