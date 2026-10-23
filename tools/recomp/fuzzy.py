# Pair compiled functions with ROM functions by instruction skeleton (immediates masked), then
# report exact matches and the constants that differ.
# Usage: python3 -I fuzzy.py <rom> <object.o> <binutils prefix> <decompile index.tsv> [-v]
#
# Skeleton: every Thumb halfword of the function's code with its immediate bits cleared.
# Literal-pool words (from the object's $d mapping symbols) are compared separately.
# Output per function:
#   EXACT addr           bytes identical except relocations
#   CONST addr  diffs    same skeleton; differing immediates / literal words listed
#   NONE                 no ROM function with the same skeleton
import csv, re, subprocess, sys, tempfile, os, struct, collections, difflib

rom_path, obj, prefix, index = sys.argv[1:5]
verbose = '-v' in sys.argv
rom = open(rom_path, 'rb').read()
B = 0x08000000


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def imm_mask(h):
    """Bits of a Thumb halfword that hold immediates (cleared for the skeleton)."""
    if h < 0x1800: return 0x07C0                      # shift by imm5
    if h < 0x2000: return 0x01C0 if h & 0x0400 else 0  # add/sub imm3
    if h < 0x4000: return 0x00FF                      # mov/cmp/add/sub imm8
    if h < 0x4800: return 0
    if h < 0x5000: return 0x00FF                      # ldr pc-relative
    if h < 0x6000: return 0
    if h < 0x9000: return 0x07C0                      # ldr/str imm5
    if h < 0xB000: return 0x00FF                      # sp-relative, add pc/sp
    if h < 0xB100: return 0x007F                      # add/sub sp
    if h < 0xD000: return 0
    if h < 0xE000: return 0x00FF                      # b<cond>, swi
    return 0x07FF                                     # b, bl halves


with tempfile.TemporaryDirectory() as tmp:
    tb = os.path.join(tmp, 't.bin')
    run(prefix + 'objcopy', '-O', 'binary', '-j', '.text', obj, tb)
    text = open(tb, 'rb').read()

funcs, marks = [], []
for line in run(prefix + 'objdump', '-t', '--special-syms', obj).splitlines():
    m = re.match(r'([0-9a-f]{8}) (.{7}) (\S+)\s+([0-9a-f]{8})\s+(\S+)$', line)
    if not m or m.group(3) != '.text': continue
    addr, size, name = int(m.group(1), 16), int(m.group(4), 16), m.group(5)
    if name in ('$t', '$d'): marks.append((addr, name))
    elif 'F' in m.group(2): funcs.append((addr & ~1, size, name))
marks.sort()
relocs = set()
sec = None
for line in run(prefix + 'objdump', '-r', obj).splitlines():
    m = re.match(r'RELOCATION RECORDS FOR \[(.+)\]', line)
    if m: sec = m.group(1); continue
    m = re.match(r'([0-9a-f]{8})\s+(\S+)', line)
    if m and sec == '.text':
        w = 2 if m.group(2) in ('R_ARM_THM_JUMP11', 'R_ARM_THM_JUMP8') else 4
        relocs.update(range(int(m.group(1), 16), int(m.group(1), 16) + w))


def kind_at(off):
    k = '$t'
    for a, n in marks:
        if a > off: break
        k = n
    return k


_skel = {}


def rom_skel(a, e):
    if a not in _skel:
        hs = struct.unpack_from('<%dH' % ((e + 1 - a) // 2), rom, a - B)
        _skel[a] = [h & ~imm_mask(h) & 0xFFFF for h in hs]
    return _skel[a]


rows = [r for r in csv.reader(open(index), delimiter='\t') if r[0] != 'addr' and r[6]]
rom_funcs = [(int(r[0], 16), int(r[6], 16)) for r in rows]
by_first = collections.defaultdict(list)
for a, e in rom_funcs:
    h = struct.unpack_from('<H', rom, a - B)[0]
    by_first[h & ~imm_mask(h) & 0xFFFF].append(a)

for off, size, name in sorted(funcs):
    code = [i for i in range(off, off + size, 2) if kind_at(i) == '$t']
    data = [i for i in range(off, off + size, 4) if kind_at(i) == '$d']
    if not code: continue
    h0 = struct.unpack_from('<H', text, code[0])[0]
    best = None
    for a in by_first.get(h0 & ~imm_mask(h0) & 0xFFFF, []):
        diffs, ok = [], True
        for i in code:
            ho = struct.unpack_from('<H', text, i)[0]
            hr = struct.unpack_from('<H', rom, a - B + (i - off))[0]
            if i in relocs: continue
            mk = imm_mask(ho)
            if (ho & ~mk) != (hr & ~mk): ok = False; break
            if ho != hr: diffs.append(('ins', a + i - off, ho, hr))
        if not ok: continue
        for i in data:
            if i in relocs: continue
            wo = struct.unpack_from('<I', text, i)[0]
            wr = struct.unpack_from('<I', rom, a - B + (i - off))[0]
            if wo != wr: diffs.append(('lit', a + i - off, wo, wr))
        if best is None or len(diffs) < len(best[1]): best = (a, diffs)
    if best is None:
        # Most similar ROM function by masked-halfword sequence (literal pools included on the
        # ROM side, so ratios are approximate). Shows where the function went and how close it is.
        mine = [struct.unpack_from('<H', text, i)[0] for i in code]
        mine = [h & ~imm_mask(h) & 0xFFFF for h in mine]
        near = (0.0, None)
        for a, e in rom_funcs:
            n = (e + 1 - a) // 2
            if not (0.6 * len(mine) <= n <= 1.6 * len(mine) + 8): continue
            theirs = rom_skel(a, e)
            sm = difflib.SequenceMatcher(None, mine, theirs, autojunk=False)
            if sm.real_quick_ratio() <= near[0] or sm.quick_ratio() <= near[0]: continue
            r = sm.ratio()
            if r > near[0]: near = (r, a)
        print('%-40s %5d  NONE  nearest %s %.2f' % (name, size, '%08X' % near[1] if near[1] else '-', near[0]))
    elif not best[1]:
        print('%-40s %5d  EXACT %08X' % (name, size, best[0]))
    else:
        print('%-40s %5d  CONST %08X  %d diffs' % (name, size, best[0], len(best[1])))
        if verbose:
            for k, ad, o, r in best[1]:
                print('      %s %08X  cfru %s  rom %s' % (k, ad, hex(o), hex(r)))
