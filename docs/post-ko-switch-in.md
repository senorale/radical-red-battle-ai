# Post-KO Switch-In

How the Radical Red 4.1 AI picks which Pokemon to send in. The same scoring is used after one of its Pokemon faints and when it decides to switch out voluntarily (see `move-or-switch.md`). Read `ai-guide.md` first for the tags and damage roll.

## 1. Scoring [ROM]

Each healthy benched Pokemon is scored against your active Pokemon. Highest score comes in.

| Trait | Points |
|---|---|
| Can KO you | +31 |
| Outspeeds you (or has a priority move that KOs) | +14 |
| Revenge kill (priority KO, Moxie, trapping ability, Pursuit/Fell Stinger KO) | +8 |
| Resists or is immune to all your damaging moves | +17 |
| Walls you (see section 2) | +2 |
| Can 2HKO you (only checked if it cannot KO) | +2 |
| You KO it and it is slower | -39 |
| You KO it, it is faster but cannot KO you | -15 |
| You 2HKO it | -1 |

Perfect score is 70 (KO + resists all + revenge kill + outspeeds). A score can't drop below 0. In doubles it scores each candidate against both of your Pokemon and adds the results (perfect score 140).

Common totals:

| Total | Meaning |
|---|---|
| 70 | KOs, outspeeds, revenge kill, resists all |
| 53 | KOs, outspeeds, revenge kill |
| 45 | KOs and outspeeds |
| 31 | KOs (or resists all and outspeeds) |
| 17 | Resists all |
| 14 | Outspeeds |
| 0 to 2 | Slower and gets KOd, or does nothing useful |

## 2. How it judges each trait [ROM]

- **Damage roll.** For benched Pokemon the AI assumes a **96% roll (the 12th of 16)** in both directions: its switch-in's damage to you, and your damage to its switch-in. That is more optimistic than the 93% it uses for active Pokemon.
- **Real damage calcs vs type chart.** Its own offense ("can KO", "can 2HKO") always uses real damage calcs. Your offense against its switch-in uses real damage calcs in singles; in doubles it uses only the type chart unless you have just one Pokemon left in your party (see section 4).
- **Hazards count.** Its HP on entry is reduced by the hazard damage it would take. A Pokemon that would faint to hazards is never sent in.
- **Recovery counts.** Leftovers-style passive recovery and a pending Wish are added before checking whether you 2HKO it.
- **Your priority.** If you have a priority move that KOs it, it loses the "outspeeds" points.
- **Walls you.** Only if you do not 2HKO or OHKO it, and its Defense is **strictly greater** than your stat-stage-boosted Attack (if you have physical moves), and its Sp. Def is strictly greater than your boosted Sp. Atk (if you have special moves). Equal stats do not count.
- **Asleep Pokemon** are skipped unless they wake up this turn.
- **No usable moves:** score is set to -1 (last resort).

## 3. Tie-breaks and overrides [ROM]

- **Ties:** if one tied Pokemon gets KOd by you and the other does not, it picks the one that survives. Otherwise it is a 50/50 coin flip.
- **Hazard removal:** if hazards are on its side, a Pokemon that knows Rapid Spin or Defog and will not be KOd (or a grounded Poison type when Toxic Spikes are up) is sent in instead, unless the top pick already outspeeds and KOs or resists everything.
- **Puzzle/trial battles:** no scoring. It sends Pokemon in party order.

## 4. Double battles [ROM]

The same function picks replacements in doubles (`OpponentHandleChoosePokemon` at `0x09068A28` calls the scoring at `0x090D7168`), with these differences:

- **Scored against both of your Pokemon, then added together.** Each trait is checked separately against each of your active Pokemon. Outspeeding both is +28, KOing both is +62, and so on. Perfect score is 140.
- **Its offense uses real damage calcs** (96% roll), same as singles.
- **Your offense uses only the type chart**, unless you have just one Pokemon left in your whole party. "Weak" means you have a super-effective move against it; "resists all" means you have no neutral or super-effective damaging moves.
- **Getting KOd barely matters.** A switch-in you would KO loses only **1 point** (not -39 / -15 as in singles). Being weak to one of your moves is also -1.
- **Walls** still uses its Defense/Sp. Def against your boosted Attack/Sp. Atk, checked per foe.
- **Hazard removal override** applies with a score of 142.
- **Both AI Pokemon faint at once:** the first replacement takes the top pick, the second takes the runner-up.
- **Not affected by the 25% switch skip.** That skip only applies to voluntary switching.

Practical meaning: in doubles it sends in whatever outspeeds and hits your two Pokemon hardest, and mostly ignores whether that Pokemon will survive the turn.

## 5. Practical takeaways

- **The biggest factor is "can it KO you".** If you are low, expect its strongest attacker against you, even a slow one.
- **It does not respect your bench.** Scoring is only against your active Pokemon. Switching after it sends something in is the classic counter.
- **Outspeeding is worth a lot (+14).** A fast Pokemon that can't KO you still beats a slow one that can't either.
- **Bulk does little on its own.** Walling is only +2. It prefers fast or resisting answers.
- **Its 96% roll is optimistic.** If its switch-in needs a high roll to KO you, it may still count it as a KO.
