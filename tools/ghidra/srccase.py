import sys,re
src=open(sys.argv[1]).read().splitlines()
for name in sys.argv[2:]:
    idx=[i for i,l in enumerate(src) if re.match(r'\s*case '+name+r':',l)]
    for i in idx[:1]:
        depth_line=src[i]; ind=len(depth_line)-len(depth_line.lstrip())
        j=i+1
        while j<len(src):
            l=src[j]; s=l.strip(); cur=len(l)-len(l.lstrip())
            if s and cur<=ind and (s.startswith('case ') or s.startswith('default') or s=='}'):
                # stop at next case of same level unless it's a fallthrough stack
                if s.startswith('case ') and j==i+1: j+=1; continue
                break
            j+=1
        print(f'### SRC {name} ({i+1}-{j})'); print('\n'.join(src[i:j]))
