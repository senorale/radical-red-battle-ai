# Handoff: live AI predictor for Radical Red 4.1

For a new Claude session. Read this, then `progress.md` (overall research state), then start working. Written 2026-10-23.

## The user's goal and plan

The user wants to understand how Radical Red 4.1's enemy AI chooses moves, singles and doubles. Their plan from here:

1. **They play through the game** in mGBA with the files in this repo.
2. **A script running inside mGBA predicts what the AI will do** each time an enemy is about to choose, using our current understanding of the AI (the rules in `docs/`). It must see the battle state: the player's party, every Pokemon's 4 moves, HP, stats and so on.
3. **The same script then shows what the AI actually did**: the real scores it computed and the move and target it picked.
4. **Prediction first, then actual, every decision, for both single and double battles.**
5. **Fine-tune as they go:** when the prediction is wrong, find out why in the code, fix the model (and the docs), and repeat. Matches over many turns are what turn a rule into a human-verified [VERIFIED] finding.

Earlier in the project the user also mentioned possibly changing game data later (for example route encounters). Not part of this task.

## How the user wants you to work

- **No approvals.** The user does not want to approve anything. Keep every Bash call a plain command. Never pipe an inline script into an interpreter (`python3 -I - <<'EOF'`) and never chain backgrounded commands with `&`; those got stopped by permission prompts even in bypass mode. Write multi-line logic to a script file and run it.
- **Evidence, not docs.** The docs in `docs/` are our current understanding, not proof. For RR behavior, cite ROM addresses (decompile in `tools/ghidra/build/full-v8/`, then raw assembly via `tools/ghidra/asm.sh` or `tools/ghidra/build/cfru_all.asm`). A Ghidra decompile is a hint; confirm important details in assembly.
- **Nothing is human-verified yet.** Only the user playing and confirming makes something [VERIFIED].
- **Commits:** commit when a piece works; no `Co-Authored-By` trailer; no ticket prefix; never push without asking (a hook asks for `git push` anyway).
- **Writing:** no em dashes anywhere. Keep replies short. After writing files, repeat their paths at the end of the reply.
- **ROM-derived data** (decompiles, savestates, saves, logs with game data) stays in git-ignored places: `roms/`, `tools/ghidra/build/`, `vendor/`.

## What exists now

### Emulator and files

- mGBA 0.11.0 development build installed at `/Applications/mGBA.app` (needed: stable 0.10 has no breakpoint API).
- `roms/rr.gba`: Radical Red 4.1 (SHA1 `964f951a0fdaf209e4ea1344883ef0d557bb3a80`, CRC32 `FBA55DD8`).
- `roms/rr.sav`: the user's in-game save. `roms/rr.ss1`-`rr.ss3`: their mGBA savestates (F1-F3 load them). All match this ROM. `rr.ss2` is in a wild single battle (Tepig Lv6 vs Poochyena Lv4); its EWRAM is extracted to `roms/states/ss2.ewram` for offline tests.
- `roms/openemu/*.state`: two OpenEmu states from 2023-08-05, extracted to raw mGBA states. **They belong to a different ROM** (CRC32 `4A8B3B82`, MD5 `13b578459a321635fc5cfe77abb25cb7`), so they cannot be used with 4.1. `tools/mgba/state_info.py <state> <rom>` shows this.
- `roms/rr.sav.unused-2026-10-23`: an empty save from a first launch; safe to delete.
- Launch: `tools/mgba/run_viewer.sh` (starts mGBA with the ROM and `--script tools/mgba/rr_ai_viewer.lua`).

### `tools/mgba/rr_ai_viewer.lua` (shows what the AI actually did)

Breakpoints inside RR's move-choice function `0x090C82C0` (CFRU `BattleAI_ChooseMoveOrAction`, singles and doubles inlined):

| Address | Meaning |
|---|---|
| `0x090C83AC` | Singles: scores final, about to pick the best. Snapshot the AI struct here. |
| `0x090C875C` | Doubles: scores for the current target final. Runs once per target. |
| `0x090C837A` | The function's only exit. `r0` = chosen move slot 0-3, 4 = flee, 5 = watch. `gBankTarget` holds the final target (set at decompile line 372 of `090C82C0`, then retargeted if it hit the partner with a negative score). |

Why it only sees real decisions: `0x090C82C0` is the only caller of `BattleAI_DoAIProcessing` `0x090C6F3C` (call sites `0x090C838C`, `0x090C871E`). The per-turn move predictions (`PredictMovesForBanks` in CFRU) call `AIScript_Negatives`/`Positives` directly into local arrays and do not touch the AI struct's scores.

It prints, per decision: the AI Pokemon, each target considered, every move's score, ties (broken at random), and the chosen move/target. Tested only offline: `lua tools/mgba/test_viewer.lua roms/rr.gba tools/mgba/rr_ai_viewer.lua` (fake RAM, real ROM name tables). **Not yet run in a real battle.** Does not cover switching (ShouldSwitch `0x090D824C`) or post-KO switch-ins (`0x090D7168`).

### RAM and ROM layout (RR 4.1)

Verified in RR's code this session unless marked otherwise:

| What | Address | Notes |
|---|---|---|
| `gBattleResources` | `0x02023FF4` | `[+0x14]` = AI struct: `+0` aiState (0 setup, 1 scoring, 2 done), `+1` movesetIndex, `+2` moveConsidered (u16), `+4` score[4] (s8), `+0xC` aiFlags (u32), `+0x10` aiAction, `+0x11` aiLogicId. From `BattleAI_DoAIProcessing` `0x090C6F3C`. |
| AI battler | `0x02023D6B` | battler being scored (u8) |
| AI target | `0x02023D6C` | `gBankTarget` (u8) |
| `gBattleMons` | `0x02023BE4` | 0x58 bytes per battler, CFRU `struct BattlePokemon`: `+0x18` is type3 (not an HP stage), stages Atk..Eva at `+0x19`..`+0x1F`. Checked on real data (`rr.ss2`) and the type reads at `0x0906CB64`. Full layout in `tools/mgba/rr_state.lua`. |
| Move names | `0x090F3188` | 13 bytes each (Gen 3 charset). 32 pointers reference it; vanilla table unused. |
| Species names | `0x094042CC` | 11 bytes each. 41 pointers reference it. |
| `gBattleMoves` | `0x091521D0` | 12 bytes per move. Seen in code: `+0` effect, `+10` split (2 = status). Other fields assumed vanilla-like (power, type, accuracy, pp, secondary chance, target, priority, flags); **check before relying on them**. |
| `gPlayerParty` / `gEnemyParty` | `0x02024284` / `0x0202402C` | Checked on real data (`rr.ss2`). 100-byte structs, **unencrypted, fixed order G A E M, checksum 0**: `EncryptBoxMon` `0x0803F8F8` eor nopped, `GetSubstruct` order forced to 0 at `0x0803F94C`, `GetBoxMonData` decrypt nopped `0x0803FD94`-`0x0803FDA6`. `gPlayerPartyCount` is `0x02024029` on real data (`0x02024028` from `symbols.txt` is wrong). |
| Doubles damage ladder | `0x093504B0` | `gDoublesDamageViabilityMapping[class-11][score]`, recorded earlier as byte-identical to CFRU; not re-checked this session. |

Battlers: 0 = player left, 1 = foe left, 2 = player right, 3 = foe right.

mGBA savestates (`.ss*`) are PNG files with the zlib-compressed raw state in chunk `gbAs`: 0x61000 bytes, ROM CRC32 at `+0x08`, EWRAM at `+0x21000` (`tools/mgba/extract_state.py`). The user's states have version magic `0x0100000B`.

### Other tools worth knowing

- `tools/ghidra/full.sh`, `tools/ghidra/validate_full.py`, `tools/ghidra/xcheck_calls.py`: full decompile and its validation (v8 is the trusted baseline, `tools/ghidra/build/full-v8/`).
- `tools/rom/find_names.py`: locates name tables and counts references.
- `tools/recomp/`: byte-matching tools (paused; see `progress.md` for why).

## What to build next

1. **Done (2026-10-23): `tools/mgba/rr_state.lua`**, tested on `rr.ss2` by `tools/mgba/test_state.lua`. Missing: item and ability names, party abilities (need the base stats table), bit meanings of weather/side statuses/status1/status2. Original task: both sides' active Pokemon from `gBattleMons` (species, HP, stats, stat stages, ability, item, types, status, moves), plus both full parties from `gPlayerParty`/`gEnemyParty` (decrypt the Gen 3 substructures). Confirm every offset in RR's code first.
2. **Prediction hook:** break at the entry of `0x090C82C0` (or just before the scoring loop) and print "PREDICT": the model's score per move per target and the predicted move/target, using only data the script read.
3. **Model** (start simple, refine): base 100 per move; damage estimate at the 93% roll (the AI's KO assumption per `docs/ai-guide.md`); KO bonuses, strongest-move bonus and immunity penalties for singles from `docs/singles/move-or-switch.md`; for doubles the role rules (`PredictFightingStyle` `0x090C40C4`, including RR's exactly-3 Setup Attacker check at `0x090C4574`), the per-target damage score and the ladder table at `0x093504B0`, per `docs/doubles/moves-and-targets.md`. Mark moves the model does not understand (most status moves at first) as low confidence instead of guessing.
4. **Then the existing viewer's "ACTUAL"** output: real scores and the chosen move/target, right after the prediction.
5. **Log every decision** (state, predicted scores, actual scores, choice) as one JSON line per decision to a git-ignored file (for example `tools/mgba/logs/`), so a later session can find systematic misses and trace them to the ROM code.
6. Keep `tools/mgba/test_viewer.lua`-style offline tests working for anything that can be faked.

Later: also predict switching and post-KO switch-ins (`docs/singles/post-ko-switch-in.md`, `docs/doubles/post-ko-switch-in.md`).
