import os
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
import sys,re
rom_path, src_path, sw, offset, out = sys.argv[1:6]
offset=int(offset)
eff={}
for l in open(os.path.join(REPO, 'vendor/cfru/include/constants/battle_move_effects.h')):
    m=re.match(r'#define (EFFECT_\w+) (\d+)',l)
    if m: eff.setdefault(int(m.group(2)),m.group(1))
R=open(rom_path).read().splitlines()
lab=re.compile(rf'^override_jmp_{sw}_case_(\d+):')
starts=[(i,int(m.group(1))) for i,l in enumerate(R) for m in [lab.match(l.strip())] if m]
S=open(src_path).read().splitlines()
def src_case(name):
    idx=[i for i,l in enumerate(S) if re.match(r'\s*case '+name+r':',l)]
    if not idx: return '(no source case)'
    i=idx[0]
    # include stacked case labels before body
    j=i+1
    while j<len(S) and S[j].strip().startswith('case ') : j+=1
    ind=len(S[i])-len(S[i].lstrip())
    while j<len(S):
        l=S[j]; s=l.strip(); c=len(l)-len(l.lstrip())
        if s and c<=ind and (s.startswith('case ') or s.startswith('default') or s=='}'): break
        j+=1
    return '\n'.join(S[i:j])
with open(out,'w') as f:
    for k,(i,n) in enumerate(starts):
        end=starts[k+1][0] if k+1<len(starts) else len(R)
        e=eff.get(n+offset,f'?{n+offset}')
        f.write(f'\n======== ROM case {n} = {e} (lines {i+1}-{end})\n'+'\n'.join(R[i:end])+'\n')
        f.write(f'---- SRC {e}\n{src_case(e)}\n')
