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

## `tools/ghidra/` (headless Ghidra)

| Script | Usage | What it does |
|---|---|---|
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
