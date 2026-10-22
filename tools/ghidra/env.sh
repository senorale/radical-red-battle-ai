#!/bin/zsh
# Shared settings for the headless Ghidra wrappers. Values come from .env when present.
GHIDRA_TOOLS_DIR=${0:A:h}
REPO_ROOT=${GHIDRA_TOOLS_DIR:h:h}
[[ -f $REPO_ROOT/.env ]] && source $REPO_ROOT/.env

RADICAL_RED_ROM=${RADICAL_RED_ROM:-$REPO_ROOT/roms/rr.gba}
GHIDRA_INSTALL_DIR=${GHIDRA_INSTALL_DIR:-/opt/homebrew/opt/ghidra/libexec}
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}

BUILD_DIR=$GHIDRA_TOOLS_DIR/build
SYMBOLS=$BUILD_DIR/symbols.txt
mkdir -p $BUILD_DIR/proj

# Fresh import each run (context register changes conflict with saved instructions).
analyze() {
	local project=$1 script=$2; shift 2
	$GHIDRA_INSTALL_DIR/support/analyzeHeadless $BUILD_DIR/proj $project \
		-import $RADICAL_RED_ROM -overwrite -loader BinaryLoader -loader-baseAddr 0x08000000 \
		-processor ARM:LE:32:v4t -noanalysis \
		-scriptPath $GHIDRA_TOOLS_DIR/scripts -postScript $script "$@"
}
