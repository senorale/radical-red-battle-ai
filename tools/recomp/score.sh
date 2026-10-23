#!/bin/zsh
# usage: score.sh <rom> <build dir with .o files> <binutils prefix> <decompile index.tsv>
# Run fuzzy.py on every object; write <dir>/<name>.fuzzy and print EXACT/CONST/NONE counts
# (functions and bytes) per object and in total.
rom=$1; dir=$2; prefix=$3; index=$4
here=${0:A:h}
for o in $dir/*.o; do
	python3 -I $here/fuzzy.py $rom $o $prefix $index -v > ${o%.o}.fuzzy
done
awk 'FNR==1{f=FILENAME; sub(/.*\//,"",f)} $3 ~ /^(EXACT|CONST|NONE)$/ {n[f" "$3]++; b[f" "$3]+=$2; t[$3]++; tb[$3]+=$2}
	END {for (k in n) printf "%-28s %4d fns %7d bytes\n", k, n[k], b[k];
	     for (k in t) printf "TOTAL %-6s %4d fns %7d bytes\n", k, t[k], tb[k]}' $dir/*.fuzzy | sort
