# Progress

Where the research stands, so a new session can pick up without re-deriving it. Last updated 2026-10-22.

## Goal

Understand how Radical Red 4.1's enemy AI chooses moves, switches and switch-ins (singles and doubles). Later, possibly change game data such as route encounters.

## Ground rules

- **Nothing is human-verified yet.** [ROM] and [CFRU] tags are code findings only. [VERIFIED] is reserved for behavior a person has tested in game (see the Tags table in `README.md`).
- **The docs in this repo are not evidence.** Re-check a claim in the ROM (decompile, then raw assembly) before relying on it, and cite the address range.
- **A Ghidra decompile is a hint, not proof.** When it matters, confirm in assembly (`tools/ghidra/asm.sh`).
- **"Learnset"** in this project means a Pokemon's current 4 moves, not its level-up learnset.
- Decompiled output and ROM-derived data stay in git-ignored `tools/ghidra/build/` and are never committed.

## Status

### Full decompile (done, 2026-10-22)

`tools/ghidra/full.sh` decompiles the CFRU/RR code region `09000000`-`09160000` into `tools/ghidra/build/full/` (index in `index.tsv`, columns: addr, name, bytes, status, switches, found_by, end). A baseline copy of this run is in `tools/ghidra/build/full-v7/`.

Result of the current run (v7):

- 2,554 functions, 0 FAILED, 0 NOFUNC, 0 SWITCHFAIL.
- All 156 switch tables inside functions are attached. The other 7 switch sites are in 7 functions with no reference anywhere in the ROM (likely dead code, not decompiled).
- Long calls through `bx rN` stubs: 42 left unresolved (probably real dynamic calls through function-pointer tables; not yet checked). 0 calls resolve into data.
- Key AI functions are whole: `AIScript_Negatives` `090C904C` (6 switches), `AIScript_Positives` `090D10D4` (4 switches), ShouldSwitch `090D824C` (ends `090D9D61`).
- One harmless junk entry: `0911FC42` (2 bytes of data that look like a call target, called by nothing).

How the validation was done (repeat it after any tooling change): compare `index.tsv` against the previous run (new/missing functions, size changes), look for functions whose `end` is far beyond their size (a sign one function absorbed another), count switch-helper call sites vs attached switches, count decompiled calls to `bx rN` stubs (unresolved) and to the data area (wrong). Test tooling changes on `09060000`-`090E8000` first and diff against the last full run before running a new full decompile.

### Findings from this round

- **Doubles role assignment** (`PredictFightingStyle` `0x090C40C4`): matches CFRU (commit `b039d662` era) except Setup Attacker needs attacks + boosting moves **exactly 3** (assembly `0x090C4574`, `cmp r6,#0x3; beq`); current CFRU uses `>= 3`. Documented in `docs/doubles/moves-and-targets.md` and `docs/ai-notes.md`.
- **Walls** in the switch-in scorer (`0x090D7168`): exists. +2 when the benched Pokemon's Defense is strictly greater than your stage-boosted Attack (if you have a physical move) and its Sp. Def strictly greater than your boosted Sp. Atk (if you have a special move). Only checked when you have no super-effective move but at least one neutral one. Assembly `0x090D78F8`-`0x090D792C` (move loop), `0x090D7AAC` (resist-all +17 branch), `0x090D7AFC`-`0x090D7B6E` (walls check). Not yet written into the docs.
- **Hardcore check** `FlagGet(0x1034)` appears in `090BD7D0` (alongside `FlagGet(0x82C)` and `FlagGet(0x1017)`); not yet investigated.

### Tooling traps found (and fixed in `DecompileFns.java`)

Each of these produced wrong decompiles before it was fixed; they explain why older outputs under `tools/ghidra/build/` (chp, dbl, ko, ...) should not be trusted:

1. `symbols.txt` names data tables too; they were decompiled as functions.
2. Functions were cut short at internal long branches depending on processing order (`AIScript_Negatives` came out at 430 lines).
3. Switches patched during another function's pass were never attached.
4. Calls to functions with setup instructions before `push`, or to leaf functions, were treated as branches, so callers absorbed callees (ShouldSwitch "returned" early).
5. Long-call targets were taken from the wrong `ldr` (`FlagGet(0x1034)` showed as `gBattleMoves(0x1034)`).

## Next steps

1. **Cross-check resolved long-call names** against raw assembly with an independent method, to measure how often a name is wrong.
2. **Doc audit:** re-check every [ROM] claim in `docs/` against the v7 decompile and assembly, record its address range, list unknowns explicitly, downgrade anything that does not hold up. Add the Walls finding above.
3. **mGBA Lua score viewer:** read the AI's per-move scores from RAM during battle so the user can watch decisions live. This is the path to [VERIFIED].
4. Later: route encounters are data tables, not code; locate RR's encounter tables when needed.

## Related

- `~/projects/rea` (REA, an MCP wrapper around Ghidra/IDA): kept for reference. It cannot decompile this ROM as is (no Thumb support for raw binaries, no in-memory fixes allowed). Its useful idea is evidence-first reporting: cite addresses, state unknowns.
