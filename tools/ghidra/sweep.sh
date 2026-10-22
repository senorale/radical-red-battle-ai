#!/bin/zsh
# usage: sweep.sh <outfile> <start> <end>
# Linear-sweep disassemble a Thumb address range.
source ${0:A:h}/env.sh
analyze rrsweep SweepAsm.java "$@" 2>&1 | grep -E "ERROR|Exception"
