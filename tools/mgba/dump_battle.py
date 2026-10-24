# Print gBattleMons (0x02023BE4, 0x58 bytes per battler) from an EWRAM dump, using the
# vanilla FireRed struct BattlePokemon layout, to check the field offsets against real data.
# Usage: python3 -I dump_battle.py <ewram.bin> <rr.gba>
import struct, sys

ewram = open(sys.argv[1], 'rb').read()
rom = open(sys.argv[2], 'rb').read()
MOVE_NAMES, SPECIES_NAMES = 0x090F3188, 0x094042CC

CHARS = {0x00: ' ', 0xAB: '!', 0xAC: '?', 0xAD: '.', 0xAE: '-', 0xB4: "'", 0xB8: ',', 0xBA: '/'}
CHARS.update({0xA1 + i: chr(48 + i) for i in range(10)})
CHARS.update({0xBB + i: chr(65 + i) for i in range(26)})
CHARS.update({0xD5 + i: chr(97 + i) for i in range(26)})

def text(b):
    out = []
    for c in b:
        if c == 0xFF:
            break
        out.append(CHARS.get(c, '?'))
    return ''.join(out)

def rom_text(addr, n):
    o = addr - 0x08000000
    return text(rom[o:o + n])

def ew(addr, n):
    return ewram[addr - 0x02000000:addr - 0x02000000 + n]

for b in range(4):
    m = ew(0x02023BE4 + b * 0x58, 0x58)
    species, atk, dfn, spe, spa, spd = struct.unpack_from('<6H', m, 0)
    moves = struct.unpack_from('<4H', m, 0x0C)
    ivs = struct.unpack_from('<I', m, 0x14)[0]
    stages = list(struct.unpack_from('<8b', m, 0x18))
    ability, t1, t2, t3 = m[0x20], m[0x21], m[0x22], m[0x23]
    pp = list(m[0x24:0x28])
    hp, level, friend, maxhp, item = struct.unpack_from('<HBBHH', m, 0x28)
    nick = text(m[0x30:0x3B])
    exp, pers, status1, status2, otid = struct.unpack_from('<5I', m, 0x44)
    print('battler %d  species %d %s  nick %r  lv %d  hp %d/%d' % (
        b, species, rom_text(SPECIES_NAMES + species * 11, 11), nick, level, hp, maxhp))
    print('  stats atk %d def %d spe %d spa %d spd %d  ivs 0x%08X' % (atk, dfn, spe, spa, spd, ivs))
    print('  moves %s  pp %s' % ([rom_text(MOVE_NAMES + x * 13, 13) for x in moves], pp))
    print('  stages %s  ability %d  types %d %d %d  item %d  friend %d' % (stages, ability, t1, t2, t3, item, friend))
    print('  exp %d  personality 0x%08X  status1 0x%X  status2 0x%X  otid 0x%08X' % (exp, pers, status1, status2, otid))
