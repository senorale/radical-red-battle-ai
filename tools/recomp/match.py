# Match compiled functions against the ROM byte for byte.
# Usage: python3 -I match.py <rom> <object.o> <binutils prefix, e.g. .../bin/arm-none-eabi->
#
# Each function in the object's .text is turned into a byte pattern where relocated bytes
# (call offsets, address literals) are wildcards, then searched for in the ROM's CFRU/RR code
# region. Output, one line per function: name, size, status (MATCH addr / MULTI / NONE).
import re, subprocess, sys, tempfile, os

rom_path, obj, prefix = sys.argv[1:4]
REGION = (0x01000000, 0x01160000)  # file offsets of 0x09000000-0x09160000

rom = open(rom_path, 'rb').read()
region = rom[REGION[0]:REGION[1]]


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


with tempfile.TemporaryDirectory() as tmp:
    text_bin = os.path.join(tmp, 'text.bin')
    run(prefix + 'objcopy', '-O', 'binary', '-j', '.text', obj, text_bin)
    text = open(text_bin, 'rb').read()

funcs = []
for line in run(prefix + 'nm', '-S', '--defined-only', obj).splitlines():
    p = line.split()
    if len(p) == 4 and p[2] in ('T', 't'):
        funcs.append((int(p[0], 16) & ~1, int(p[1], 16), p[3]))

masked = set()
section = None
for line in run(prefix + 'objdump', '-r', obj).splitlines():
    m = re.match(r'RELOCATION RECORDS FOR \[(.+)\]', line)
    if m:
        section = m.group(1)
        continue
    m = re.match(r'([0-9a-f]{8})\s+(\S+)\s+(\S+)', line)
    if m and section == '.text':
        off, kind = int(m.group(1), 16), m.group(2)
        width = 2 if kind in ('R_ARM_THM_JUMP11', 'R_ARM_THM_JUMP8', 'R_ARM_THM_PC8') else 4
        masked.update(range(off, off + width))

for off, size, name in sorted(funcs):
    pat = b''.join(b'.' if off + i in masked else re.escape(text[off + i:off + i + 1]) for i in range(size))
    hits = [m.start() for m in re.finditer(pat, region, re.DOTALL)]
    if len(hits) == 1:
        status = 'MATCH %08X' % (0x09000000 + hits[0])
    elif hits:
        status = 'MULTI ' + ' '.join('%08X' % (0x09000000 + h) for h in hits[:4])
    else:
        status = 'NONE'
    print('%-40s %5d  %s' % (name, size, status))
