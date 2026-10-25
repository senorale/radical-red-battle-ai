# Handoff: live AI predictor for Radical Red 4.1

For a new Claude session. Read this, then `progress.md` (overall state) and `docs/verified.md` (the rules confirmed in game), then continue. Written 2026-10-24.

## What the user is doing and how to help

The user plays Radical Red 4.1 in mGBA with the viewer script loaded. For every enemy decision the viewer shows what our model predicted (PREDICT), what the AI actually computed (ACTUAL) and how close the model was (MODEL), and writes it all to `tools/mgba/logs/decisions.jsonl`. When the user says "check the logs", analyze that file, find where the prediction missed, locate the rule in **Radical Red's own code**, fix `tools/mgba/rr_model.lua`, verify, commit, and relaunch their session when they are ready.

The user's rules (also in memory files):

- **Learn from live play.** Improvements come from the user's own battles (prediction vs what happened). Do not use the old `rr.ss6` test battle as the default test anymore; it was only a starting point.
- **Check RR's code, not CFRU.** CFRU source (`vendor/cfru`) is only a map. Every rule needs RR addresses from the decompile (`tools/ghidra/build/full-v8/`) or assembly (`tools/ghidra/build/cfru_all.asm`, `tools/ghidra/asm.sh`). Say plainly when something is only observed.
- **Never touch the user's session or save.** Their mGBA runs `roms/rr.gba` with saves in `roms/`. Test runs use a ROM copy (`RR_TEST_ROM=<scratch>/rr.gba`) and a separate log dir (`RR_VIEWER_LOG_DIR`). Only kill their mGBA when they ask for a restart, after they saved (check the `roms/rr.ss*` / `rr.sav` timestamps), by its PID.
- **No approvals:** plain Bash commands, no inline scripts piped into `python3`, no `&` chains; write multi-line logic to a file (scratchpad) and run it.
- **Writing:** no em dashes anywhere; short replies; repeat edited file paths at the end; commit when a piece works; never push without asking (the user has asked for a push before, but ask each time).
- Doubles are not predicted yet; the user just started a doubles gauntlet.

## How to run things

- **User's session:** `tools/mgba/run_viewer.sh` (mGBA 0.11 dev build at `/Applications/mGBA.app`, loads `tools/mgba/rr_ai_viewer.lua`). Run it in the background. To restart: user saves, then `kill <pid of the mGBA with rr_ai_viewer.lua roms/rr.gba>` and relaunch.
- **Analyze the live log:** `python3 -I tools/mgba/check_decisions.py tools/mgba/logs/decisions.jsonl [--switches]` (singles move decisions with predictions; doubles entries have `"doubles":true`, `targets` with every target's scores and `chosen_target`; switch entries are text blocks). Use `tail -n +N` to look only at entries since the last check.
- **Replay a savestate automatically:** `tools/mgba/run_repeat_test.sh <state> [runs] [random|fixed]` with env options: `RR_TEST_DECISIONS=N` (turns per run), `RR_TEST_TRACE=ADDR:reg,...` (log a register each time an address runs; `090E1380:r1,090E1380:r14,090E1394:r1,090E1394:r14` = every score change and its caller), `RR_TEST_PLAN="1:switch4"` (scripted player switch), `RR_TEST_SEED_MAIN=turn`, `RR_TEST_DMGCAL=1` (log RR's cached damage next to the model's), `RR_TEST_EXTRA_SCRIPT=<viewer>` (+ `RR_VIEWER_LOG_DIR`), `RR_TEST_ROM`. Only use it on a savestate the user points to. `summarize_trace.py`, `check_dmgcal.py`, `check_random2.py` analyze its log.
- **ROM helpers** (`tools/rom/`): `move_info.py` (move data by name), `item_info.py`, `ability_ids.py` (RR ability IDs), `find_bl.py` (callers of an address), `find_refs.py`, `jump_table.py` (decode switch tables), `find_text.py`, `find_base_stats.py`.

## What the model does now (`tools/mgba/rr_model.lua`)

Singles move scores, computed at the move-choice entry `0x090C82C0` from the battle state, plus faint-replacement prediction. Measured in the user's play: about 80% of move decisions had the real choice among the predicted options; faint replacements matched RR's per-slot scores exactly in every logged case since the bench fix.

Inputs read from RR's own caches (so tests are about the scoring rules, not formulas): AI damage `gNewBS+0x2F0`, strongest move `+0x22E` (can lag one Pokemon behind after a faint), predicted player move `+0x1EE`, end-of-turn damage `+0x810`, bench damage `+0x3F0`, AI starting scores (AI struct `+4`). `gNewBS` = `*0x0203E038`.

Rules modelled (details and evidence in `docs/verified.md`, rules 1-13): roles (RR's table, `0x090C40C4`); KO first +9 / slow KO by role (`0x090C69F4`) / strongest +2; best-accuracy KO move only; RR's MoveWouldHitFirst quirk (your higher priority ignored, `0x090DA0A6`); Speed with weather abilities (`0x0906E320`); healing -10/-9 by HP; poison/Toxic (+role bonus, -10 if you cannot be poisoned); Stockpile and stat boosts via the "good idea to boost" check (`0x090C3C64`); Speed-drop +3 coin; -15 no effect; Ground into airborne = 0 (observed, code spot not found); Fake Out (+8 first turn, -10 after); unusable moves 0; ties and coins as odds. Damage fallback formula covers RR abilities/items/weather and multi-hit = 2 hits; 145 of 183 cached values matched exactly.

Switch-in model: RR's scorer rules (`0x090D7168`) with species base stats (`0x097B98EC`, 28 bytes). **Key finding:** RR's bench damage cache is only reset by `ClearCachedAIData` `0x090C8BA4` (called only from Hardcore's re-pick `0x090C8F04`), so it stays 0 and the AI gives bench Pokemon no KO/2HKO credit.

## Open items, in rough priority

1. **Doubles model:** the user's gauntlet is logging every target. Seen so far: spread moves +16 (Electroweb, Bulldoze) or +11 (Air Cutter), moves on its own partner scored too (Sleep Powder on partner 60), sleep moves +7. Build from RR's doubles code: role (`PredictFightingStyle` doubles path, RR-only "exactly 3" Setup Attacker at `0x090C4574`), damage ladder `0x093504B0`, target choice in `0x090C82C0` (doubles branch, decompile lines ~66-150).
2. **Singles status moves not scored** (seen in play): Reflect +15, Protect +7 / Detect -6, Hypnosis +7 or -10, Thunder Wave / Supersonic / Focus Energy +5, Cotton Spore +6, Leech Seed +6/-4, Safeguard +3, Will-O-Wisp +7, Stealth Rock +6, Shell Smash +6, Sleep Talk -10 when awake, Last Resort -8, Knock Off +3, Sucker Punch -9, Recover's full-HP bonus (`0x090C4C08`, tried once and reverted because it broke other turns).
3. **Voluntary switches** are logged with their reason (14 ShouldSwitch checks, viewer breakpoints) but not predicted; only the 25% skip roll is modelled.
4. Find the code for Ground-into-airborne = 0; Stockpile's extra gate (`0x090DD670`) beyond the predicted-Roar case; where RR resets the role cache each turn.
5. `README.md` / `docs/singles/*.md` still carry CFRU-based claims; move them onto RR addresses over time.
