import sys,re
path, sw, idxs = sys.argv[1], sys.argv[2], sys.argv[3:]
L=open(path).read().splitlines()
for idx in idxs:
    lab=f'override_jmp_{sw}_case_{idx}:'
    hits=[i for i,l in enumerate(L) if l.strip()==lab]
    if not hits: print(f'### case {idx}: label not found'); continue
    i=hits[0]; start=i
    # back up to the preceding "case 0x" line
    while start>0 and not L[start].strip().startswith('case 0x'): start-=1
    end=i+1
    while end<len(L) and not L[end].strip().startswith('case 0x') and not L[end].strip().startswith('default:'): end+=1
    print(f'### case {idx} (lines {start+1}-{end})'); print('\n'.join(L[start:end]))
