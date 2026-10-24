# Progress

Where the research stands, so a new session can pick up without re-deriving it. Last updated 2026-10-24.

**Current task:** the live AI predictor for mGBA (not built yet). Start with `HANDOFF.md` for the user's plan, then `docs/verified.md` for the rules confirmed in game so far.

## Goal

Understand how Radical Red 4.1's enemy AI chooses moves, switches and switch-ins (singles and doubles). Later, possibly change game data such as route encounters.

## Ground rules

- **[VERIFIED] means checked in the running game.** Those rules live in `docs/verified.md`. [ROM] and [CFRU] tags are code findings only.
- **Check Radical Red's own code, not CFRU.** CFRU source is only a map for what to look for; every rule needs RR addresses (several RR changes were found this way, see below).
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

### mGBA AI viewer (working in game, 2026-10-24)

`tools/mgba/rr_ai_viewer.lua` (mGBA 0.11+ development build, breakpoint API) runs live in the user's game. It prints every enemy move decision (each move's score per target, ties, chosen move/target) and every enemy switch: voluntary (which ShouldSwitch check fired, via breakpoints on the 14 check blocks), forced or after a faint, with why that slot was picked and the switch-in scores and flags of every party slot (RR stores them in `gNewBS +0x860/+0x878`). It re-installs its breakpoints on start/reset and logs every hook hit to `tools/mgba/logs/viewer.log`. Wild Pokemon pick random moves (`OpponentHandleChooseMove` `0x09068418`) and never show.

`tools/mgba/run_repeat_test.sh` replays a savestate N times at uncapped speed with a fresh `Random2` seed per run, records several turns per run (`RR_TEST_DECISIONS`), sends out the next Pokemon after a faint, and can log any register at any address (`RR_TEST_TRACE`). `summarize_trace.py` turns a traced run into a per-turn list of score changes and the rule behind each. This is how every rule in `docs/verified.md` was confirmed.

### Matching recompilation (paused, 2026-10-23)

Tried compiling CFRU's AI source with CFRU's flags and matching it byte for byte (`tools/recomp/`). Stopped because the cost is far beyond the value for this goal:

- GCC 10.3 and 11.3 (Arm toolchains) allocate registers differently from Radical Red's build (`CalcAIAccuracy` ROM `090DB270`: `mov r1,#0xc; mov r2,r1` vs `movs r2,#12`). GCC 9.3 is downloaded in `vendor/toolchains/` but untested. RR was likely built with a specific devkitARM release.
- Radical Red's `NewBattleStruct` layout matches no CFRU commit: `ai.fightingStyle` is at `0x888` in RR (`GetBankFightingStyle` `090C46DC`), CFRU gives `0x4E0`/`0x4F4` (2021), `0x8B4` (from `06eb6c4b`, 2021-11-30), `0x8BC`, `0x8CC` (2025). RR runs a private CFRU fork.
- Where only constants differ, code generation does line up (`GetBankFightingStyle` is instruction-for-instruction identical apart from the struct offset).

### Findings so far

Verified in game (details and evidence in `docs/verified.md`): the AI picks its action at turn start before the player; the RR-only 25% no-switch roll; `Random2` is a fixed formula (same savestate, same decision); absorb switch; random move ties; the Speed-drop +3 coin (RR adds the coin); KO / slow-KO / strongest-move bonuses; roles (set from the AI's own moves, recomputed each turn); -15 for moves with no effect.

Code findings:

- **Doubles role assignment** (`PredictFightingStyle` `0x090C40C4`): matches CFRU (commit `b039d662` era) except Setup Attacker needs attacks + boosting moves **exactly 3** (assembly `0x090C4574`, `cmp r6,#0x3; beq`); current CFRU uses `>= 3`. Documented in `docs/doubles/moves-and-targets.md` and `docs/ai-notes.md`.
- **Walls** in the switch-in scorer (`0x090D7168`): exists. +2 when the benched Pokemon's Defense is strictly greater than your stage-boosted Attack (if you have a physical move) and its Sp. Def strictly greater than your boosted Sp. Atk (if you have a special move). Only checked when you have no super-effective move but at least one neutral one. Assembly `0x090D78F8`-`0x090D792C` (move loop), `0x090D7AAC` (resist-all +17 branch), `0x090D7AFC`-`0x090D7B6E` (walls check). Not yet written into the docs.
- **ShouldSwitch** `090D824C` starts with RR-only checks `FlagGet(0x1042)` and `FlagGet(0x10C0)` before CFRU's `IsTrapped`.
- **25% no-switch roll** (RR-only): after the trapped/Sky Drop checks, ShouldSwitch returns FALSE when `Random2() % 4 == 0` (assembly `0x090D82CE`-`0x090D82DE`), before any CFRU switch check runs. Repeat test on `rr.ss6` with 100 random `Random2` seeds: 77 switched (absorb), 23 stayed, all 100 matching the formula (`tools/mgba/check_random2.py`). `Random2` (state `0x020386D0`) does not advance with frames, so one savestate always gives the same decision.
- **AI flags**: every trainer battle gets `aiFlags = 7` (`0x090C77B0`, trainer bit set), whatever the trainer table says (574 trainers list `0x1`). So the switch-in scorer uses its damage-based path in singles.
- **Switch-in tie**: the scorer `0x090D7168` walks the party in order; a later equal score replaces the best on a 50% `Random2` flip, so later slots are favored. `0x090D6CB0` (called before the post-faint slot is stored) moves second best into best.
- **RR role table differs from CFRU** (`0x090C40C4`, singles, asm `0x090C4272`): one Reflect or Light Screen gives screens support; never screens sweeper in singles.
- **Role bonus tables** decoded from RR's jump tables: status moves `0x090C5CAE` (setup stats: 3 + boost, only if the player cannot 2HKO; CFRU gives 3), stat boosts `0x090C5E0E`/`0x090C6098`, slow KO `0x090C6A12` (same as CFRU).
- **Two random generators:** `Random2` (`0x0808322C`, state `0x020386D0`, the vanilla wild-encounter RNG) for most AI rolls; the "good idea to boost" check `0x090C3C64` uses the main `Random` (`0x08044EC8`, state `0x03005000`).
- **Party Pokemon are unencrypted** in fixed G A E M order (`EncryptBoxMon` `0x0803F8F8` and `GetSubstruct` `0x0803F94C` patched); `gBattleMons` uses CFRU's layout (`+0x18` = type3); `gPlayerPartyCount` is `0x02024029`.
- **Post-faint pick:** `OpponentHandleChoosePokemon` `0x09068A28` calls `0x090D6CB0` before storing the slot, which moves the scorer's second best into best.
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

1. **Predictor** (HANDOFF steps 2-5): break at the move-choice entry, compute our predicted scores and switch decision from the rules in `docs/verified.md`, print PREDICT before the viewer's ACTUAL, log both as JSON lines. Needs a damage model for the KO / 2HKO / strongest-move rules.
2. Open questions from the traces: where RR resets the role cache each turn (not `ClearCachedAIData` `0x090C8BA4`, whose only caller is the Hardcore re-pick `0x090C8F04`); why Stockpile got no +5 against Mightyena; why Hidden Power lost its +2 against a 3 HP target; whether the main `Random` advances every frame.
3. Doc audit: move the remaining [ROM]/[CFRU] claims in `docs/` onto RR addresses.
4. Later: route encounters are data tables, not code.

## Related

- `~/projects/rea` (REA, an MCP wrapper around Ghidra/IDA): kept for reference. It cannot decompile this ROM as is (no Thumb support for raw binaries, no in-memory fixes allowed). Its useful idea is evidence-first reporting: cite addresses, state unknowns.
