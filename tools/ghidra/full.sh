#!/bin/zsh
# usage: full.sh [start] [end]
# Decompile every function in an address range (default: the CFRU/RR code region) into
# build/full/, then replace raw addresses with symbol names. Safe to stop and rerun: functions
# that already have an output file are skipped. Progress: tail -f tools/ghidra/build/full.log
# Results: build/full/index.tsv (addr, name, bytes, status, switches, found_by, end).
source ${0:A:h}/env.sh
start=${1:-09000000}; end=${2:-09160000}
out=$BUILD_DIR/full; log=$BUILD_DIR/full.log
export GHIDRA_HEADLESS_MAXMEM=${GHIDRA_HEADLESS_MAXMEM:-4G}
mkdir -p $out
echo "Decompiling $start-$end into $out (log: $log)"
analyze rrfull DecompileFns.java $SYMBOLS $out range $start $end 2>&1 \
	| tee -a $log | grep --line-buffered -E "SEEDS|OK |FAILED|NOFUNC|SWITCHFAIL|DONE|ERROR|Exception"
echo "Replacing addresses with symbol names"
python3 -I $GHIDRA_TOOLS_DIR/postproc.py $RADICAL_RED_ROM $SYMBOLS $out
echo "Done. $(grep -c $'\tOK\t' $out/index.tsv) OK, $(grep -c $'\tFAILED\t' $out/index.tsv) FAILED, $(grep -c $'\tNOFUNC\t' $out/index.tsv) NOFUNC (see $out/index.tsv)"
