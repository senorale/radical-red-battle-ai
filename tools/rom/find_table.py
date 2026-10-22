import sys, struct
rom = open(sys.argv[1],'rb').read()
def ptr(v): return 0x08000001 <= v < 0x0A000000 and v & 1
for off in range(0x1000000, len(rom)-128, 4):
    w = struct.unpack_from('<32I', rom, off)
    filled = [i for i,v in enumerate(w) if v]
    if filled and filled[:3]==[0,1,2] and all(ptr(w[i]) for i in filled) and 3 <= len(filled) <= 8 and all(w[i]==0 for i in range(3,29)):
        print(f"{off+0x08000000:08X}", {i: f"{w[i]-1:08X}" for i in filled})
