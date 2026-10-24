# Verified Findings

Behavior of the Radical Red 4.1 AI that has been checked in the running game, not only in the code. Each entry says what was observed, how, and which code explains it. Code findings that are not on this list stay [ROM] or [CFRU] (see "Tags" in `../README.md`).

How the observations were made: the mGBA scripts in `../tools/mgba/` stop the game inside the AI's own functions and print what it computed (`rr_ai_viewer.lua`), or replay a savestate many times and tally the result (`repeat_switch_test.lua`). They read the AI's real decisions; they do not simulate it.

## 1. The AI picks its action before you pick yours [VERIFIED]

At the start of each turn the enemy decides whether to switch and which move to use, while you are still on the action menu. Your choice for that turn cannot change its choice. It only "reacts" to you through its own prediction of what you will do, which it makes from the battle state, not from your input.

- **Observed (2026-10-24, trainer battle, Meditite vs your Mightyena):** the viewer printed Meditite's turn-2 decision (Rock Tomb chosen, score 103) while the game was still waiting for your turn-2 action. Turn 2 had not been played yet.
- **Code:** the opponent's battle controller runs the AI when the battle asks every battler for its action at the start of the turn: `0x090AD1C0` (choose action) calls `AI_TrySwitchOrUseItem` `0x090C802C` (switch or not), and `OpponentHandleChooseMove` `0x09068418` calls the move choice `0x090C82C0`. The choice is returned to the battle engine there and not revisited. [ROM]
- **Not covered:** Hardcore Mode's re-pick after you switch (`singles/move-or-switch.md` section 6) has not been tested.

## 2. 25% of turns, the AI skips all switch logic and stays in [VERIFIED]

Every turn, before any switch reason is even considered, the AI rolls `Random2() % 4`. On 0 (25%) it stays in and picks a move as usual, no matter how good a switch would be. On the other 75% it runs the normal switch checks, which may still decide to stay.

- **Code:** ShouldSwitch `0x090D824C`, assembly `0x090D82CE`-`0x090D82DE`: call `Random2`, `% 4` via `__umodsi3`, return FALSE on 0. It comes after the RR flag checks (`0x1042`, `0x10C0`), the trapped check and the Sky Drop check, and before the first CFRU switch check. Not in CFRU. [ROM]
- **Observed in play:** from the same position (`rr.ss6`: your Psyduck, which knows Water Pulse and Water Gun, against Hippopotas), the enemy usually switched to Lileep but not always.
- **Repeat test (2026-10-24):** `rr.ss6` replayed 100 times with a different `Random2` seed each run (`tools/mgba/run_repeat_test.sh roms/rr.ss6 100 random`): 77 switched to Lileep, 23 stayed (17 Toxic, 6 Bulldoze). In all 23 stays no switch check ran at all. `tools/mgba/check_random2.py` recomputed the roll from each run's `Random2` state: 100 of 100 runs match the formula.
- **Practical meaning:** a switch is never certain. Even a Pokemon that "has to" switch stays in about 1 turn in 4, and rolls again next turn.

### It is pseudo-random, not truly random

- `Random2` (`0x0808322C`) is a simple formula: `state = state * 0x41C64E6D + 0x3039`, result `state >> 16`. Its state is at `0x020386D0`, which in vanilla FireRed is the wild encounter generator (`sWildEncounterData`); RR's AI uses the same one.
- It only moves when something calls it (wild encounter checks while walking, and the AI's own calculations). It does not change with time: loading a savestate and waiting 0, 7 or 14 frames gave the same state (`0x209C3E5D`) at the decision, so **the same savestate always gives the same decision**.
- In normal play it is unpredictable to the player, because every step and every earlier battle moves it. A script can read `0x020386D0` and compute the roll before the AI makes it.

## 3. Absorb switch: a party member that absorbs your predicted move comes in [VERIFIED]

When the switch logic runs (the 75% above), the first check is whether a party member has an ability that absorbs the move the AI predicts you will use. If one does, that Pokemon comes in, ignoring the normal switch-in scores.

- **Observed (2026-10-24, `rr.ss6`):** Hippopotas switched to Lileep against your Psyduck (Water moves). Lileep can have Storm Drain, which absorbs Water. The viewer showed the reason as the absorb check and the slot as set by that check, although Cacnea had the best switch-in score (31 against Lileep's 17).
- **Code:** the absorb block of ShouldSwitch (first check, entered at `0x090D831C`) tries the scorer's best Pokemon, then the second best, then every other party slot in order, and the RR helper `0x093508B0` accepts the first one with a matching ability. Same idea as CFRU's `FindMonThatAbsorbsOpponentsMove`. In singles it is skipped 50% of the time when your Pokemon is not predicted to be an attacker, and always right after a switch-in. [ROM]
- **Not yet verified:** which ability Lileep had (Storm Drain was not confirmed on screen), and the 50% skip against non-attackers.
