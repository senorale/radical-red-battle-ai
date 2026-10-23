#!/bin/zsh
# usage: layout_probe.sh <cfru repo> <gcc> <commit>...
# Print offsetof(struct NewBattleStruct, ai.fightingStyle) for each CFRU commit, to find the
# commit whose headers give Radical Red's data layout (RR 4.1 uses 0x888).
cfru=$1; gcc=$2; shift 2
tmp=$(mktemp -d)
for c in "$@"; do
	rm -rf $tmp && mkdir -p $tmp
	git -C $cfru archive $c include src/defines.h src/defines_battle.h src/config.h | tar -x -C $tmp
	mkdir -p $tmp/src/x
	print '#include "../defines.h"\n#include "../defines_battle.h"\nint probe = __builtin_offsetof(struct NewBattleStruct, ai.fightingStyle);' > $tmp/src/x/probe.c
	v=$($gcc -mthumb -Os -S -o - $tmp/src/x/probe.c 2>/dev/null | grep -E '^\s+\.word' | head -1 | awk '{print $2}')
	print "$c $(git -C $cfru log -1 --format=%cd --date=short $c) ${v:-ERR}"
done
rm -rf $tmp
