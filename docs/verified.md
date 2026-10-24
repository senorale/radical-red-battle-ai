# Verified Findings

Rules of the Radical Red 4.1 AI that have been checked in the running game, not only in the code. Each rule lists the code that implements it and the in-game evidence. Code findings that are not on this list stay [ROM] or [CFRU] (see "Tags" in `../README.md`).

Evidence comes from the mGBA scripts in `../tools/mgba/`: `rr_ai_viewer.lua` stops the game inside the AI's own functions and prints what it computed; `run_repeat_test.sh` replays a savestate many times with a different random seed each run and tallies the AI's decision. Both read the AI's real decisions; neither simulates it.

## 1. The AI chooses its action before you choose yours [VERIFIED]

At the start of every turn the enemy decides whether to switch and which move to use, while you are still on the action menu. Your choice for that turn cannot change its choice. It reacts to you only through its own prediction of what you will do, made from the battle state.

- **Code:** at turn start the opponent's battle controller runs the AI: `0x090AD1C0` (choose action) calls `AI_TrySwitchOrUseItem` `0x090C802C` (switch or not), and `OpponentHandleChooseMove` `0x09068418` calls the move choice `0x090C82C0`. The result goes back to the battle engine and is not revisited. [ROM]
- **Evidence:** the viewer printed the enemy's next-turn move while the game was still waiting for the player's action for that turn.
- **Not covered:** Hardcore Mode's re-pick after you switch (`singles/move-or-switch.md` section 6).

## 2. Every turn, a 25% roll skips all switching [VERIFIED]

Before any reason to switch is considered, the AI rolls `Random2() % 4`. On 0 (25%) it stays in and picks a move, however good a switch would be. On the other 75% it runs the normal switch checks, which may still decide to stay. A voluntary switch is therefore never more than 75% likely in a given turn, and a Pokemon that "should" switch usually does within a turn or two.

- **Code:** ShouldSwitch `0x090D824C`, assembly `0x090D82CE`-`0x090D82DE`: call `Random2`, `% 4` via `__umodsi3`, return FALSE on 0. It runs after the RR flag checks (`0x1042`, `0x10C0`), the trapped check and the Sky Drop check, before the first switch check. Radical Red only; CFRU does not have it. [ROM]
- **Evidence:** a position where the enemy had a reason to switch, replayed 100 times with random seeds: 77 switches, 23 stays. In every stay no switch check ran, and recomputing the roll from each run's `Random2` state (`tools/mgba/check_random2.py`) matched all 100 runs.

## 3. The AI's randomness is a fixed formula, not true randomness [VERIFIED]

All the AI's coin flips (the 25% switch skip, switch check rolls, ties between moves or switch-ins) come from `Random2`.

- **Code:** `Random2` `0x0808322C`: `state = state * 0x41C64E6D + 0x3039`, returns `state >> 16`. The state is at `0x020386D0`, which in vanilla FireRed is the wild encounter generator (`sWildEncounterData`); RR's AI uses the same one. It only advances when something calls it (wild encounter checks while walking, and the AI's own calculations). [ROM]
- **Evidence:** loading a savestate and waiting 0, 7 or 14 frames before acting gave the same `Random2` state at the decision and the same decision. Changing only the state changed the decision as the formula predicts (rule 2).
- **Practical meaning:** the same savestate always gives the same AI decision. In normal play it is unpredictable, because every step and every earlier battle moves the state. A script can read `0x020386D0` and compute the AI's rolls before it makes them.

## 4. Absorb switch: a party member that absorbs your predicted move comes in [VERIFIED]

When the switch checks run (the 75% in rule 2), the first check is whether a party member has an ability that absorbs the move the AI predicts you will use (Volt Absorb, Water Absorb, Storm Drain, Flash Fire, ...). If one does, that Pokemon comes in, regardless of the normal switch-in scores.

- **Code:** first block of ShouldSwitch (entered at `0x090D831C`). It tries the scorer's best Pokemon, then the second best, then every other party slot in order; the RR helper `0x093508B0` accepts the first with a matching ability. Same idea as CFRU's `FindMonThatAbsorbsOpponentsMove`. [ROM]
- **Evidence:** against a Pokemon whose attacks were Water moves, the enemy switched to its party member that can have Storm Drain, although another party member had the best switch-in score (31 against 17). The viewer showed the absorb check as the reason and the slot as chosen by that check.
- **Not yet verified:** the 50% skip in singles when your Pokemon is not predicted to be an attacker, and the skip right after a switch-in (both [ROM]).

## 5. Ties are broken at random [VERIFIED]

When two or more moves share the highest score, the AI picks one of them at random with equal chances.

- **Code:** move choice `0x090C82C0` collects the slots with the top score and picks `list[Random2() % count]` (`__modsi3` at `0x09000438`). [ROM]
- **Evidence:** in replays where a damaging move tied a status move at the top score (105), each was chosen 6 times out of 12. In replays without the tie, the higher-scored move was chosen every time (11 of 11).
- **Related, [ROM] only:** switch-in candidates with equal scores are not an even pick. The scorer `0x090D7168` walks the party in order and a later equal score takes over on a 50% flip, so later party slots are favored.
