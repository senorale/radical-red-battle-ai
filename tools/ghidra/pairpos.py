import os
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
import sys,re,struct,collections
rom=open(os.environ.get('RADICAL_RED_ROM', os.path.join(REPO, 'roms/rr.gba')),'rb').read()
dec_path, src_path, base, n, out = sys.argv[1], sys.argv[2], int(sys.argv[3],16), int(sys.argv[4]), sys.argv[5]
eff={}
for l in open(os.path.join(REPO, 'vendor/cfru/include/constants/battle_move_effects.h')):
    m=re.match(r'#define (EFFECT_\w+) (\d+)',l)
    if m: eff.setdefault(int(m.group(2)),m.group(1))
tgt=collections.defaultdict(list)
for i in range(n):
    v=struct.unpack_from('<i',rom,(base&0x1FFFFFF)+4*i)[0]
    tgt[(base+v)&~1].append(i)
R=open(dec_path).read().splitlines()
starts=[]
for i,l in enumerate(R):
    m=re.match(r'\s*case 0x([0-9a-f]+):',l)
    if m and int(m.group(1),16) in tgt: starts.append((i,int(m.group(1),16)))
S=open(src_path).read().splitlines()
def src_case(name):
    idx=[i for i,l in enumerate(S) if re.match(r'\s*case '+name+r':',l)]
    if not idx: return '(no source case)'
    i=idx[0]; j=i+1
    while j<len(S) and S[j].strip().startswith('case '): j+=1
    ind=len(S[i])-len(S[i].lstrip())
    while j<len(S):
        l=S[j]; s=l.strip(); c=len(l)-len(l.lstrip())
        if s and c<=ind and (s.startswith('case ') or s.startswith('default') or s=='}'): break
        j+=1
    return '\n'.join(S[i:j])
seen=set()
with open(out,'w') as f:
    for k,(i,a) in enumerate(starts):
        if a in seen: continue
        seen.add(a)
        end=starts[k+1][0] if k+1<len(starts) else len(R)
        names=[eff.get(x,f'?{x}') for x in tgt[a]]
        if len(names)>12: names=names[:3]+[f'...({len(names)} total, default)']
        f.write(f'\n======== ROM case 0x{a:x} effects={names} (lines {i+1}-{end})\n'+'\n'.join(R[i:end])+'\n')
        for nme in names:
            if nme.startswith('EFFECT_'): f.write(f'---- SRC {nme}\n{src_case(nme)}\n')
