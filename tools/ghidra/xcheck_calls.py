# Cross-check long-call names in a decompile against block-local "ldr rN,=fn" loads in the
# linear-sweep assembly. Usage: xcheck_calls.py <cfru_all.asm> <decompile dir> <symbols.txt>
import sys,re,csv,glob,bisect,collections
asmp,full,symp=sys.argv[1:4]
L=[]
for l in open(asmp):
    m=re.match(r'([0-9a-f]{8})\s+(\S+)\s*(.*)',l.rstrip())
    if m: L.append((int(m.group(1),16),m.group(2),m.group(3)))
targets=set()
for a,mn,op in L:
    m=re.match(r'0x([0-9a-f]{8})$',op)
    if mn.startswith('b') and m: targets.add(int(m.group(1),16))
stub={a:int(re.match(r'r(\d+)',op).group(1)) for a,mn,op in L if mn=='bx' and re.match(r'r(\d+)$',op)}
syms=collections.defaultdict(set)
for l in open(symp):
    p=l.split()
    if len(p)>=2: syms[int(p[1],16)&~1].add(p[0])
rows=[r for r in csv.reader(open(full+'/index.tsv'),delimiter='\t') if r[0]!='addr' and r[6]]
spans=sorted((int(r[0],16),int(r[6],16),r[0]) for r in rows); starts=[s[0] for s in spans]
src={}
def text(k):
    if k not in src:
        p=glob.glob(f'{full}/{k}_*.c'); src[k]=open(p[0]).read() if p else ''
    return src[k]
res=collections.Counter(); bad=[]
for i,(a,mn,op) in enumerate(L):
    m=re.match(r'0x([0-9a-f]{8})$',op)
    if mn!='bl' or not m or int(m.group(1),16) not in stub: continue
    reg='r%d'%stub[int(m.group(1),16)]
    j=bisect.bisect_right(starts,a)-1
    if j<0 or not (spans[j][0]<=a<=spans[j][1]): res['site outside decompiled functions']+=1; continue
    exp=None
    for k in range(i-1,max(i-40,-1),-1):
        b,mn2,op2=L[k]
        if mn2 in('b','bx','pop') or (mn2.startswith('b') and mn2 not in('bl','bic')): break
        if re.match(reg+r',',op2) or (mn2=='bl' and int(reg[1:])<4):
            mm=re.match(reg+r',\[0x[0-9a-f]+\]\s+;\s+\[[0-9a-f]+\]=([0-9A-F]{8})',op2)
            if mn2=='ldr' and mm: exp=int(mm.group(1),16)
            break
        if b in targets: break
    if exp is None: res['no block-local load (not checkable)']+=1; continue
    if not exp&1: res['even value (not a Thumb call)']+=1; continue
    t=exp&~1; s=text(spans[j][2])
    names=syms[t]|{'func_0x%08x'%t,'FUN_%08x'%t}
    if any(re.search(re.escape(n)+r'\s*\(',s) for n in names): res['match']+=1
    else: res['MISMATCH']+=1; bad.append((spans[j][2],'%08x'%a,sorted(names)[0]))
for k,v in res.most_common(): print(v,k)
print('mismatches by function:',collections.Counter(b[0] for b in bad).most_common(15))
