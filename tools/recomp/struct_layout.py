# Print the offset of every member of a struct as compiled, for a CFRU commit.
# Usage: python3 -I struct_layout.py <cfru repo> <commit> <gcc> <struct name> [nested member prefix]
# Example: struct_layout.py vendor/cfru 06eb6c4b .../arm-none-eabi-gcc NewBattleStruct
# Member names come from a simple parse of include/battle.h; nested structs (like ai) are listed
# with their own members when the prefix is given (e.g. "ai").
import os, re, subprocess, sys, tempfile, tarfile, io

cfru, commit, gcc, struct = sys.argv[1:5]
prefix = sys.argv[5] if len(sys.argv) > 5 else None

tmp = tempfile.mkdtemp()
arch = subprocess.run(['git', '-C', cfru, 'archive', commit, 'include', 'src/defines.h', 'src/defines_battle.h',
                       'src/config.h'], capture_output=True, check=True).stdout
tarfile.open(fileobj=io.BytesIO(arch)).extractall(tmp)
src = open(os.path.join(tmp, 'include/battle.h')).read()
body = re.search(r'struct ' + struct + r'\s*\{(.*?)\n\};', src, re.S).group(1)

# Walk the body, tracking nesting so members of a named nested struct get "outer.inner" names.
names = []
stack = []
for raw in body.split('\n'):
    line = re.sub(r'//.*', '', raw).strip()
    if not line or line.startswith('#'):
        continue
    if re.match(r'(struct|union)\b[^;]*$', line) or line == '{':
        stack.append(None)
        continue
    m = re.match(r'\}\s*(\w+)?\s*(\[[^\]]*\])*\s*;', line)
    if m:
        if stack:
            stack.pop()
        if m.group(1):
            names.append('.'.join([s for s in stack if s] + [m.group(1)]))
        continue
    for decl in line.rstrip(';').split(';'):
        m = re.search(r'(\w+)\s*(\[[^\]]*\])*\s*(:\s*\d+)?\s*$', decl.strip())
        if m and not m.group(3):
            names.append(m.group(1) if not stack else '?.' + m.group(1))

# Nested struct member names are not prefixed reliably by the simple parse above, so probe
# top-level names, plus "<prefix>.<name>" for the requested nested struct.
probe = ['#include "../defines.h"', '#include "../defines_battle.h"']
cands = []
for n in names:
    base = n.split('.')[-1]
    cands.append(base)
    if prefix:
        cands.append(prefix + '.' + base)
seen = set()
os.makedirs(os.path.join(tmp, 'src/x'), exist_ok=True)
ok = []
for c in cands:
    if c in seen:
        continue
    seen.add(c)
    test = '\n'.join(probe + ['int p = __builtin_offsetof(struct %s, %s);' % (struct, c)])
    path = os.path.join(tmp, 'src/x/p.c')
    open(path, 'w').write(test)
    r = subprocess.run([gcc, '-mthumb', '-Os', '-S', '-o', '-', path], capture_output=True, text=True)
    m = re.search(r'\.word\s+(\d+)', r.stdout)
    if m:
        ok.append((int(m.group(1)), c))
for off, c in sorted(ok):
    print('0x%04X %s' % (off, c))
