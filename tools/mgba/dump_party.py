# Decode gPlayerParty / gEnemyParty from an EWRAM dump (Gen 3 100-byte Pokemon structs).
# Usage: python3 -I dump_party.py <ewram.bin> <rr.gba> [vanilla]
# Substructures are 12 bytes each, 48 bytes at +0x20 (G = growth, A = attacks, E = EVs/condition,
# M = misc). Radical Red stores them unencrypted in fixed order G A E M with checksum 0 (see
# rr_state.lua). Pass "vanilla" to decode FireRed's way instead: XOR with personality ^ otId,
# order by personality % 24.
import struct, sys

ewram = open(sys.argv[1], 'rb').read()
rom = open(sys.argv[2], 'rb').read()
VANILLA = len(sys.argv) > 3 and sys.argv[3] == 'vanilla'
MOVE_NAMES, SPECIES_NAMES = 0x090F3188, 0x094042CC
PARTIES = {'player': 0x02024284, 'enemy': 0x0202402C}

ORDERS = ['GAEM', 'GAME', 'GEAM', 'GEMA', 'GMAE', 'GMEA', 'AGEM', 'AGME', 'AEGM', 'AEMG', 'AMGE', 'AMEG',
          'EGAM', 'EGMA', 'EAGM', 'EAMG', 'EMGA', 'EMAG', 'MGAE', 'MGEA', 'MAGE', 'MAEG', 'MEGA', 'MEAG']

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

for side, base in PARTIES.items():
    print('==', side, hex(base))
    for slot in range(6):
        m = ew(base + slot * 100, 100)
        pers, otid = struct.unpack_from('<II', m, 0)
        if pers == 0 and otid == 0:
            continue
        key = pers ^ otid if VANILLA else 0
        words = [w ^ key for w in struct.unpack_from('<12I', m, 0x20)]
        plain = struct.pack('<12I', *words)
        checksum = struct.unpack_from('<H', m, 0x1C)[0]
        calc = sum(struct.unpack('<24H', plain)) & 0xFFFF
        sub = {k: plain[i * 12:(i + 1) * 12] for i, k in enumerate(ORDERS[pers % 24 if VANILLA else 0])}
        species, item, exp = struct.unpack_from('<HHI', sub['G'], 0)
        moves = struct.unpack_from('<4H', sub['A'], 0)
        pp = list(sub['A'][8:12])
        evs = list(sub['E'][0:6])
        ivword = struct.unpack_from('<I', sub['M'], 4)[0]
        ivs = [(ivword >> (5 * i)) & 31 for i in range(6)]
        status, level = struct.unpack_from('<IB', m, 0x50)
        hp, maxhp, atk, dfn, spe, spa, spd = struct.unpack_from('<7H', m, 0x56)
        print(' slot %d %s (%d) nick %r lv %d hp %d/%d stats %d/%d/%d/%d/%d item %d  checksum %s' % (
            slot, rom_text(SPECIES_NAMES + species * 11, 11), species, text(m[8:18]), level, hp, maxhp,
            atk, dfn, spe, spa, spd, item, 'ok' if calc == checksum else 'BAD %04X vs %04X' % (calc, checksum)))
        print('   moves %s pp %s evs %s ivs %s ivword 0x%08X status 0x%X' % (
            [rom_text(MOVE_NAMES + x * 13, 13) for x in moves], pp, evs, ivs, ivword, status))
for a in (0x02024028, 0x02024029):
    print('byte at %X = %d' % (a, ew(a, 1)[0]))
