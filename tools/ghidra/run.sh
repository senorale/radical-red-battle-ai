#!/bin/zsh
# usage: run.sh <outdir> <depth> <addr>...
# Decompile functions (and callees up to <depth>) into <outdir>. Run postproc.py on <outdir> afterwards.
source ${0:A:h}/env.sh
out=$1; depth=$2; shift 2
analyze rr DecompileFns.java $SYMBOLS $out $depth "$@" 2>&1 | grep -E "OK |NOFUNC|SWITCHFAIL|ERROR|Exception"
