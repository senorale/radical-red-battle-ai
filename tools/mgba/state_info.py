# Show which ROM an mGBA savestate belongs to, and whether it matches a given ROM.
# Usage: python3 -I state_info.py <state file> [rom]
# Raw mGBA GBA state header: 0x00 version magic, 0x08 ROM CRC32, 0x10 ROM title (12 bytes)
# and game code (4 bytes) copied from the cartridge header.
import struct, sys, zlib

state = open(sys.argv[1], 'rb').read()
magic, bios, crc = struct.unpack_from('<III', state, 0)
title = state[0x10:0x1C].rstrip(b'\0').decode('latin-1')
code = state[0x1C:0x20].decode('latin-1')
print('state  version 0x%08X  rom crc32 %08X  title %r  code %r' % (magic, crc, title, code))
if len(sys.argv) > 2:
    rom = open(sys.argv[2], 'rb').read()
    rcrc = zlib.crc32(rom) & 0xFFFFFFFF
    print('rom    crc32 %08X  title %r  code %r  -> %s' % (rcrc, rom[0xA0:0xAC].decode('latin-1'),
          rom[0xAC:0xB0].decode('latin-1'), 'MATCH' if rcrc == crc else 'DIFFERENT ROM'))
