import sys, re, struct
cfru, rrpath, out = sys.argv[1:4]
rr = open(rrpath,'rb').read()
syms = {}
def add(name, addr, src):
    addr &= ~1
    if name not in syms: syms[name] = (addr, src)
for line in open(f'{cfru}/BPRE.ld'):
    m = re.match(r'\s*(\w+)\s*=\s*(0x[0-9A-Fa-f]+)', line)
    if m: add(m.group(1), int(m.group(2),16), 'ld')
def ptr_at(a): return struct.unpack_from('<I', rr, a & 0x1FFFFFF)[0]
for line in open(f'{cfru}/hooks'):
    p = line.split()
    if len(p) < 2 or line.startswith('#'): continue
    a = int(p[1],16) & ~1 & 0x1FFFFFF
    pad = 2 if a % 4 else 0
    if rr[a+1] & 0xF8 == 0x48 and rr[a+3] == 0x47:
        t = ptr_at(a+4+pad)
        if 0x08000000 <= t < 0x0A000000: add(p[0], t, 'hook')
for line in open(f'{cfru}/routinepointers'):
    p = line.split()
    if len(p) < 2 or line.startswith('#'): continue
    try: t = ptr_at(int(p[1],16))
    except ValueError: continue
    if 0x08000000 <= t < 0x0A000000: add(p[0], t, 'routineptr')
for line in open(f'{cfru}/repointall'):
    p = line.split()
    if len(p) < 2 or line.startswith('#'): continue
    t = ptr_at(int(p[1],16))
    if 0x08000000 <= t < 0x0A000000: add(p[0], t, 'repoint')
tbl = 0x091491E0
for i,n in {0:'AIScript_Negatives',1:'AIScript_SemiSmart',2:'AIScript_Positives',29:'AIScript_Roaming',30:'AIScript_Safari',31:'AIScript_FirstBattle'}.items():
    add(n, ptr_at(tbl+4*i), 'aitable')
add('sBattleAIScriptTable', tbl, 'aitable')
add('gDoublesDamageViabilityMapping', 0x093504B0, 'datascan')
with open(out,'w') as f:
    for n,(a,s) in sorted(syms.items(), key=lambda x:x[1][0]):
        f.write(f'{n} {a:08X} {s}\n')
print(len(syms), 'symbols')
