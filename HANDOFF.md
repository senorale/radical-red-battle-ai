# Handoff: live AI predictor for Radical Red 4.1

For a new Claude session. Read this, then `progress.md` (overall state) and `docs/findings.md` (the rules confirmed in game), then continue. Written 2026-10-25.

## What the user is doing and how to help

The user plays Radical Red 4.1 in mGBA with the viewer script loaded, mostly doubles fights now, and wants to understand how the AI chooses. For every enemy decision the viewer shows what our model predicted (PREDICT), what the AI actually computed (ACTUAL) and how close the model was (MODEL), and writes it all to `tools/mgba/logs/decisions.jsonl`. When the user says "logs", analyze the new entries, explain the decisions they ask about from the logged numbers, find where a prediction missed, locate the rule in **Radical Red's own code**, fix `tools/mgba/rr_model.lua`, verify, commit, and relaunch their session when they ask.

The user's rules (also in memory files):

- **Learn from live play.** Improvements come from the user's own battles. The repeat tool is for savestates the user points to.
- **Check RR's code, not CFRU.** CFRU source (`vendor/cfru`) is only a map. Every rule needs RR addresses from the decompile (`tools/ghidra/build/full-v8/`) or assembly (`tools/ghidra/build/cfru_all.asm`). Say plainly when something is only observed. Check claims with commands (logs, traces, replays), not reasoning alone.
- **Never touch the user's session or save** unless they ask (they did once, for the bench-cache experiment). Test runs use copies in the scratchpad (`RR_TEST_ROM`, a copied savestate, `RR_VIEWER_LOG_DIR`). Only kill their mGBA when they ask for a restart, after checking the `roms/rr.ss*` / `rr.sav` timestamps, by its PID. The user closes mGBA themselves sometimes; that is not a crash.
- **No approvals:** plain Bash commands, no inline scripts piped into `python3`, no `&` chains; write multi-line logic to a file (scratchpad) and run it.
- **Writing:** no em dashes anywhere; short replies; repeat edited file paths at the end; ask before multi-file edits; commit when a piece works; push only when asked.

## How to run things

- **User's session:** `exec /Applications/mGBA.app/Contents/MacOS/mGBA --script tools/mgba/rr_ai_viewer.lua -t roms/rr.ss2 roms/rr.gba` in the background (the user usually wants to start on savestate 2), or `tools/mgba/run_viewer.sh` without a savestate. To restart: check save timestamps, `kill <pid>`, relaunch. "Clear the logs" = rename `decisions.jsonl` and `viewer.log` to dated archives in `tools/mgba/logs/` (never delete).
- **Read the live log:** each line is JSON. Move decisions have `actual`, `predicted` (singles), and in doubles `targets` with per-target `scores`, `hp`, `dmg` (AI to target), `dmg_back` (target to AI), `ai_ko`/`you_ko` (RR's CanKnockOut, often null when RR did not need it) and `chosen_target`. Switch entries are text blocks with field status, PREDICT, per-slot `why`, MODEL and the bench cache. `python3 -I tools/mgba/check_decisions.py <log>` summarizes singles predictions; `python3 -I tools/mgba/watch_switchins.py <log> --all` prints switch-ins (the user keeps one running in a Terminal window).
- **Replay a savestate:** `tools/mgba/run_repeat_test.sh <state> [runs] [random|fixed]`. Env: `RR_TEST_DECISIONS=N`, `RR_TEST_TRACE=ADDR:reg,...`, `RR_TEST_POKE=ADDR[+OFF]:SIZE:VALUE` (e.g. party HP before a battle), `RR_TEST_EXTRA_SCRIPT=$PWD/tools/mgba/rr_ai_viewer.lua` with `RR_VIEWER_LOG_DIR=<scratch>/log/` to get per-target choices, `RR_TEST_ROM=<scratch copy>`. `random` reseeds `Random2` per run (odds); `fixed` keeps the savestate's seed (what the user's game will do).
- **ROM helpers** (`tools/rom/`): `move_info.py`, `item_info.py`, `ability_ids.py`, `find_bl.py`, `find_refs.py`, `jump_table.py` (decode switch tables; the s8 helper `0x090003EA` is not in its list), `find_base_stats.py`. Note `tools/ghidra/asm.sh` takes an OUTPUT FILE as its first argument.

## What the model does now (`tools/mgba/rr_model.lua`)

- **Singles move scores** at the move-choice entry `0x090C82C0`: rules 1-13, 15, 16 of `docs/findings.md` (KO / strongest, roles, Speed, healing, poison, boosts, Fake Out, Last Resort, U-turn pivot check). About 80% of decisions had the real choice among the predicted options; misses are mostly status moves not scored yet.
- **Switch-ins** (singles and doubles): RR's scorer `0x090D7168` with bench damage 0 (the bench damage cache bug, rule 14), per-foe sum and type-only defense in doubles (S1-S3). Matched every logged doubles switch-in (19 of 19 on 2026-10-25). Each prediction carries the reason per foe.
- **Doubles move choice: not predicted yet.** The rules are decoded and verified (D1-D6): doubles damage points + role table, partner "handled" targets, -30 no effect, Fake Out by role and threat, the target tie-break. Next big piece is building it.
- Inputs read from RR's caches (`gNewBS = *0x0203E038`): damage `+0x2F0`, strongest move `+0x22E`, predicted move `+0x1EE` (`0xFFFF` = predicted switch), end-of-turn damage `+0x810`, CanKnockOut `+0x820`, Can2HKO `+0x830`, bench damage `+0x3F0` (stuck at 0), doubles best move `+0x7B0` / points `+0x7D0`.

## Open items, in rough priority

1. **Doubles move-choice model** from D1-D6. Still to decode: role assignment for doubles (Perrserker came out as Utility), status-move bonuses in doubles (Sleep Powder +7, partner moves), the spot where RR doubles the "avoid" penalties (-30).
2. **Singles status moves not scored:** Reflect +15, Protect +7 / Detect -6, Hypnosis +7 or -10, Thunder Wave / Supersonic / Focus Energy / Leer / Confuse Ray +5, Cotton Spore / Stun Spore / Will-O-Wisp / Trailblaze +6, Leech Seed +6/-4, Safeguard +3, Stealth Rock +6, Torment +3, Rest / Sleep Talk patterns, Recover's full-HP bonus (`0x090C4C08`).
3. **Voluntary switches** are logged with their reason but not predicted (only the 25% skip roll).
4. Unexplained: Iron Head 109 on a non-KO (frame 26462, 2026-10-24); the code that zeroes the bench cache; Ground into airborne = 0 code spot.
5. Doc audit is done for the topic docs (2026-10-25); `docs/ai-notes.md` stays raw notes.
