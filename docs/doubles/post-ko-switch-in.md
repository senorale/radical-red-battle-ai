# Doubles: Post-KO Switch-In

How the Radical Red 4.1 AI picks which Pokemon to send in during a double battle. There is no separate doubles function: the singles scoring (`0x090D7168`, called from `OpponentHandleChoosePokemon` at `0x09068A28`) runs with doubles-only branches, which change the result a lot. For single battles see `../singles/post-ko-switch-in.md`. Read `../ai-guide.md` first for the tags.

> **Two separate flows** (`../findings.md`, "Switching: two separate flows"): a **mid-turn swap** first asks *should it switch?* (in doubles: `../findings.md` M1 to M3) and then *who comes in?*; a **post-KO replacement** only asks *who comes in?*. This doc is the *who comes in* part, shared by both flows. The two steps are separate code, not one chain: why it leaves does not change who it picks (worked example in `../findings.md`).

The verified rules, with evidence, are in `../findings.md` ("Doubles: post-KO switch-in", S1 to S3). The doubles switch-in model in `tools/mgba/rr_model.lua` follows them and matched RR's score for every party slot in all 19 logged doubles switch-ins.

> **Bench damage cache bug** (`../findings.md` rule 14): the scorer reads each benched Pokemon's damage against you from a cache (`gNewBS+0x3F0`) that Radical Red never resets to "not computed", so it always reads 0. The KO (+31), 2HKO (+2) and revenge-kill (+8) points therefore never fire, in singles and doubles. Shown live: resetting the cache by hand made the KO points appear and changed the pick.

## Overview with examples

Enemy B faints. Your X (Speed 62, has a Fire move and a Fighting move) and your Y (Speed 52, has a Fairy move, low Attack and Sp. Atk) are on the field. The AI's benched Pokemon are C, D and E. Each one is scored against X and against Y, and the two scores are added:

| Bench | vs your X | vs your Y | Total |
|---|---|---|---|
| C (Speed 110) | +14 faster; X hits it neutrally, no wall: 0 | +14 faster; +2 walls Y (its Def/SpD beat Y's Atk/SpA) | **30** |
| D (Speed 52, Steel) | slower; X's Fire move is super-effective: -1 (stays at 0) | Speed tie 52 = 52 counts: +14; +2 walls | **16** |
| E (Speed 47, Fairy) | slower; neutral hits, no wall: 0 | slower; Y's Fairy move is super-effective: -1 (floor 0) | **0** |

C comes in.

- **Its own damage does not count** (bench damage cache bug). If E could OHKO both X and Y, it still scores 0.
- **Typing counts only defensively.** A bench Pokemon F that resists every damaging move X and Y have but is slower than both scores 17 + 17 = **34** and beats the fast C (30).
- **Ties are coin flips.** Later, only D and E are left and both score 0: RR walks the party in order, D is the pick, then E (later slot) replaces it on a 50% flip. With three tied at 0 the last one gets 50%, the other two 25% each.
- **Excluded slots.** If Enemies A and B both faint the same turn, A's replacement takes C; B's replacement cannot take C and gets the next best (D).
- **Your last Pokemon** [HYPOTHESIS]. If X is the only usable Pokemon left in your whole party, the scorer uses real damage against X instead of types, but a candidate X would KO still only loses 1 point (singles: -39 or -15).

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

- **Its offense: never counted** [OBSERVED]. Same cache as singles (`../findings.md` rule 14); every doubles switch-in logged `0/0/0/0` against both foes.
- **Your offense: type chart only** [VERIFIED], while your party has more than one usable Pokemon. "Super-effective" means any of your damaging moves hits it super-effectively; "resists all" means none of them hits it neutrally or better.
- **Your last Pokemon** [HYPOTHESIS]: when your whole party is down to one usable Pokemon (`0x09073B6A`), it uses damage calcs instead, but a switch-in you would KO still loses only 1 point. Not seen in a logged battle yet.
- **Hazards count** [HYPOTHESIS]. A Pokemon that would faint to hazards is never sent in.
- **Asleep Pokemon** are skipped unless they wake up this turn [HYPOTHESIS].

## 3. Tie-breaks, randomness and overrides

- **Ties are a coin flip** [VERIFIED]: the scorer walks the party in order and a later equal score takes over on a 50% `Random2` flip, so with three tied the last one is favored (25% / 25% / 50%). With everyone at 0 the pick is a flip between the healthy ones.
- **Both AI Pokemon faint at once** [HYPOTHESIS]: the first replacement takes the top pick; the slot it picked is excluded for the second (`gBattleStruct+0x5C+battler`).
- **Hazard removal** [HYPOTHESIS]: if hazards are on its side, a Rapid Spin/Defog user that survives (or a grounded Poison type vs Toxic Spikes) is sent in instead, unless the top pick already outspeeds and KOs or resists everything.
- **Not affected by the 25% switch skip.** That skip only applies to voluntary switching.

## 4. Practical takeaways

- **Speed against both of your Pokemon decides most replacements.** Being faster than both is worth +28; nothing else except "resists all" comes close.
- **It ignores how hard the switch-in hits you.** A slow Pokemon that would OHKO your pair scores 0.
- **Typing matters only defensively.** Resisting all of one of your Pokemon's attacks is +17, walling it +2, being hit super-effectively -1. The -1 almost never changes the pick except in ties.
- **It barely cares if its switch-in survives.** Expect replacements that walk into your super-effective spread moves.
- **Ties are common and random.** Two slow Pokemon that both get hit super-effectively both score 0.
