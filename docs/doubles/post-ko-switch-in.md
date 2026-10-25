# Doubles: Post-KO Switch-In

How the Radical Red 4.1 AI picks which Pokemon to send in during a double battle. There is no separate doubles function: the singles scoring (`0x090D7168`, called from `OpponentHandleChoosePokemon` at `0x09068A28`) runs with doubles-only branches, which change the result a lot. For single battles see `../singles/post-ko-switch-in.md`. Read `../ai-guide.md` first for the tags.

The verified rules, with evidence, are in `../verified.md` ("Doubles: post-KO switch-in", S1 to S3). The doubles switch-in model in `tools/mgba/rr_model.lua` follows them and matched RR's score for every party slot in all 19 logged doubles switch-ins.

## 1. Scoring [VERIFIED]

Each healthy benched Pokemon is scored **against each of your active Pokemon separately**, and the scores are **added together**. Highest total comes in.

| Trait (per Pokemon of yours) | Points | In practice |
|---|---|---|
| Outspeeds it (Speed ties count; uses the AI's effective Speed: stages, paralysis, weather abilities) | +14 | Live |
| Resists or is immune to all its damaging moves | +17 | Live |
| Walls it (no super-effective move, some neutral hit, and its Def/SpD strictly above your boosted Atk/SpA) | +2 | Live |
| It has a super-effective damaging move (or, on your last Pokemon, would KO the switch-in) | **-1** | Live |
| Can KO it | +31 | **Never fires** (rule 14: bench damage reads as 0) |
| Revenge kill | +8 | **Never fires** |
| Can 2HKO it | +2 | **Never fires** |

The score never goes below 0. Outspeeding both of your Pokemon is +28, resisting everything both have is +34.

Examples from logged battles: Boltund 30 (+14 +14 faster than Emboar and Azumarill, +2 walls Azumarill); Boltund 27 (+14 +14, -1 for Gyarados' Bulldoze); Perrserker 16 (+14 Speed tie 52 vs 52 with Azumarill, +2 walls Azumarill, -1 for Emboar's Heat Crash); Granbull 0 (slower than both, hit super-effectively).

## 2. How it judges each trait

- **Its offense: never counted** [VERIFIED]. Same cache as singles (`../verified.md` rule 14); every doubles switch-in logged `0/0/0/0` against both foes.
- **Your offense: type chart only** [VERIFIED], while your party has more than one usable Pokemon. "Super-effective" means any of your damaging moves hits it super-effectively; "resists all" means none of them hits it neutrally or better.
- **Your last Pokemon** [ROM]: when your whole party is down to one usable Pokemon (`0x09073B6A`), it uses damage calcs instead, but a switch-in you would KO still loses only 1 point. Not seen in a logged battle yet.
- **Hazards count** [ROM]. A Pokemon that would faint to hazards is never sent in.
- **Asleep Pokemon** are skipped unless they wake up this turn [ROM].

## 3. Tie-breaks, randomness and overrides

- **Ties are a coin flip** [VERIFIED]: the scorer walks the party in order and a later equal score takes over on a 50% `Random2` flip, so with three tied the last one is favored (25% / 25% / 50%). With everyone at 0 the pick is a flip between the healthy ones.
- **Both AI Pokemon faint at once** [ROM]: the first replacement takes the top pick; the slot it picked is excluded for the second (`gBattleStruct+0x5C+battler`).
- **Hazard removal** [ROM]: if hazards are on its side, a Rapid Spin/Defog user that survives (or a grounded Poison type vs Toxic Spikes) is sent in instead, unless the top pick already outspeeds and KOs or resists everything.
- **Not affected by the 25% switch skip.** That skip only applies to voluntary switching.

## 4. Practical takeaways

- **Speed against both of your Pokemon decides most replacements.** Being faster than both is worth +28; nothing else except "resists all" comes close.
- **It ignores how hard the switch-in hits you.** A slow Pokemon that would OHKO your pair scores 0.
- **Typing matters only defensively.** Resisting all of one of your Pokemon's attacks is +17, walling it +2, being hit super-effectively -1. The -1 almost never changes the pick except in ties.
- **It barely cares if its switch-in survives.** Expect replacements that walk into your super-effective spread moves.
- **Ties are common and random.** Two slow Pokemon that both get hit super-effectively both score 0.
