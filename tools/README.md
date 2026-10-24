# Tools

Scripts used to reverse engineer the Radical Red battle AI. Findings are in `docs/`.

## Setup

1. Put the ROMs in `roms/` (`base-fire-red.gba`, `rr.gba`), or set the paths in `.env` (see `.env.example`).
2. Clone CFRU, the engine Radical Red is built on:
   `git clone --depth 1 https://github.com/Skeli789/Complete-Fire-Red-Upgrade vendor/cfru`
3. Install Ghidra and Java: `brew install openjdk@21 ghidra`.
4. Build the symbol file (CFRU and FireRed names mapped to Radical Red addresses):
   `python3 -I tools/ghidra/make_symbols.py vendor/cfru roms/rr.gba tools/ghidra/build/symbols.txt`

Generated output goes to `tools/ghidra/build/`, which is git-ignored because it is derived from the ROM.

## `tools/rom/` (plain Python, no Ghidra)

| Script | Usage | What it does |
|---|---|---|
| `check_hooks.py` | `check_hooks.py vendor/cfru/hooks roms/base-fire-red.gba roms/rr.gba` | Lists which CFRU code hooks exist in the RR ROM and where they jump. |
| `find_table.py` | `find_table.py roms/rr.gba` | Finds the AI script table (32 function pointers). |
| `trainers.py` | `trainers.py roms/rr.gba` | Counts per-trainer AI flags in the trainer table. |
| `find_names.py` | `find_names.py roms/rr.gba` | Finds the move and species name tables and how many pointers reference each (the game uses CFRU's expanded copies, not vanilla's). |
| `find_refs.py` | `find_refs.py roms/rr.gba <hex value>... [--compare roms/base-fire-red.gba]` | Lists literal-pool words equal to a value (e.g. a RAM address), optionally marking where vanilla FireRed has the same word. |
| `find_bl.py` | `find_bl.py roms/rr.gba <hex target>...` | Lists every Thumb `bl` in the ROM that calls a given address. |
| `jump_table.py` | `jump_table.py roms/rr.gba <table> <entries> [first case] [u8\|u16\|s16]` | Decodes a GCC Thumb switch table (data after `bl 0x090003C4` / `0x090003D6` / `0x090003FC`). |
| `move_info.py` | `move_info.py roms/rr.gba "Move Name"...` | Move ID and raw `gBattleMoves` entry (effect, power, type, ...) by name. |

## `tools/mgba/` (watch the AI live)

| Script | Usage | What it does |
|---|---|---|
| `rr_ai_viewer.lua` | mGBA 0.11+ development build, Tools > Scripting > Load script | Breaks inside RR's move-choice function and prints each enemy decision: every move's final score against every target considered, ties, and the move and target chosen. In singles it prints the predictor's PREDICT block first, then ACTUAL, then a MODEL line (scores right, odds it gave the real choice), and appends every decision to `tools/mgba/logs/decisions.jsonl`. Also prints enemy switches (voluntary, forced, after a faint): the ShouldSwitch check that triggered it, why that party slot was picked, and the switch-in scores and flags of every slot. Addresses and evidence are in the script header. |
| `rr_model.lua` | `require("rr_model")` (used by the viewer and the repeat test) | Predictor (singles): from the battle state alone, predicts each enemy move's score and the odds of each move being chosen, using the rules in `docs/verified.md` and RR's own damage/strongest-move/predicted-move caches. Approximations are listed in its header. |
| `run_viewer.sh` | `tools/mgba/run_viewer.sh [rom]` | Starts `/Applications/mGBA.app` (0.11+) with the ROM and the viewer loaded (`--script`). |
| `test_viewer.lua` | `lua tools/mgba/test_viewer.lua roms/rr.gba tools/mgba/rr_ai_viewer.lua` | Offline test: fakes mGBA, reads names from the real ROM, fires the breakpoints with a made-up doubles decision. |
| `rr_state.lua` | `require("rr_state")` from the other scripts | Battle-state reader: `gBattleMons` (CFRU layout), both parties (RR stores them unencrypted), battle type, weather, side statuses. Evidence in the header. |
| `test_state.lua` | `lua tools/mgba/test_state.lua roms/rr.gba roms/states/ss2.ewram` | Offline test: runs `rr_state.lua` on EWRAM from a real savestate and prints the battle. |
| `repeat_switch_test.lua`, `run_repeat_test.sh` | `tools/mgba/run_repeat_test.sh <state> [runs=50] [random\|fixed]` | Loads a savestate N times at uncapped speed (mashes A; after your Pokemon faints, alternates RIGHT and A to send out the next one), optionally with a different `Random2` seed each run, and tallies the enemy's decisions: switch (check, slot) or stay (move and scores). Each move decision is also compared with `rr_model.lua` (`model N/4 scores`). Env options: `RR_TEST_DECISIONS=N` records N turns per run; `RR_TEST_EXTRA_SCRIPT=<lua>` loads another script too (e.g. the viewer, to test it with the auto-player); `RR_TEST_TRACE=ADDR:reg,...` logs a register each time an address runs (e.g. `090E1380:r1,090E1380:r14` for every score change and its caller). Log: `tools/mgba/logs/repeat.log`. |
| `summarize_trace.py` | `python3 -I tools/mgba/summarize_trace.py tools/mgba/logs/repeat.log` | Per-turn breakdown of a traced run: each move's score changes with the rule that made them, and the roles computed. Trace with `RR_TEST_TRACE=090C4618:r0,090C46F4:r0,090E1380:r1,090E1380:r14,090E1394:r1,090E1394:r14`. |
| `check_random2.py` | `python3 -I tools/mgba/check_random2.py tools/mgba/logs/repeat.log` | Checks each run against ShouldSwitch's RR-only 25% no-switch roll. |
| `extract_state.py` | `python3 -I tools/mgba/extract_state.py roms/rr.ss2 roms/states/ss2.raw roms/states/ss2.ewram` | Pulls the raw GBA state out of an mGBA `.ss*` (PNG chunk `gbAs`) and dumps EWRAM (raw offset `0x21000`). |
| `dump_battle.py`, `dump_party.py`, `peek.py` | `python3 -I tools/mgba/<script> roms/states/ss2.ewram ...` | Raw views of `gBattleMons`, the parties, or any EWRAM range, for checking layouts. |

Stable mGBA (0.10) has no breakpoint API, so the viewer needs a development build from https://mgba.io/downloads.html#development-downloads.

## `tools/recomp/` (byte-matching against the ROM)

Compiles CFRU source with CFRU's flags and compares the result with the ROM. Paused: GCC 10.3 and 11.3 allocate registers differently from Radical Red's build, and Radical Red's data layout matches no CFRU commit (see `progress.md`). Useful for spot checks. Toolchains go in git-ignored `vendor/toolchains/` (Arm GNU toolchains run under Rosetta).

| Script | Usage | What it does |
|---|---|---|
| `build_at.sh` | `build_at.sh vendor/cfru <commit> <gcc> <outdir> [src files]` | Compiles CFRU files as of a commit (default: `Battle_AI/*.c`). |
| `match.py` | `match.py roms/rr.gba <obj.o> <binutils prefix>` | Byte-exact search for each compiled function in the ROM, relocations as wildcards. |
| `fuzzy.py` | `fuzzy.py roms/rr.gba <obj.o> <binutils prefix> <index.tsv> [-v]` | Pairs functions by instruction skeleton (immediates masked), lists differing constants, and for unpaired functions the most similar ROM function. |
| `score.sh` | `score.sh roms/rr.gba <dir> <binutils prefix> <index.tsv>` | Runs `fuzzy.py` on every object and totals EXACT/CONST/NONE. |
| `layout_probe.sh` | `layout_probe.sh vendor/cfru <gcc> <commit>...` | Prints `offsetof(NewBattleStruct, ai.fightingStyle)` per commit (RR 4.1: `0x888`). |
| `struct_layout.py` | `struct_layout.py vendor/cfru <commit> <gcc> NewBattleStruct [ai]` | Prints every member offset of a struct at a commit. |

## `tools/ghidra/` (headless Ghidra)

| Script | Usage | What it does |
|---|---|---|
| `full.sh` | `full.sh [start] [end]` | Decompiles every function in a range (default `09000000`-`09160000`, the CFRU/RR code) into `build/full/`, runs `postproc.py`, and writes `build/full/index.tsv`. Long-running; run it in its own terminal. Safe to stop and rerun, done functions are skipped. Progress: `tail -f tools/ghidra/build/full.log`. |
| `validate_full.py` | `validate_full.py tools/ghidra/build <full dir> <region test dir>` | Checks a full decompile: missing/resized functions vs a region test, functions absorbing others, data-area entries, and long-call names via `xcheck_calls.py`. |
| `xcheck_calls.py` | `xcheck_calls.py <cfru_all.asm> <decompile dir> <symbols.txt>` | Independent check of long-call names: compares each against the block-local `ldr rN,=fn` in the assembly. |
| `run.sh` | `run.sh <outdir> <depth> <addr>...` | Decompiles functions, and their callees up to `<depth>`. |
| `postproc.py` | `postproc.py roms/rr.gba tools/ghidra/build/symbols.txt <outdir>` | Replaces raw addresses in decompiled output with symbol names. Run after `run.sh`. |
| `asm.sh` | `asm.sh <outfile> <addr>...` | Disassembles whole functions. |
| `sweep.sh` | `sweep.sh <outfile> <start> <end>` | Linear-sweep disassembly of an address range. |
| `pair2.py` | `pair2.py <negatives.c> vendor/cfru/src/Battle_AI/ai_negatives.c 090c9a8c 1 <out>` | Puts each decompiled Negatives switch case next to the matching CFRU source case. |
| `pairpos.py` | `pairpos.py <positives.c> vendor/cfru/src/Battle_AI/ai_positives.c 090d11e8 243 <out>` | Same for Positives, using the ROM jump table. |
| `case.py`, `srccase.py` | ad hoc | Print a single ROM or CFRU switch case. |

`scripts/DecompileFns.java` handles three things the default decompile gets wrong in CFRU code:

- **Long calls** (`ldr rN, =fn; bl bx_rN_stub`): adds call-override references so the real callee shows.
- **Thumb switch helpers** (`__gnu_thumb1_case_*`): patches each call to `bx r0` in Ghidra's in-memory copy and adds a jump-table override, so switch statements decompile. The ROM file is never modified.
- **Long branches inside a function** (`bl` to a label): overridden to plain branches.

Key addresses (RR 4.1): GetAIFlags `090C77B0`, AI_TrySwitchOrUseItem `090C802C`, ShouldSwitch `090D824C`, switch-in scoring `090D7168`, AIScript_Negatives `090C904C`, AIScript_Positives `090D10D4`, AI damage calc `09087080`.
