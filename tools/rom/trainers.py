import sys, struct, collections
rom=open(sys.argv[1],'rb').read()
T=int(sys.argv[2],16) if len(sys.argv)>2 else 0x23EAC8
cm={0x00:' '}
for i,c in enumerate('0123456789'): cm[0xA1+i]=c
for i in range(26): cm[0xBB+i]=chr(65+i); cm[0xD5+i]=chr(97+i)
cm[0xAD]='.'; cm[0xB4]="'"; cm[0xAE]='-'; cm[0xB8]=','; cm[0xAB]='!'; cm[0xAC]='?'
def name(b):
    s=''
    for x in b:
        if x==0xFF: break
        s+=cm.get(x,'~')
    return s
c=collections.Counter(); ex=collections.defaultdict(list)
for i in range(743):
    o=T+i*0x28
    nm=name(rom[o+4:o+16]); ai=struct.unpack_from('<I',rom,o+0x1C)[0]
    c[ai]+=1
    if len(ex[ai])<6: ex[ai].append(f"{i}:{nm}")
for k,v in sorted(c.items()): print(hex(k), v, ex[k])
