#!/bin/zsh
# usage: asm.sh <outfile> <addr>...
# Disassemble whole functions at the given addresses.
source ${0:A:h}/env.sh
out=$1; shift
analyze rrasm DumpAsm.java $out "$@" 2>&1 | grep -E "ERROR|Exception"
