# Progress

Where the research stands, so a new session can pick up without re-deriving it. Last updated 2026-10-23.

## Goal

Understand how Radical Red 4.1's enemy AI chooses moves, switches and switch-ins (singles and doubles). Later, possibly change game data such as route encounters.

## Ground rules

- **Nothing is human-verified yet.** [ROM] and [CFRU] tags are code findings only. [VERIFIED] is reserved for behavior a person has tested in game (see the Tags table in `README.md`).
- **The docs in this repo are not evidence.** Re-check a claim in the ROM (decompile, then raw assembly) before relying on it, and cite the address range.
- **A Ghidra decompile is a hint, not proof.** When it matters, confirm in assembly (`tools/ghidra/asm.sh`).
- **"Learnset"** in this project means a Pokemon's current 4 moves, not its level-up learnset.
- Decompiled output and ROM-derived data stay in git-ignored `tools/ghidra/build/` and are never committed. Downloaded toolchains stay in git-ignored `vendor/toolchains/`.
- Write multi-line analysis as script files and run them as plain commands (inline scripts piped into `python3` got blocked by permission prompts).

## Status

### Full decompile (done, v8, 2026-10-23)

`tools/ghidra/full.sh` decompiles the CFRU/RR code region `09000000`-`09160000` into `tools/ghidra/build/full/` (index in `index.tsv`, columns: addr, name, bytes, status, switches, found_by, end). Baseline copy: `tools/ghidra/build/full-v8/`.

- 2,574 functions, 0 FAILED, 0 NOFUNC, 0 SWITCHFAIL.
- All 156 switch tables inside functions are attached. The other 7 switch sites are in 7 functions with no reference anywhere in the ROM (likely dead code, not decompiled).
- Long-call names: checked against the assembly by `tools/ghidra/xcheck_calls.py`, 0 wrong. Calls whose target depends on the path are left unresolved on purpose (shown as a call to the `bx rN` stub), for example the land/water wild-encounter choice in `GetLocalWildMon` `090C3630`.
- Key AI functions are whole: `AIScript_Negatives` `090C904C` (6 switches), `AIScript_Positives` `090D10D4` (4 switches), ShouldSwitch `090D824C` (ends `090D9D61`), move choice `090C82C0`.
- One harmless junk entry: `0911FC42` (2 bytes of data that look like a call target, called by nothing).

Validate after any tooling change: test on `09060000`-`090E8000` (and `09000000`-`09060000` for hook code) into `tools/ghidra/build/tests/`, diff against the last full run, then `python3 -I tools/ghidra/validate_full.py tools/ghidra/build <full dir> <region test dir>`.

### mGBA AI viewer (built, not yet run in a real game)

`tools/mgba/rr_ai_viewer.lua` needs an mGBA 0.11+ development build (breakpoint API). It breaks in the move-choice function `090C82C0` at `090C83AC` (singles scores final), `090C875C` (doubles, once per target) and `090C837A` (exit, `r0` = chosen slot) and prints each enemy decision with every move's score per target. Predictions do not touch these scores (they call the AI scripts into local arrays), so what it shows are real decisions. Tested offline with `tools/mgba/test_viewer.lua` (fake RAM, real ROM name tables). The user has not run it in game yet; switching and switch-in decisions are not covered.

### Matching recompilation (paused, 2026-10-23)

Tried compiling CFRU's AI source with CFRU's flags and matching it byte for byte (`tools/recomp/`). Stopped because the cost is far beyond the value for this goal:

- GCC 10.3 and 11.3 (Arm toolchains) allocate registers differently from Radical Red's build (`CalcAIAccuracy` ROM `090DB270`: `mov r1,#0xc; mov r2,r1` vs `movs r2,#12`). GCC 9.3 is downloaded in `vendor/toolchains/` but untested. RR was likely built with a specific devkitARM release.
- Radical Red's `NewBattleStruct` layout matches no CFRU commit: `ai.fightingStyle` is at `0x888` in RR (`GetBankFightingStyle` `090C46DC`), CFRU gives `0x4E0`/`0x4F4` (2021), `0x8B4` (from `06eb6c4b`, 2021-11-30), `0x8BC`, `0x8CC` (2025). RR runs a private CFRU fork.
- Where only constants differ, code generation does line up (`GetBankFightingStyle` is instruction-for-instruction identical apart from the struct offset).

### Findings so far (code findings, not human-verified)

- **Doubles role assignment** (`PredictFightingStyle` `0x090C40C4`): matches CFRU (commit `b039d662` era) except Setup Attacker needs attacks + boosting moves **exactly 3** (assembly `0x090C4574`, `cmp r6,#0x3; beq`); current CFRU uses `>= 3`. Documented in `docs/doubles/moves-and-targets.md` and `docs/ai-notes.md`.
- **Walls** in the switch-in scorer (`0x090D7168`): exists. +2 when the benched Pokemon's Defense is strictly greater than your stage-boosted Attack (if you have a physical move) and its Sp. Def strictly greater than your boosted Sp. Atk (if you have a special move). Only checked when you have no super-effective move but at least one neutral one. Assembly `0x090D78F8`-`0x090D792C` (move loop), `0x090D7AAC` (resist-all +17 branch), `0x090D7AFC`-`0x090D7B6E` (walls check). Not yet written into the docs.
- **ShouldSwitch** `090D824C` starts with RR-only checks `FlagGet(0x1042)` and `FlagGet(0x10C0)` before CFRU's `IsTrapped`.
- **Hardcore check** `FlagGet(0x1034)` appears in `090BD7D0` (alongside `FlagGet(0x82C)` and `FlagGet(0x1017)`); not yet investigated.
- **Name tables** used by the game: moves `090F3188` (13 bytes each), species `094042CC` (11 bytes each); the vanilla tables are unreferenced (`tools/rom/find_names.py`).

### Tooling traps found (and fixed in `DecompileFns.java`)

Each of these produced wrong decompiles before it was fixed; they explain why older outputs under `tools/ghidra/build/` (chp, dbl, ko, ...) should not be trusted:

1. `symbols.txt` names data tables too; they were decompiled as functions.
2. Functions were cut short at internal long branches depending on processing order (`AIScript_Negatives` came out at 430 lines).
3. Switches patched during another function's pass were never attached.
4. Calls to functions with setup instructions before `push`, to leaf functions, or to hook thunks ending in `ldr rN,=fn; bx rN` were treated as branches, so callers absorbed callees (ShouldSwitch "returned" early).
5. Long-call targets were taken from the wrong `ldr` (`FlagGet(0x1034)` showed as `gBattleMoves(0x1034)`), or from one path when the target depends on the path.

## Next steps

1. **User:** install an mGBA development build and run `tools/mgba/rr_ai_viewer.lua` in a battle; compare what it shows with the docs. This is the path to [VERIFIED].
2. **Doc audit:** re-check every [ROM] claim in `docs/` against the v8 decompile and assembly, record its address range, list unknowns explicitly, downgrade anything that does not hold up. Add the Walls and ShouldSwitch findings above.
3. Viewer extensions if wanted: ShouldSwitch decisions and post-KO switch-in scores.
4. Later: route encounters are data tables, not code; locate RR's encounter tables when needed.

## Related

- `~/projects/rea` (REA, an MCP wrapper around Ghidra/IDA): kept for reference. It cannot decompile this ROM as is (no Thumb support for raw binaries, no in-memory fixes allowed). Its useful idea is evidence-first reporting: cite addresses, state unknowns.
