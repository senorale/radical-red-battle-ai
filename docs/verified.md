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

## 6. Speed-lowering attacks get +3 on a coin flip (singles) [VERIFIED]

In single battles, an attacking move whose side effect lowers your Speed (Bulldoze, Rock Tomb, Icy Wind, Mud Shot, ...) gets +3 on a 50% coin flip, when lowering your Speed is useful to the AI. +3 lifts it above the +2 the strongest move gets. Radical Red added the coin flip; in CFRU the +3 is always given.

- **Conditions** ([ROM], same as CFRU's `EFFECT_SPEED_DOWN_HIT` case and `GoodIdeaToLowerSpeed`): the Speed drop happens at least 50% of the time (`0x090DB220`, doubled by Serene Grace), your Pokemon is not behind a Substitute the move cannot hit through (`0x09075B98`), the AI cannot KO you first, the AI is not faster than you, and your ability does not block the drop (Contrary, Clear Body and similar) (`0x090E006C`).
- **Code:** Positives, assembly `0x090D29D0`-`0x090D2A6A`: after the conditions, `Random2() % 2` (`0x090D2A4C`-`0x090D2A5C`); on 0, `+3` via `0x090E1380` at `0x090D2A62`. [ROM]
- **Evidence:** replays where the AI stayed in with two Speed-lowering attacks, logging the coin at `0x090D2A5A` (`RR_TEST_TRACE=090D2A5A:r0 tools/mgba/run_repeat_test.sh ...`): in 26 of 26 move scorings, coin 0 gave +3 and coin 1 gave nothing (Bulldoze 105 or 102, Rock Tomb 103 or 100).
- **Side note:** the AI's prediction pass runs the same scoring first, so it uses up `Random2` rolls before the real choice.

## 7. How a damaging move is scored: KO bonus, else strongest-move bonus (singles) [VERIFIED]

For each damaging move the AI gives at most one of these, checked in this order:

1. **KO and goes first:** +9.
2. **KO but goes second** ("slow KO"), when the AI has no Protect, you are not predicted to switch, and you would not faint on your own anyway: a bonus set by the AI's role (setup status sweeper +8; the other roles 3 to 9, see `IncreaseViabilityForSlowKOMove` in CFRU `ai_advanced.c`).
3. **Otherwise, its strongest move:** +2 (a role-based 4 to 8 instead if it KOs in one hit and nothing else changed its score).

Side-effect bonuses such as rule 6's Speed drop come on top.

- **Code:** Positives, the KO checks around `0x090D66DE`-`0x090D67DA`; slow-KO bonus `0x090C69F4` (role switch, `+8` at `0x090C6A28`), called from `0x090D67DA`; strongest move `IsStrongestMove` `0x090DFE00`, `+2` set at `0x090D692A` and added at `0x090D67A6`. Same as CFRU's `DamageMoveViabilityIncrease`. [ROM]
- **Evidence:** traced score changes over several turns: a move that KOs while the AI moves second got +8 (role 3), and once your new Pokemon resisted it, that move got nothing and the AI's strongest other move got +2.
- **Not yet verified:** the +9 for a KO that goes first, and the other roles' slow-KO amounts.

## 8. Roles: what they are, how they are set, what they change [VERIFIED]

Every turn the AI gives each Pokemon on the field a role (CFRU calls it a "fighting style"), worked out from that Pokemon's current 4 moves (and its ability and item). The role does not look at the battle situation: the same Pokemon with the same moves gets the same role all battle.

**How the role is set (singles)**, first match wins. The table is CFRU's `PredictFightingStyle`; in the game three rows are verified so far (setup status sweeper, setup stats sweeper, pure attacker by 4 attacks), the rest is [CFRU]:

| Moveset | Role |
|---|---|
| Baton Pass (with a teammate to pass to) | Baton Pass support |
| Haze or Clear Smog | phazing support |
| Wish or Heal Bell | cleric |
| trapping move or Mean Look | stall |
| Choice item or ability, or Assault Vest | pure attacker |
| 2+ screens (Reflect, Light Screen; Aurora Veil counts as 2) | screens sweeper (2+ attacks) or screens support |
| entry hazards still worth setting | phazing support (if it also has Roar/Whirlwind) or hazard setter |
| 3+ attacks | setup stats sweeper (with a boosting move), setup status sweeper (with a status or phazing move), else pure attacker |
| Leech Seed and Protect | stall |
| 2 attacks plus a boosting, status or phazing move | setup stats sweeper (boosting) or setup status sweeper |
| anything else | stall |

**What the role changes:** only the *size* of some bonuses. Whether a bonus applies at all is decided by the situation (can it KO, does it go first, its HP, whether the move is useful now). Role-dependent bonuses:

- status moves (Toxic, Stockpile, ...): setup status sweeper 4 + boost, stall and cleric 3 + boost, screens 2 + boost, pure attacker 0 (`IncreaseStatusViability` `0x090C5C90`);
- stat-boosting moves (Power-Up Punch, ...): by role (called from `0x090C5F26`);
- a KO that goes second (rule 7): setup status sweeper +8, setup stats sweeper +6 or +8, other roles 3 to 9 (`0x090C69F4`).

So the role decides close calls between a status or setup move and an attack. Example: when it cannot KO, a setup status sweeper's Stockpile (105) beats its strongest attack (102), while a pure attacker's Stockpile would stay at 100 and it would attack.

- **Code:** role computed by `0x090C4618` (CFRU `PredictBankFightingStyle`/`PredictFightingStyle`, singles part `0x090C40C4`), cached per battler at `gNewBS+0x888` by `GetBankFightingStyle` `0x090C46DC`, recomputed each turn. [ROM]
- **Evidence:** a full traced battle: 2 attacks plus status moves (Hippopotas: Bulldoze, Rock Tomb, Toxic, Slack Off; Lileep: Stockpile, Recover, Hidden Power, Mega Drain) gave setup status sweeper; 3 attacks plus Power-Up Punch (Cacnea) gave setup stats sweeper; 4 attacks (Lunatone) gave pure attacker. The role was recomputed every turn and never changed for the same Pokemon. The slow-KO bonus was +8 for the setup status sweeper and +6 for the setup stats sweeper.

## 9. A move that would have no effect gets -15 [VERIFIED]

If the AI's type check says the move would miss outright, have no effect or fail against you (for example an Electric move into a Ground type, a Psychic move into a Dark type), the move gets -15.

- **Code:** Negatives `0x090CB2E0`-`0x090CB2F8`: type check `0x090838A4`, result `& 0x29` (missed, no effect, failed) gives -15. [ROM]
- **Evidence:** in a traced battle, ThunderPunch against a Ground-type and Psybeam against a Dark-type each got -15 on every turn they were scored.

## Worked example: Hippopotas against your Psyduck

How rules 2 to 9 combine in one real position (test state `rr.ss6`, start of the battle). Every number below was traced in the game with `RR_TEST_TRACE`: the AI's score helpers (`0x090E1380` adds, `0x090E1394` subtracts), who called them, and the branch that led there. Your Psyduck (Water Pulse, Confusion, Tail Whip, Water Gun) faces the enemy's Hippopotas (Bulldoze, Rock Tomb, Toxic, Slack Off). The enemy's bench: Cacnea, Lunatone, Lileep, Archen, Varoom.

**Step 1: the 25% roll (rule 2).** 1 turn in 4, the AI skips switching and goes to step 3.

**Step 2: why it wants to switch (rule 4).** The AI predicts your Psyduck will use Water Pulse (traced: move `352` passed to the absorb helper). Hippopotas is Ground, weak to Water, and a party member can absorb Water. The absorb check tries the switch-in scorer's best Pokemon first, then the second best:

| Order | Party member | Switch-in score | Absorbs Water? |
|---|---|---|---|
| 1st | Cacnea (best score: resists all your moves, outspeeds) | 31 | no, rejected |
| 2nd | Lileep (second best: resists all your moves) | 17 | yes, Storm Drain, **switches in** |

The scores do not decide here; the first Pokemon (in that order) that absorbs Water wins. This step had no further randomness: every run that passed the 25% roll switched to Lileep.

**Step 3: if it stays, the move scores.** Every move starts at 100.

| Move | Score | Why |
|---|---|---|
| Toxic | 105 | +5: Toxic's base boost is +1 ("AI enjoys poisoning", CFRU's default when poisoning is not a bad idea), and status moves get extra points by the AI's battle role. Hippopotas plays the "setup status sweeper" role, which gets 4 + boost = 5 (`IncreaseStatusViability` `0x090C5C90`, called from `0x090D246A`; role 3, boost 1, traced) |
| Bulldoze | 102 or **105** | +2: it is Hippopotas's strongest move against Psyduck (`IsStrongestMove` `0x090DFE00`); the strongest move gets +2, or a role-based 4 to 8 when it KOs in one hit and nothing else changed its score (Bulldoze does not KO). Then +3 on a coin flip because it lowers your Speed (rule 6) |
| Rock Tomb | 100 or 103 | +3 on its own coin flip (rule 6) |
| Slack Off | 90 | -10: healing moves are penalized by the AI's own HP: at 100% -10, at 90-99% -9, at 89% or less no penalty from this rule (Negatives `0x090CB0E8`-`0x090CB110`, HP% = HP x 100 / max HP rounded down, `0x090DD734`). Hippopotas was at full HP |

**Step 4: ties (rule 5).** If Bulldoze lost its coin flip (102), Toxic is the only best move and is used. If Bulldoze won it (105), it ties Toxic and a 50/50 pick decides.

**Resulting odds** (computed from the rules, compared with the replays):

| Outcome | Odds from the rules | 100 replays | 50 replays |
|---|---|---|---|
| Switch to Lileep | 75% | 77 | 37 |
| Stay, Toxic | 25% x (50% + 50% x 50%) = 18.75% | 17 | 10 |
| Stay, Bulldoze | 25% x 50% x 50% = 6.25% | 6 | 3 |

**Turns 2 to 4 (Lileep on the field).** Lileep (Stockpile, Recover, Hidden Power, Mega Drain) is also a setup status sweeper (2 attacks plus status moves). It moves after your Pokemon (Speed 17).

| Turn | Your Pokemon | Stockpile | Recover | Hidden Power | Mega Drain | Used |
|---|---|---|---|---|---|---|
| 2 | Psyduck | 105 (+5, role) | 90 (-10, full HP) | 100 | **108** (+8, KOs you but goes second, rule 7) | Mega Drain, KO |
| 3 | Marill | 105 | 90 | 100 | **108** (same) | Mega Drain, KO |
| 4 | Nuzleaf (Grass/Dark resists Mega Drain) | **105** | 90 | 102 (+2, now its strongest move) | 100 (no KO, no bonus) | Stockpile |
