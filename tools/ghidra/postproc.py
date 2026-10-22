import sys, re, struct, glob, os
rom = open(sys.argv[1],'rb').read(); syms = {}
for line in open(sys.argv[2]):
    n, a, *_ = line.split(); syms.setdefault(int(a,16), n)
def name_for(v):
    v &= ~1
    if v in syms: return syms[v]
    best = max((a for a in syms if a <= v and v - a < 0x400 and a >= 0x02000000 and a < 0x04000000), default=None)
    return f'{syms[best]}+0x{v-best:X}' if best else None
def dat(m):
    a = int(m.group(1),16)
    if not (0x08000000 <= a < 0x0A000000): return m.group(0)
    v = struct.unpack_from('<I', rom, a & 0x1FFFFFF)[0]
    n = name_for(v)
    return f'(&{n})' if n else f'0x{v:08X}'
def fn(m):
    a = int(m.group(1),16); return syms.get(a & ~1, m.group(0))
for path in glob.glob(os.path.join(sys.argv[3], '*.c')):
    s = open(path).read()
    s = re.sub(r'_?DAT_([0-9a-fA-F]{8})', dat, s)
    s = re.sub(r'(?:func_0x|FUN_)([0-9a-fA-F]{8})', fn, s)
    open(path, 'w').write(s)
