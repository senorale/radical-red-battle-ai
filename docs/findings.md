# Findings

Rules of the Radical Red 4.1 AI that we have seen in the running game, most of them also read in the code. Each rule lists the code that implements it and the in-game evidence. Code findings that are not on this list stay [HYPOTHESIS] (see "Tags" in `../README.md`).

> **How sure are we?** These are leading hypotheses, not proven facts. All of the evidence comes from one playthrough that has only reached the second gym (as of 2026-10-25): a few dozen trainer battles, a handful of doubles fights, and repeat tests from a few savestates. The [TESTED] and [VERIFIED] rules matched the code we read and every case we logged, but we have not seen later bosses, most abilities, items, weather, terrain, Hardcore Mode or most of the game's double battles. A rule can still turn out to be incomplete or wrong in a situation we have not hit yet. Each "Evidence" line says how much was seen.

Evidence comes from the mGBA scripts in `../tools/mgba/`: `rr_ai_viewer.lua` stops the game inside the AI's own functions and prints what it computed; `run_repeat_test.sh` replays a savestate many times with a different random seed each run and tallies the AI's decision. Both read the AI's real decisions; neither simulates it.

## Legend

| Label | Meaning |
|---|---|
| **1 to 16** | General rules, mostly checked in single battles (the title says "(singles)" when it only applies there) |
| **D1 to D6** | Doubles: how each enemy picks its move and target (section "Doubles: move selection") |
| **S1 to S3** | Doubles: which Pokemon comes in after a faint (section "Doubles: post-KO switch-in") |
| **[VERIFIED]** | Tested, and our model's predictions (`tools/mgba/rr_model.lua`) also matched the real game in the cases we logged |
| **[TESTED]** | A code hypothesis supported by in-game output from our tools (viewer logs, repeat tests, traces), not yet by the model |
| **[OBSERVED]** | A behavior seen repeatedly in game that the code found so far does not explain |
| **[HYPOTHESIS]** | Read in Radical Red's code, not tested in game yet (appears here only as a part of a rule) |
| **"Code:" / "Evidence:"** | Where in the ROM the rule lives / what was seen in game |

Other docs refer to these by label, e.g. "`findings.md` rule 14" or "D6".

| Quick index | |
|---|---|
| Rule 14 | The bench damage cache bug: in every switch-in logged so far, the bench Pokemon's own damage counted as 0 |
| D1 | The faster enemy decides first; every move is scored against every target |
| D2 | Doubles damage points (+4 hit, +2 KO, +1 strongest) and the role table |
| D3 | A foe the partner already KOs is worth nothing |
| D4 | No effect: -30 (absorbing ability -40) |
| D5 | Fake Out: by role, aimed at the bigger threat, 80 after the first turn |
| D6 | The target tie-break: KOs, then "can KO me", then a 25% roll or a coin flip |
| S1 | Switch-in score per foe, summed: Speed +14, resists all +17, walls +2, super-effective -1 |
| S2 | Which Pokemon can come in; ties are a 50% flip favoring later slots |
| S3 | Your last Pokemon: damage-based, and "you KO it" is only -1 |

## 1. The AI chooses its action before you choose yours [TESTED]

At the start of every turn the enemy decides whether to switch and which move to use, while you are still on the action menu. Your choice for that turn cannot change its choice. It reacts to you only through its own prediction of what you will do, made from the battle state.

- **Code:** at turn start the opponent's battle controller runs the AI: `0x090AD1C0` (choose action) calls `AI_TrySwitchOrUseItem` `0x090C802C` (switch or not), and `OpponentHandleChooseMove` `0x09068418` calls the move choice `0x090C82C0`. The result goes back to the battle engine and is not revisited. [HYPOTHESIS]
- **Evidence:** the viewer printed the enemy's next-turn move while the game was still waiting for the player's action for that turn.
- **Not covered:** Hardcore Mode's re-pick after you switch (`singles/move-or-switch.md` section 6).

## 2. Every turn, a 25% roll skips all switching [TESTED]

Before any reason to switch is considered, the AI rolls `Random2() % 4`. On 0 (25%) it stays in and picks a move, however good a switch would be. On the other 75% it runs the normal switch checks, which may still decide to stay. A voluntary switch is therefore never more than 75% likely in a given turn, and a Pokemon that "should" switch usually does within a turn or two.

- **Code:** ShouldSwitch `0x090D824C`, assembly `0x090D82CE`-`0x090D82DE`: call `Random2`, `% 4` via `__umodsi3`, return FALSE on 0. It runs after the RR flag checks (`0x1042`, `0x10C0`), the trapped check and the Sky Drop check, before the first switch check. Radical Red only; CFRU does not have it. [HYPOTHESIS]
- **Evidence:** a position where the enemy had a reason to switch, replayed 100 times with random seeds: 77 switches, 23 stays. In every stay no switch check ran, and recomputing the roll from each run's `Random2` state (`tools/mgba/check_random2.py`) matched all 100 runs.

## 3. The AI's randomness is a fixed formula, not true randomness [TESTED]

The AI's coin flips traced so far (the 25% switch skip, switch check rolls, the Speed-drop coin, ties between moves or switch-ins) come from `Random2`. At least one does not: the "good idea to boost" check (`0x090C3C64`) uses the main generator `Random` (`0x08044EC8`, state `0x03005000`, `state * 0x41C64E6D + 0x6073`).

- **Code:** `Random2` `0x0808322C`: `state = state * 0x41C64E6D + 0x3039`, returns `state >> 16`. The state is at `0x020386D0`, which in vanilla FireRed is the wild encounter generator (`sWildEncounterData`); RR's AI uses the same one. It only advances when something calls it (wild encounter checks while walking, and the AI's own calculations). [HYPOTHESIS]
- **Evidence:** loading a savestate and waiting 0, 7 or 14 frames before acting gave the same `Random2` state at the decision and the same decision. Changing only the state changed the decision as the formula predicts (rule 2).
- **Practical meaning:** the same savestate gave the same AI decision every time we tried it. In normal play it is unpredictable, because every step and every earlier battle moves the state. A script can read `0x020386D0` and compute the AI's rolls before it makes them.

## 4. Absorb switch: a party member that absorbs your predicted move comes in [TESTED]

When the switch checks run (the 75% in rule 2), the first check is whether a party member has an ability that absorbs the move the AI predicts you will use (Volt Absorb, Water Absorb, Storm Drain, Flash Fire, ...). If one does, that Pokemon comes in, even when another party member has a better switch-in score. The scores only set the order in which party members are tested (best, second best, then the rest in party order); the first one that absorbs the move wins.

- **Code:** first block of ShouldSwitch (entered at `0x090D831C`). It tries the scorer's best Pokemon, then the second best, then every other party slot in order; the RR helper `0x093508B0` accepts the first with a matching ability. Same idea as CFRU's `FindMonThatAbsorbsOpponentsMove`. [HYPOTHESIS]
- **Evidence:** against a Pokemon whose attacks were Water moves, the enemy switched to its party member that can have Storm Drain, although another party member had the best switch-in score (31 against 17). The viewer showed the absorb check as the reason and the slot as chosen by that check.
- **Bench damage cache bug (rule 14):** the best / second best order this check walks comes from switch-in scores that never count the bench Pokemon's damage.
- **Not yet tested:** the 50% skip in singles when your Pokemon is not predicted to be an attacker, and the skip right after a switch-in (both [HYPOTHESIS]).

## 5. Ties are broken at random [VERIFIED]

When two or more moves share the highest score, the AI picks one of them at random with equal chances.

- **Code:** move choice `0x090C82C0` collects the slots with the top score and picks `list[Random2() % count]` (`__modsi3` at `0x09000438`). [HYPOTHESIS]
- **Evidence:** in replays where a damaging move tied a status move at the top score (105), each was chosen 6 times out of 12. In replays without the tie, the higher-scored move was chosen every time (11 of 11).
- **Related [VERIFIED]:** switch-in candidates with equal scores are not an even pick. The scorer `0x090D7168` walks the party in order and a later equal score takes over on a 50% flip, so later party slots are favored. Ties are common because of the bench damage cache bug (rule 14): offense never separates candidates.

## 6. Speed-lowering attacks get +3 on a coin flip (singles) [VERIFIED]

In single battles, an attacking move whose side effect lowers your Speed (Bulldoze, Rock Tomb, Icy Wind, Mud Shot, ...) gets +3 on a 50% coin flip, when lowering your Speed is useful to the AI. +3 lifts it above the +2 the strongest move gets. Radical Red added the coin flip; in CFRU the +3 is always given.

- **Conditions** ([HYPOTHESIS], same as CFRU's `EFFECT_SPEED_DOWN_HIT` case and `GoodIdeaToLowerSpeed`): the Speed drop happens at least 50% of the time (`0x090DB220`, doubled by Serene Grace), your Pokemon is not behind a Substitute the move cannot hit through (`0x09075B98`), the AI cannot KO you first, the AI is not faster than you, and your ability does not block the drop (Contrary, Clear Body and similar) (`0x090E006C`).
- **Code:** Positives, assembly `0x090D29D0`-`0x090D2A6A`: after the conditions, `Random2() % 2` (`0x090D2A4C`-`0x090D2A5C`); on 0, `+3` via `0x090E1380` at `0x090D2A62`. [HYPOTHESIS]
- **Evidence:** replays where the AI stayed in with two Speed-lowering attacks, logging the coin at `0x090D2A5A` (`RR_TEST_TRACE=090D2A5A:r0 tools/mgba/run_repeat_test.sh ...`): in 26 of 26 move scorings, coin 0 gave +3 and coin 1 gave nothing (Bulldoze 105 or 102, Rock Tomb 103 or 100).
- **Side note:** the AI's prediction pass runs the same scoring first, so it uses up `Random2` rolls before the real choice.

## 7. How a damaging move is scored: KO bonus, else strongest-move bonus (singles) [VERIFIED]

For each damaging move the AI gives at most one of these, checked in this order:

1. **KO and goes first:** +9.
2. **KO but goes second** ("slow KO"), when the AI has no Protect, you are not predicted to switch, and you would not faint on your own anyway: a bonus set by the AI's role (setup status sweeper +8; the other roles 3 to 9, see `IncreaseViabilityForSlowKOMove` in CFRU `ai_advanced.c`).
3. **Otherwise, its strongest move:** +2 (a role-based 4 to 8 instead if it KOs in one hit and nothing else changed its score).

Side-effect bonuses such as rule 6's Speed drop come on top.

- **Code:** Positives, the KO checks around `0x090D66DE`-`0x090D67DA`; slow-KO bonus `0x090C69F4` (role switch, `+8` at `0x090C6A28`), called from `0x090D67DA`; strongest move `IsStrongestMove` `0x090DFE00`, `+2` set at `0x090D692A` and added at `0x090D67A6`. Same as CFRU's `DamageMoveViabilityIncrease`. [HYPOTHESIS]
- **Evidence:** traced score changes over several turns: a move that KOs while the AI moves second got +8 (role 3), and once your new Pokemon resisted it, that move got nothing and the AI's strongest other move got +2.
- **Also seen in a full traced battle:** +9 for a KO that goes first (Pin Missile, Bullet Seed, Psybeam, AncientPower, all added at `0x090D67A6`), and the slow-KO bonus +6 for a setup stats sweeper. **Not yet tested:** the other roles' slow-KO amounts.

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

  **Good idea to boost** (`0x090C3C64`, singles, [HYPOTHESIS]): no if your ability ignores its boosts (unless it has a move that gets around that). It needs the AI not badly poisoned (unless above 75% HP or with a Poison Heal-type ability). It needs you to have no way to undo the boost (Roar, Whirlwind, Haze, Clear Smog, Dragon Tail and similar, unless they would fail on it) and no Encore-type move, unless you cannot 2HKO it; a 50% coin from the main generator `Random` skips these two checks. Then, if its move cannot KO you: yes when you are about to switch or cannot act, or for Speed when it is below +3 and you cannot KO it, or when you cannot 2HKO it and the stat is below +4. If its move can KO you: yes only in narrow cases, with the stat below +3.
- **a KO that goes second** (rule 7), `0x090C69F4`, jump table at `0x090C6A12`: pure attacker and setup status sweeper +8; setup stats sweeper +8 if knocking out your last Pokemon is the better play (`0x090C3B48`), else +6; stall and phazing support 9 or 8; Baton Pass support 9, 8 or 3; cleric 9, 7 or 6; screens 9 or 6; hazard setter 9, 6 or 3 (the lower values when you cannot 2HKO it). Same as CFRU.

So the role decides close calls between a status or setup move and an attack. Example: when it cannot KO, a setup status sweeper's Stockpile (105) beats its strongest attack (102), while a pure attacker's Stockpile would stay at 100 and it would attack.

- **Code:** role computed by `0x090C4618` (CFRU `PredictBankFightingStyle`/`PredictFightingStyle`, singles part `0x090C40C4`), cached per battler at `gNewBS+0x888` by `GetBankFightingStyle` `0x090C46DC`, recomputed each turn. [HYPOTHESIS]
- **Evidence:** a full traced battle: 2 attacks plus status moves (Hippopotas: Bulldoze, Rock Tomb, Toxic, Slack Off; Lileep: Stockpile, Recover, Hidden Power, Mega Drain) gave setup status sweeper; 3 attacks plus Power-Up Punch (Cacnea) gave setup stats sweeper; 4 attacks (Lunatone) gave pure attacker. The role was recomputed every turn and never changed for the same Pokemon. The slow-KO bonus was +8 for the setup status sweeper and +6 for the setup stats sweeper.

## 9. A move that would have no effect gets -15 [VERIFIED]

If the AI's type check says the move would miss outright, have no effect or fail against you (for example an Electric move into a Ground type, a Psychic move into a Dark type), the move gets -15.

- **Code:** Negatives `0x090CB2E0`-`0x090CB2F8`: type check `0x090838A4`, result `& 0x29` (missed, no effect, failed) gives -15. [HYPOTHESIS]
- **Evidence:** in a traced battle, ThunderPunch against a Ground-type and Psybeam against a Dark-type each got -15 on every turn they were scored.

## 10. "Who goes first" ignores your priority advantage [VERIFIED]

When the AI checks whether its move hits before yours, it compares against the move it predicts you will use. Its own higher priority counts; your higher priority does not. If your move has higher priority, the AI still decides by Speed. Example: its Pin Missile against your predicted Fake Out (+3) counted as going first because it was faster, and got the +9 "KO, goes first" bonus.

- **Code:** MoveWouldHitFirst `0x090DA062`: priorities from `0x0906EFC0`; `cmp r7,r0; ble` at `0x090DA0A6` sends "equal **or lower**" to the bracket check (`0x0906F140`, quick-claw style) and then Speed (`0x0906F284`, faster strictly wins, Trick Room swaps). [HYPOTHESIS]
- **Evidence:** traced in game: AI priority 0, your predicted move priority 3, Speeds 40 vs 29, result "goes first".

## 11. The AI's Speed includes weather abilities [VERIFIED]

The AI's Speed comparison uses RR's Speed calculation: stat stages, and x2 for Sand Rush in sandstorm, Swift Swim in rain, Chlorophyll in sun and Slush Rush in hail (also Tailwind, paralysis, Quick Feet).

- **Code:** `0x0906F284`, weather abilities in `0x0906E320` (Sand Rush `0x7C` with weather `0x18`, Swift Swim `0x21`, Chlorophyll `0x22`, Slush Rush `0xAB`). [HYPOTHESIS]
- **Evidence:** traced in game: a Sand Rush Pokemon with 20 Speed was compared as 40 in sandstorm.

## 12. Toxic and other poison moves get -10 if you cannot be poisoned [VERIFIED]

- **Code:** Negatives `0x090CB186`-`0x090CB1C2`: -10 if the move would have no effect, if you cannot be poisoned (`0x09076380`: Immunity, Poison or Steel type unless the AI has Corrosion, already statused), or if a Substitute blocks it. [HYPOTHESIS]
- **Evidence:** Toxic against a Poison-type Pokemon got -10 and no status bonus on every turn.

## 13. When a stat boost counts as a good idea [VERIFIED]

Stat-boosting moves (Swords Dance, Power-Up Punch, Stockpile, ...) only get their role bonus when boosting is a good idea:

- never if you have a move that undoes boosts (Roar, Whirlwind, Haze, Clear Smog and similar), except on a 50% coin from the main `Random`;
- if the AI moves first: only if you cannot KO it, counting the damage it takes at the end of the turn (weather, poison, ...), and only while that stat is below +3;
- if it moves second: only if you cannot 2HKO it, and only while that stat is below +4.

- **Code:** `0x090C3C64` (with `0x090E031C` for "you can KO it, including end-of-turn damage" and `0x090DADF8` for that damage, cached at `gNewBS+0x810`). [HYPOTHESIS]
- **Evidence:** in two traced battles every stat-boost score matched these conditions: no bonus against a Pokemon with Roar, none once Attack reached +3, bonus restored when sandstorm damage did not count (the Pokemon was immune to it).

## 14. The bench damage cache bug: switch-ins do not count the bench Pokemon's damage (singles and doubles) [OBSERVED]

When the AI picks which Pokemon to send in (after a faint, a forced switch, or a voluntary switch that uses the best score), it appears to score each bench Pokemon on Speed and defense only. In every switch-in we logged it treated every bench Pokemon as dealing 0 damage to you, so the KO (+31), 2HKO (+2) and priority-KO (+8) credit never appeared. Equal defensive scores then end in the scorer's 50% coin flip (rule 5).

What still counts: outspeeds +14, resists all your moves +17, walls your attack stats +2, you can 2HKO it -1, you can KO it (large penalty).

- **Code:** the scorer `0x090D7168` adds +31 when the bench Pokemon can KO (`0x090DAA78` -> `0x090DA9D0`) and +2 when its stored best damage (`gNewBS+0x6F0`) is at least half your HP. Both take their damage from `0x090DA8A4`, which only calculates when its cache slot holds `0xFFFFFFFF` and otherwise returns the stored value. The cache is u32 per move at `gNewBS + 0x3F0 + (((side*6 + slot)*4 + foe)*4 + move)*4`. No code found writes `0xFFFFFFFF` to that range; `ClearCachedAIData` `0x090C8BA4` resets the other AI caches (`+0x2F0`, `+0x22E`, `+0x810`, `+0x820`, ...) but not this one. Where the zeros come from (likely the zeroed allocation of `gNewBS` at battle start) is not confirmed. [HYPOTHESIS]
- **Evidence (2026-10-24):** the viewer prints the raw cache for every party slot at each switch-in. In four untouched battles every value was 0, including Togedemaru, whose Zippy Zap did 61 to Azumarill on its first turn out, and no bench Pokemon in about 400 logged slot rows ever had the KO (0x01) or 2HKO (0x10) flag. Then the same Politoed battle was replayed with the viewer's experiment switch (`tools/mgba/logs/reset_bench_cache`) setting the cache to `0xFFFFFFFF` before each scorer run: RR filled it with real damage (e.g. Toxicroak 97 against 97 HP), the KO and 2HKO flags and points appeared (Toxicroak 31 -> 62), and the choice changed at the same moment (Toxicroak switched to Starmie, 44 with "KO foe", instead of Mantine, 31). Faint replacements in that run also got KO credit (Ludicolo 30, Toxicroak 52 with revenge kill). Doubles: every logged doubles switch-in (19 on 2026-10-25) showed `0/0/0/0` against both foes (S1).

## 15. Last Resort gets -10 until it can be used (singles) [VERIFIED]

- **Code:** Negatives `0x090CF83E`: -10 unless `0x0906CAD4` passes: every other move it knows was used since it came in (one bit per move slot at `gNewBS+0x6D+battler`), and it knows at least one other move (Last Resort alone always fails). [HYPOTHESIS]
- **Evidence:** Komala (Sleep Talk, Last Resort) scored Last Resort 99/98/92 on its first turn out (its normal score minus 10) and used Sleep Talk; from the next turn Last Resort scored normally (102, 108, 109). Seen in three playthroughs; Eevee showed the same -10 earlier.

## 16. U-turn, Volt Switch and Flip Turn: the pivot check (singles) [VERIFIED]

- **Code:** Positives `0x090D2F60` calls ShouldPivot `0x090C5704`. Result 0 (do not pivot): -9, and if the move was the strongest, the strongest-move bonus is recalculated without it (`0x090DE4EC`). Result 2 (pivot): a bonus by role from jump table `0x090C69BE`: +3 pure attacker or hazard setter, +9 setup sweepers, stall and Baton Pass, +7 cleric and screens, +4 phazer. Result 3 (pivot now, set by the switch logic at `gNewBS+0x1C5`): +9. Result 1 (can pivot): no change; this is what it returns when it has no Pokemon to switch to. ShouldPivot reads RR's KO caches (`gNewBS+0x820` CanKnockOut, `+0x830` Can2HKO) and the best switch-in's flags. [HYPOTHESIS]
- **Evidence:** Togedemaru (pure attacker): U-turn 91 (-9) on healthy turns, 103 (+3) at 24% HP against Clodsire (it then pivoted to Komala), 100 or 102 once it was the last Pokemon. The model with this check matched the U-turn score on all 4 replay turns where it ran (91, 91, 91, 100).

## Doubles: move selection

How each enemy picks a move and a target in a double battle. Evidence is the viewer's per-target logs (`tools/mgba/logs/`, 2026-10-24 and 2026-10-25) and repeat tests on copies of the user's savestate with a fresh `Random2` seed per run.

### D1. Every move is scored against every other battler, then the best target wins [TESTED]

The AI runs its scripts once per battler: both foes and its own partner (`0x090C82C0`, doubles branch). Moves aimed at the partner are scored too (Sleep Powder on the partner scored 60). Partner targets below 101 are dropped. The two enemies decide in Speed order, faster first, so the slower one can react to the faster one's chosen move and target. **Evidence:** Boltund (Speed 110) decided before Ambipom (105), Ambipom before Mr. Mime (93) and Granbull (47).

### D2. Damaging moves score by "doubles damage points" and the role table [TESTED]

For each target, `0x090E03C4` scores every damaging move: +4 if it hits a foe, +2 more if it KOs, +1 if it is the strongest move against that foe; with two foes alive, -3 if it does under 1/4 of the foe's max HP, -2 if under 1/3. A spread move adds its points for each foe it hits (and loses 3 for hitting the partner). Only the single best move per target keeps its points (cached at `gNewBS+0x7B0`, points at `+0x7D0`). The total is turned into a score bonus by the role table `0x093504B0` (`0x090C6E5C`):

| Points | All-Out Attacker | Setup Attacker |
|---|---|---|
| 1-4 | +9 | +4 |
| 5 (hit + strongest) | +10 | +9 |
| 6-7 (hit + KO) | +11 | +11 |
| 10 (spread, strongest on both) | +16 | +15 |

- **Evidence:** +10 for the strongest move per target (Amaura, Jigglypuff, Plusle, Electrike, Snover, Boltund...), +11 for a KO (Boltund's Thunder Fang into Gyarados), +16 for spread moves strongest on both foes (Electroweb, Bulldoze), and Butterfree's +9/+11. Butterfree has exactly 3 attacking moves, which makes it a Setup Attacker under RR's "exactly 3" rule (`0x090C4574`).
- **Utility role:** Perrserker's Iron Head scored only +1 (Utility row: 5 points = +1). Its role assignment in `0x090C40C4` is not checked yet.

### D3. A foe the partner already KOs is worth nothing [TESTED]

If the partner's chosen move KOs a foe, that foe counts as "handled" and the second enemy gets no damage points against it (`0x090E03C4`). **Evidence:** Mightyena set to 30 HP, where Ambipom's Fake Out alone KOs it: Mr. Mime's Freeze-Dry into Mightyena dropped to 100 and Mr. Mime picked Psyshock into Emboar in 20 of 20 runs.

### D4. Moves with no effect get -30 [OBSERVED]

Psyshock into Mightyena (Dark), Thunder Fang and Shock Wave into Clodsire (Ground) all scored 70. Thunder Fang into Lanturn (Volt Absorb) scored 60. Singles gives -15 (rule 9). CFRU doubles every "avoid" penalty in double battles, which would explain -30 (and -40 for an absorbing ability, CFRU's -20 doubled), but the spot in RR's code is not found yet.

### D5. Fake Out goes to the bigger threat on the first turn [TESTED]

`0x090C67A4`: on the user's first turn, if the target can flinch, Fake Out gets +15 (All-Out or Setup Attacker), +17 (Trick Room or team support roles) or +19 (Utility, Phazing). It gets -1 against a foe whose partner can KO more of the AI's Pokemon (counted with RR's CanKnockOut `0x090DFED4`), so it goes to the foe that threatens the AI's team more. The code also stops two enemies from Fake Outing the same foe (not seen yet, [HYPOTHESIS]). After the first turn Fake Out scored 80 (-20).

- **Evidence:** Ambipom: Fake Out into Mightyena 115, into Emboar 114 (Mightyena can KO Mr. Mime, Emboar can KO neither), so Fake Out into Mightyena in 100 of 100 runs. Perrserker's Fake Out scored 119 (Utility). Fake Out scored 80 on every later turn.

### D6. Equal top scores on two targets: the tie-break [TESTED]

When two targets tie for the best score, `0x090C82C0` decides in this order (for enemies with a doubles attacker role, `0x090C470C`/`0x090C4744`/`0x090C478C`):

1. **More KOs wins** (`0x090C7330`). This counts a KO together with the partner's hit when the partner already chose its move, targets the same foe (or uses a spread move) and goes first.
2. **If both hits do at least 50% of the target's max HP:** prefer the foe that can KO the attacker.
3. **Otherwise a 25% roll** (`Random2 & 3 == 0`): if it hits, the target taking the higher % of its max HP wins (`0x090C7298`); if it misses, a random pick among the tied targets.

So without a KO difference the harder-hit target is picked about 62.5% of the time (25% + 75% x 1/2).

- **Evidence:** Mr. Mime, Freeze-Dry into Mightyena (39%) vs Psyshock into Emboar (69%), both 110: Emboar 34 of 50. With a Payapa Berry on Emboar (33%): Emboar 20 of 50. A trace of the roll (`0x090C84B8`) and the damage % (`0x090C8598`/`0x090C8686`) over the same 50 seeds showed the roll hit in 14 runs, each one picking the higher %, and the berry flipped exactly those 14. With Mightyena at 60 HP (Fake Out + Freeze-Dry KO): Mightyena in 20 of 20 runs. `Random2` is a fixed formula, so from one savestate with the same inputs the pick was the same every time (3 of 3 runs without reseeding).

## Doubles: post-KO switch-in

How the AI picks a replacement after a faint in a double battle. Same scorer as singles (`0x090D7168`), run against each live foe and summed. The doubles switch-in model in `tools/mgba/rr_model.lua` follows these rules and matched RR's score for every party slot in the 19 doubles switch-ins logged on 2026-10-25, all from one trainer fight replayed several times and one earlier gauntlet.

### S1. Each foe is scored separately and the results add up [VERIFIED]

Per live foe:

- **Speed:** +14 if the candidate is at least as fast (ties count) as that foe, using the Speed the AI uses (stages, paralysis, weather abilities). Being faster than both foes is worth +28.
- **Offense:** +31 if it can KO that foe, +2 if it can 2HKO it. 0 in every doubles switch-in so far, because the bench damage cache read 0 (rule 14; every logged doubles switch-in showed `0/0/0/0` against both foes).
- **Defense with both foes alive:** type matchups only, no damage calculation (`0x09083ABC`). Any super-effective damaging move from that foe: -1 (the score never goes below 0). Otherwise, if none of its damaging moves hits neutrally (all resisted or immune): +17 "resists all". Otherwise +2 "walls" when the candidate's Defense beats the foe's boosted Attack (if the foe has a physical move) and its Sp. Def beats the foe's boosted Sp. Atk (if it has a special move).

- **Evidence:** Boltund 30 = +14 +14 (faster than Emboar and Azumarill) +2 (walls Azumarill); Boltund 27 = +14 +14 -1 (Gyarados' Bulldoze); Perrserker 16 = vs Emboar first: slower, -1 for Heat Crash while the score was still 0, so nothing lost; then vs Azumarill +14 (Speed tie 52 vs 52) +2 (walls); Granbull 0 (slower than both, hit super-effectively).

### S2. Which Pokemon can be picked [VERIFIED for ties, HYPOTHESIS for the partner's slot]

Not the two Pokemon on the field, not a slot the partner already picked this turn (`gBattleStruct+0x5C+battler`; both enemies fainting at once has not happened in a logged fight yet), not fainted. Equal scores: the scorer walks the party in order and a later slot takes over on a 50% `Random2` flip (rule 5), so when everyone scores 0 the pick is a coin flip between the healthy ones.

### S3. Your last Pokemon: damage-based, and "you KO it" is only -1 [HYPOTHESIS]

The type-only defense in S1 applies while your party has more than one usable Pokemon. When you are down to exactly one (`0x09073B6A` counts party slots with a species, not an egg, HP above 0), the defense part uses damage like singles, but a candidate you can KO only loses 1 point (the doubles branch at `0x090D7A3C` skips the singles -39/-15 and the "faints" flag). Not seen in a logged battle yet. With one of your Pokemon on the field but more in your party, the scorer still uses type matchups, against that one foe.

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
