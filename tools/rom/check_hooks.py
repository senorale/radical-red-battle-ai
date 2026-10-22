import sys, struct
hooks_path, base_path, rr_path = sys.argv[1:4]
base = open(base_path,'rb').read(); rr = open(rr_path,'rb').read()
def decode(rom, off):
    off &= ~1
    a = off & 0x1FFFFFF
    pad = 2 if a % 4 else 0
    b = rom[a:a+4+pad]
    # expect ldr rX,[pc,#imm]; bx rX
    ins = b[pad:pad+4] if pad==0 else b[0:4]
    lo = rom[a:a+2]
    if lo[1] & 0xF8 == 0x48 and rom[a+3] == 0x47:
        lit = a + 4 + pad
        return struct.unpack('<I', rom[lit:lit+4])[0]
    return None
hit = miss = 0
for line in open(hooks_path):
    line=line.strip()
    if not line or line.startswith('#'): continue
    parts=line.split()
    if len(parts)<2: continue
    name, addr = parts[0], int(parts[1],16) & 0x1FFFFFF
    t = decode(rr, addr)
    changed = base[addr:addr+8] != rr[addr:addr+8]
    if t and 0x08000000 <= t < 0x0A000000: hit+=1; print(f"HOOK  {name:45s} {addr+0x08000000:08X} -> {t-1:08X}")
    else: miss+=1; print(f"----  {name:45s} {addr+0x08000000:08X} changed={changed}")
print(f"hooks matched {hit}, not matched {miss}", file=sys.stderr)
