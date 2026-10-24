#!/bin/zsh
# usage: run_repeat_test.sh <savestate> [runs] [seed: random|fixed] [delay step]
# Runs repeat_switch_test.lua in mGBA at uncapped speed, waits for '== done', closes mGBA and
# prints the log (tools/mgba/logs/repeat.log, overwritten each run).
here=${0:A:h}
repo=${here:h:h}
state=${1:A}
log=$here/logs/repeat.log
mkdir -p $here/logs
rm -f $log
extra=()
[[ -n $RR_TEST_EXTRA_SCRIPT ]] && extra=(--script $RR_TEST_EXTRA_SCRIPT) # e.g. the viewer, to test it with the auto-player
RR_TEST_PLAN=${RR_TEST_PLAN:-} RR_TEST_TRACE=${RR_TEST_TRACE:-} RR_TEST_DECISIONS=${RR_TEST_DECISIONS:-1} RR_TEST_STATE=$state RR_TEST_RUNS=${2:-50} RR_TEST_SEED=${3:-random} RR_TEST_DELAY_STEP=${4:-0} RR_TEST_OUT=$log \
	/Applications/mGBA.app/Contents/MacOS/mGBA -C videoSync=0 -C audioSync=0 -C fpsTarget=6000 -C mute=1 \
	$extra[@] --script $here/repeat_switch_test.lua $repo/roms/rr.gba >/dev/null 2>&1 &
pid=$!
while kill -0 $pid 2>/dev/null; do
	grep -q "== done" $log 2>/dev/null && break
	sleep 1
done
kill $pid 2>/dev/null
cat $log
