# Singles: Post-KO Switch-In

How the Radical Red 4.1 AI picks which Pokemon to send in during a single battle. The same scoring is used after one of its Pokemon faints, after a forced switch (U-turn, Dragon Tail, ...) and when it decides to switch out voluntarily (see `move-or-switch.md`). For double battles see `../doubles/post-ko-switch-in.md`. Read `../ai-guide.md` first for the tags and damage roll.

## 0. The bench damage cache bug: the switch-in's own damage never counts [OBSERVED]

The scorer has full offense rules (+31 if the switch-in can KO you, +2 if it can 2HKO you, +8 for a revenge kill), but they never fire in practice. They read the switch-in's damage from a cache that Radical Red never resets to "not computed", so every benched Pokemon looks like it does 0 damage to you. Shown live: resetting the cache by hand made the KO points appear and changed the AI's pick at the same moment. Details and evidence: `../findings.md` rule 14.

So in practice the AI picks its replacement on **Speed and how well it takes your hits**, not on how hard it hits you.

## 1. Scoring

Each healthy benched Pokemon is scored against your active Pokemon. Highest score comes in.

| Trait | Points | In practice |
|---|---|---|
| Outspeeds you (Speed ties count) | +14 | Live [VERIFIED] |
| Resists or is immune to all your damaging moves | +17 | Live [VERIFIED] |
| Walls you (see section 2) | +2 | Live [VERIFIED] |
| You 2HKO it | -1 | Live [VERIFIED] |
| You KO it and it is slower | -39 | Live [HYPOTHESIS] |
| You KO it, it is faster but cannot KO you | -15 | Live [HYPOTHESIS] |
| Can KO you | +31 | **Never fires** (rule 14) |
| Revenge kill (priority KO, Moxie, trapping ability, Pursuit/Fell Stinger KO) | +8 | **Never fires** (needs a KO) |
| Can 2HKO you (only checked if it cannot KO) | +2 | **Never fires** (rule 14) |

A score can't drop below 0. A Pokemon with no usable damaging move scores -1 (last resort).

Common totals in practice:

| Total | Meaning |
|---|---|
| 31 | Outspeeds and resists all your moves |
| 17 | Slower, resists all your moves |
| 16 | Outspeeds and walls you |
| 14 | Outspeeds |
| 13 | Outspeeds, you can 2HKO it |
| 2 | Slower, walls you |
| 0 | Slower and gets 2HKOd or KOd, or does nothing useful |

## 2. How it judges each trait [HYPOTHESIS]

- **Your damage to it** is a real damage calc. The damage roll assumed for benched Pokemon (96%, the 12th of 16, in `docs/ai-guide.md`) comes from older notes and is not verified.
- **Hazards count.** Its HP on entry is reduced by the hazard damage it would take. A Pokemon that would faint to hazards is never sent in.
- **Recovery counts.** Leftovers-style passive recovery and a pending Wish are added before checking whether you 2HKO it.
- **Your priority.** If you have a priority move that KOs it, it loses the "outspeeds" points.
- **Walls you.** Only checked when you neither KO nor 2HKO it and it does not resist all your moves. Its Defense must be **strictly greater** than your stat-stage-boosted Attack (if you have physical moves), and its Sp. Def strictly greater than your boosted Sp. Atk (if you have special moves). Equal stats do not count. Assembly `0x090D7AFC`-`0x090D7B6E`.
- **Asleep Pokemon** are skipped unless they wake up this turn.

## 3. Tie-breaks, randomness and overrides

- **Ties** [VERIFIED]: the scorer walks the party in order; a later Pokemon with an equal score replaces the current pick on a 50% `Random2` flip, so with three tied the last one is favored (25% / 25% / 50%). If one tied Pokemon gets KOd by you and the other does not, it picks the one that survives. Same savestate and same inputs always give the same flip.
- **Hazard removal** [HYPOTHESIS]: if hazards are on its side, a Pokemon that knows Rapid Spin or Defog and will not be KOd (or a grounded Poison type when Toxic Spikes are up) is sent in instead, unless the top pick already outspeeds and KOs or resists everything.
- **Puzzle/trial battles** [HYPOTHESIS]: no scoring. It sends Pokemon in party order.
- **Not affected by the 25% switch skip** [TESTED]. That skip only applies to voluntary switching.

## 4. Practical takeaways

- **Speed decides most replacements.** Anything faster than your active Pokemon gets +14, which beats almost everything except "resists all".
- **It does not pick the Pokemon that threatens you most.** A slow Pokemon that would OHKO you scores 0 to 2; a fast one that barely scratches you scores 14.
- **Resisting everything you have is the other big factor** (+17), and both together (31) is the best a switch-in can score in practice.
- **It does not respect your bench.** Scoring is only against your active Pokemon. Switching after it sends something in is the classic counter.
- **Lots of ties.** Two Pokemon that are both faster (or both slower) and take similar hits tie, and the later party slot wins half the time.
