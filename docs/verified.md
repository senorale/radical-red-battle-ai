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

The AI's coin flips traced so far (the 25% switch skip, switch check rolls, the Speed-drop coin, ties between moves or switch-ins) come from `Random2`. At least one does not: the "good idea to boost" check (`0x090C3C64`) uses the main generator `Random` (`0x08044EC8`, state `0x03005000`, `state * 0x41C64E6D + 0x6073`).

- **Code:** `Random2` `0x0808322C`: `state = state * 0x41C64E6D + 0x3039`, returns `state >> 16`. The state is at `0x020386D0`, which in vanilla FireRed is the wild encounter generator (`sWildEncounterData`); RR's AI uses the same one. It only advances when something calls it (wild encounter checks while walking, and the AI's own calculations). [ROM]
- **Evidence:** loading a savestate and waiting 0, 7 or 14 frames before acting gave the same `Random2` state at the decision and the same decision. Changing only the state changed the decision as the formula predicts (rule 2).
- **Practical meaning:** the same savestate always gives the same AI decision. In normal play it is unpredictable, because every step and every earlier battle moves the state. A script can read `0x020386D0` and compute the AI's rolls before it makes them.

## 4. Absorb switch: a party member that absorbs your predicted move comes in [VERIFIED]

When the switch checks run (the 75% in rule 2), the first check is whether a party member has an ability that absorbs the move the AI predicts you will use (Volt Absorb, Water Absorb, Storm Drain, Flash Fire, ...). If one does, that Pokemon comes in, even when another party member has a better switch-in score. The scores only set the order in which party members are tested (best, second best, then the rest in party order); the first one that absorbs the move wins.

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
- **Also seen in a full traced battle:** +9 for a KO that goes first (Pin Missile, Bullet Seed, Psybeam, AncientPower, all added at `0x090D67A6`), and the slow-KO bonus +6 for a setup stats sweeper. **Not yet verified:** the other roles' slow-KO amounts.

## 8. Roles: what they are, how they are set, what they change [VERIFIED]

Every turn the AI gives each Pokemon on the field a role (CFRU calls it a "fighting style"), worked out from that Pokemon's current 4 moves (and its ability and item). The role does not look at the battle situation: the same Pokemon with the same moves gets the same role all battle.

**How the role is set (singles)**, from Radical Red's role function `0x090C40C4` (singles path). The AI walks its 4 moves; some moves end the check at once, the rest are counted, then the totals decide:

| Check | Role |
|---|---|
| Baton Pass, while it has another usable Pokemon (`0x09074180`) | Baton Pass support (6), immediately |
| a Haze-type move (effect `0x19`, or `0xDE`) | phazing support (9), immediately |
| Wish or Heal Bell (effects `0xB3`, `0x66`) | cleric (7), immediately |
| a trapping move or Mean Look (effects `0x2A`, `0x6A`) | stall (5), immediately |
| Choice item or ability, or Assault Vest (checked on its other moves, `0x09076730`) | pure attacker (1), immediately |
| then, after counting all 4 moves: **any** screen move (Reflect or Light Screen effect), or Aurora Veil while Veil is not up | screens support (8) |
| entry hazards that are not already fully set on your side (Stealth Rock, Sticky Web, Toxic Spikes, Spikes up to 3 layers, read from `gSideTimers`) | phazing support (9) if it also has Roar/Whirlwind, else hazard setter (10) |
| 3 or 4 attacks | setup stats sweeper (2) with a stat-boosting move (an attack that boosts counts, e.g. Power-Up Punch); else setup status sweeper (3) with any status move; else pure attacker (1) |
| exactly 2 attacks, not Leech Seed + Protect | setup stats sweeper (2) with a boosting move, setup status sweeper (3) with a status move or Roar |
| anything else (0 or 1 attack, or Leech Seed + Protect) | stall (5) |

Differences from CFRU: one screen move is enough for screens support, and RR never gives the "screens sweeper" role in singles (CFRU needs two screens and gives screens sweeper with 2+ attacks). [ROM, checked in assembly: screen counter `0x090C418C`-`0x090C4194`, decision `0x090C4272`-`0x090C432C`]

The role is recomputed every turn but only changes mid-battle through battle state, never because you switched: once its hazards are fully set, Aurora Veil is up, or Baton Pass has no one left to pass to, those moves stop counting.

**What the role changes:** only the *size* of some bonuses. Whether a bonus applies at all is decided by the situation (can it KO, does it go first, its HP, whether the move is useful now). Role-dependent bonuses:

- **status moves** (Toxic, Stockpile, ...), `0x090C5C90`, decoded from RR's jump table at `0x090C5CAE` ("boost" is the move's own value, e.g. Toxic 1):

  | Role | Bonus |
  |---|---|
  | pure attacker, none | 0 |
  | setup stats sweeper | 3 + boost, only if you cannot 2HKO it (`0x090DFE50`); CFRU gives a flat 3 |
  | setup status sweeper, phazing support | 4 + boost |
  | screens support (and screens sweeper, unused in singles) | 2 + boost |
  | stall, cleric | 3 + boost |
  | Baton Pass support | +1, only if boost is 3 or more |
  | hazard setter | 3 |

- **stat-boosting moves** (Swords Dance, Power-Up Punch, ...), `0x090C5D0C`, jump table at `0x090C5E0E` (a near-identical second table at `0x090C6098` is used when your role is stall, Baton Pass, cleric, screens support or phazing and your last move was a status move; in singles it gives the same amounts). Most roles first ask "is boosting a good idea now?" (`0x090C3C64`, below); if not, no bonus:

  | Role | Bonus when boosting is a good idea |
  |---|---|
  | pure attacker | 3 + boost (if not a good idea: +1, only for an attack that raises Attack or Sp. Atk) |
  | setup stats sweeper | 3 + boost |
  | setup status sweeper | 5 (the status-move bonus with boost 1) |
  | screens support | 3 |
  | stall, cleric | 4 |
  | phazing support | 5, but none if it has a Haze-type move itself |
  | hazard setter | 3 |
  | Baton Pass support | no good-idea check: Attack, Speed, Sp. Atk, accuracy +5 while that stat is below +4; Defense, Sp. Def +4 below +4; evasion +6 below +6 |

  **Good idea to boost** (`0x090C3C64`, singles, [ROM]): no if your ability ignores its boosts (unless it has a move that gets around that). It needs the AI not badly poisoned (unless above 75% HP or with a Poison Heal-type ability). It needs you to have no way to undo the boost (Roar, Whirlwind, Haze, Clear Smog, Dragon Tail and similar, unless they would fail on it) and no Encore-type move, unless you cannot 2HKO it; a 50% coin from the main generator `Random` skips these two checks. Then, if its move cannot KO you: yes when you are about to switch or cannot act, or for Speed when it is below +3 and you cannot KO it, or when you cannot 2HKO it and the stat is below +4. If its move can KO you: yes only in narrow cases, with the stat below +3.
- **a KO that goes second** (rule 7), `0x090C69F4`, jump table at `0x090C6A12`: pure attacker and setup status sweeper +8; setup stats sweeper +8 if knocking out your last Pokemon is the better play (`0x090C3B48`), else +6; stall and phazing support 9 or 8; Baton Pass support 9, 8 or 3; cleric 9, 7 or 6; screens 9 or 6; hazard setter 9, 6 or 3 (the lower values when you cannot 2HKO it). Same as CFRU.

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

The scores only set the testing order; the first Pokemon in that order that absorbs Water wins. This step had no further randomness: every run that passed the 25% roll switched to Lileep.

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
