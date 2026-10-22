# Doubles: Post-KO Switch-In

How the Radical Red 4.1 AI picks which Pokemon to send in during a double battle. There is no separate doubles function: the singles scoring (`0x090D7168`, called from `OpponentHandleChoosePokemon` at `0x09068A28`) runs with doubles-only branches, which change the result a lot. For single battles see `../singles/post-ko-switch-in.md`. Read `../ai-guide.md` first for the tags and damage roll.

## 1. Scoring [ROM]

Each healthy benched Pokemon is scored **against each of your active Pokemon separately**, and the scores are **added together**. Highest total comes in.

| Trait (per Pokemon of yours) | Points |
|---|---|
| Can KO it | +31 |
| Outspeeds it (or has a priority move that KOs) | +14 |
| Revenge kill (priority KO, Moxie, trapping ability, Pursuit/Fell Stinger KO) | +8 |
| Resists or is immune to all its damaging moves | +17 |
| Walls it | +2 |
| Can 2HKO it (only checked if it cannot KO) | +2 |
| It would KO the switch-in, or has a super-effective move | **-1** |

Perfect score is 140 (70 against each of your two Pokemon). Examples: outspeeding both is +28, KOing both is +62.

Compared with singles, the big difference is the last row: a switch-in you would KO loses only 1 point, not -39 or -15.

## 2. How it judges each trait [ROM]

- **Its offense uses real damage calcs** with a 96% roll (the 12th of 16): "can KO" and "can 2HKO" are real calculations.
- **Your offense uses only the type chart**, unless you have just one Pokemon left in your whole party (then it uses damage calcs, but a KO still only costs 1 point). "Weak" means you have a super-effective damaging move against it. "Resists all" means you have no neutral or super-effective damaging moves against it.
- **Walls** still compares its Defense/Sp. Def against your stat-stage-boosted Attack/Sp. Atk (strictly greater), checked against each of your Pokemon.
- **Hazards count.** A Pokemon that would faint to hazards is never sent in.
- **Asleep Pokemon** are skipped unless they wake up this turn.

## 3. Tie-breaks, randomness and overrides [ROM]

- **Ties are always a coin flip.** Singles prefers the tied Pokemon that survives; doubles does not track that, so every tie is 50/50. The flip runs down the party in order, so with three tied the last one is favored (25% / 25% / 50%).
- **Other randomness:** none in the scoring itself. A move with a 50%+ crit chance gets a coin flip on whether the crit is counted, which can change "can KO".
- **Both AI Pokemon faint at once:** the first replacement takes the top pick, the second takes the runner-up.
- **Hazard removal:** if hazards are on its side, a Rapid Spin/Defog user that survives (or a grounded Poison type vs Toxic Spikes) is sent in instead (scored 142), unless the top pick already outspeeds and KOs or resists everything.
- **Not affected by the 25% switch skip.** That skip only applies to voluntary switching.

## 4. Practical takeaways

- **It sends in whatever outspeeds and hits your pair hardest.** Speed and KO power against both of your Pokemon dominate.
- **It barely cares if its switch-in survives.** Expect replacements that walk into your super-effective spread moves.
- **Type chart, not damage, for your attacks.** A neutral hit that would KO it is not counted against it at all.
- **Ties are common and random.** Two similar options are a straight coin flip.
