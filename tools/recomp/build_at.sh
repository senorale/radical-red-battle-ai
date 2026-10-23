#!/bin/zsh
# usage: build_at.sh <cfru repo> <commit> <gcc> <outdir> [files relative to src/, e.g. Battle_AI/ai_util.c]
# Compile CFRU source files as of <commit> with CFRU's own flags into <outdir>/<name>.o.
# Default sources: the battle AI (src/Battle_AI/*.c).
cfru=$1; commit=$2; gcc=$3; out=${4:A}; shift 4
tree=$out/tree
rm -rf $tree && mkdir -p $tree
git -C $cfru archive $commit src include | tar -x -C $tree
files=("$@")
(( ${#files} )) || files=(${(f)"$(cd $tree/src && ls Battle_AI/*.c)"})
for f in $files; do
	n=${${f:t}%.c}
	$gcc -mthumb -mno-thumb-interwork -mcpu=arm7tdmi -mtune=arm7tdmi -mno-long-calls -march=armv4t \
		-Wall -Wextra -Os -fira-loop-pressure -fipa-pta -c $tree/src/$f -o $out/$n.o 2>$out/$n.err \
		|| print "FAILED $f (see $out/$n.err)"
done
