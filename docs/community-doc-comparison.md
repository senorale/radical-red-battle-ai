# Community AI Doc vs ROM Findings

As of 2026-10-25. Compares the community Radical Red AI doc ([Google Doc](https://docs.google.com/document/d/1GLQTaXEHOPN5i-Cm6GYZYdwyszPhnd0ND9ChLO7Mp3s/edit?tab=t.0), credited to Cam, Pengu, Sarqx, Byonemil, Ssataei, Apecio, 3Plates and Zen1th) with what we found in the Radical Red 4.1 ROM. That doc says it is mostly hypothesis from player observation. Our findings come from decompiling the ROM. Details and addresses are in `docs/ai-notes.md`; the player guide starts at `docs/ai-guide.md`.

## Summary

- **Most of the community doc holds up.** Its switch conditions and doubles priority tables match the code closely, which makes sense because they appear to come from CFRU/Unbound source.
- **3 contradictions** where the code says something different (section 1), one of them minor.
- **The community doc was right about switch-in KO points**, against our first code reading: the KO code exists but never fires in game (section 1, verified).
- **1 claim matching the ROM code exactly that we had wrong** (the anti-switch counter, section 2).
- **Several important behaviors are missing** from the community doc (section 4).

Status key:

| Status | Meaning |
|---|---|
| Contradicted | The ROM code does something different. |
| Matches ROM code | Checked in the Radical Red code and it matches. |
| Consistent (CFRU) | Matches CFRU source; the RR function exists but this detail was not line-checked. |
| Not checked | We did not check it. |

## 1. Contradictions

| Topic | Community doc says | ROM shows | Evidence |
|---|---|---|---|
| Faint penalties on switch-ins | "Faints to move: -big" | Two different values: **-39** if the switch-in is slower and gets KOd, **-15** if it is faster but cannot KO you. | `0x090D7168` subtracts `0x27` and `0x0F` |
| "Only bad moves left" switch: who can come in | New switch must wall or resist; "outspeed isn't good enough". | Outspeeding **is** accepted. The check is Outspeeds OR Walls OR Resists-all (mask `0x4A`), plus "your predicted move won't hit it too hard". | `ShouldSwitch` at `0x090D824C` tests `flags & 0x4A` |
| "Walls foe" definition | AI's Def must be greater than or equal to your Atk (and SpD vs SpA). | **Strictly greater**, and it compares against your **stat-stage-modified** Atk/SpA. Equal stats do not count as walling, and your boosts make walling harder. | `0x090D7168`: no wall if Def <= stage-modified Atk (or SpD <= SpA) |

The last row is a minor wording point, but it can flip a switch-in decision when stats are close.

**Correction (2026-10-24, verified in game):** we first listed "kill flags are gone" as a contradiction, because the code still has the +31 KO / +8 revenge kill / +2 2HKO rules (`0x090D7168`, KO check `0x090DAA78` -> `0x090DA9D0` -> `0x090DA8A4`). In practice the community doc is right because of the bench damage cache bug: those rules read the switch-in's damage from a cache that is never reset, so every benched Pokemon looks like it does 0 damage and the KO points never fire. Resetting the cache by hand made them appear and changed the pick. See `docs/findings.md` rule 14.

## 2. Matches exactly (and corrected our own guide)

| Topic | Community doc says | ROM shows |
|---|---|---|
| Anti-switch ("Cheat AI") counter | +3 per switch, -1 per turn, never below 0, reset when a mon faints. 25% at 9+, 33% at 12+, 50% at 16+. | **Matches.** +3 at `0x090C02BE`, -1 per turn in the end-turn loop at `0x090911EE`, reset on faint at `0x0909EA9A`, thresholds in `0x090C8CA4`. |

Extra details the community doc does not mention:

- It only runs in **Hardcore Mode** (flag `0x1034`) and never in puzzle/trial battles (flag `0x1042`).
- The +3 only applies if the AI side did not also switch that turn.
- Switching **straight back** to the Pokemon you just left **always** triggers it, regardless of the counter.
- The roll uses the counter including the switch you just made, so the 4th switch in 4 turns is the first that can trigger.
- When it triggers, the AI fully re-picks its move and target against your new Pokemon (never into Pursuit). Not if you were forced out by Yawn.

## 3. Section-by-section check

### Switching functions

| Community section | Status | Notes |
|---|---|---|
| Hard Switch ("this is just Unbound AI") | Not checked | Not a separate function in CFRU or RR. Closest match is ShouldSwitchToAvoidDeath. |
| ShouldSwitchIfOnlyBadMovesLeft | **Contradicted** (switch-in rule) | See section 1. Rest of the criteria not line-checked. |
| ShouldSwitchToAvoidDeath | Consistent (CFRU) | Slower or dies to priority, no Destiny Bond, paralyzed not below 33%, hazards under 33%, HP above 20% unless the switch-in has a perfect score. The community doc says the 20% exception needs "outspeed + resist all"; CFRU requires the maximum switch score (70), which also needs KO and revenge-kill points. |
| ShouldSaveSweeperForLater | Consistent (CFRU) | Including the 25% chance (if the AI can 2HKO you) vs 50% otherwise, the Destiny Bond and Choice Lock cases. |
| ShouldSwitchWhenOffensiveStatsAreLow | Consistent (CFRU) | -3 thresholds, sweeper definition and accuracy rule all match. |
| SemiInvulnerableTroll / CanStopLockedMove ("doubles only? idk") | Consistent (CFRU), clarifies | They run in **singles** too. In doubles they are effectively off: they only run when the AI has one Pokemon left, and then it has nothing to switch to. Type chart only, as the community doc guessed. |
| IsTakingAnnoyingSecondaryDamage | Consistent (CFRU) | Curse, lost Poison Heal, Toxic 6+ turns: switch. Leech Seed: 25%. Hazards under 25%. |
| ShouldSwitchWhenYawned | Consistent (CFRU), clarifies | The "new mon must outspeed and OHKO" requirement only applies when Sleep Clause would let the AI's mon be slept. Otherwise it switches without that requirement. |
| ShouldSwitchWhileAsleep | Consistent (CFRU) | 50% normally, 25% if it has +2 Atk/SpA/Spe or +3 evasion. The "doesn't check if it can use the boosted stat" note is correct. |
| FindMonThatAbsorbsOpponentsMove | Consistent (CFRU) | All listed exceptions match, including "previous prediction was wrong" and Mold Breaker. Random points match in the ROM. |

### Move selection

| Community section | Status | Notes |
|---|---|---|
| Throat Chop bonus only if you have a sound move | Not checked | |
| Doubles role ladders (Trick Room, Utility, Phazer, Team Support, Setup Attacker, All-Out Attacker) | Matches ROM code | The damage-priority table in the ROM (`0x093504B0`) is byte-identical to CFRU, and the ladders match CFRU's strategy file. |

### Post-KO switch-in

| Community claim | Status |
|---|---|
| Resist all +17, Outspeeds +14, Walls +2, Takes half -1 | Matches ROM code |
| No KO points | **Matches in game** [OBSERVED]: the KO code exists but never fires (bench damage cache bug, `docs/findings.md` rule 14) |
| "In doubles the AI still looks for super effective and resisting all moves literally" | **Matches** [VERIFIED]: doubles uses type matchups instead of damage calcs while your party has more than one usable Pokemon (`docs/findings.md` S1) |

## 4. Not in the community doc

All of these were found in the ROM code (see `docs/ai-guide.md`, `docs/singles/move-or-switch.md`, `docs/singles/post-ko-switch-in.md`):

- **Every trainer uses the full smart AI.** The per-trainer AI setting is ignored. Wild Pokemon pick moves at random.
- **Difficulty modes use the same AI.** Normal, Restricted, Hardcore and Easy share the same decision logic; the only difference is Hardcore's anti-switch rule.
- **Trainers never use items.**
- **On 25% of turns the AI skips all switch logic.**
- **Damage assumptions:** 93% roll (9th of 16) for the active Pokemon. The 96% roll for benched Pokemon in the code never matters for their own damage (it is never calculated, rule 14).
- **Move-scoring changes from CFRU:**
  - Taunt +8 when your mon has any status move.
  - Second Protect in a row has no penalty.
  - Counter/Mirror Coat have a random 50% penalty.
  - Sucker Punch depends on predicting you attack.
  - Thunder Wave is penalized against Rest users and when already faster.
  - No Explosion into an unused Protect.
  - No healing at full HP to stall.
  - Hazard "already set" check is skipped when you have 3 or fewer mons (singles).
  - Speed-lowering attacks and Smack Down bonuses are 50%.
- Puzzle/trial battles send Pokemon in fixed order and never switch.
- **How doubles actually picks moves and targets.** The community doc has the role priority ladders but not the rest of the doubles logic (all found in the ROM code, see `docs/doubles/moves-and-targets.md` and `docs/doubles/post-ko-switch-in.md`):
  - **How roles are assigned** from the moveset. Only All-Out, Setup and Trick Room Attackers count as "attackers".
  - **Only one damaging move per target gets the ladder bonus.** Its 0 to 12 score is +4 per foe hit, +2 per KO, +1 if strongest, reduced for weak hits, and -3 for hitting its partner. Other attacks stay at base 100.
  - **Random tie-breaks** between equal moves, and between equal targets for non-attacker roles. Attackers prefer KOs, then threats, then most damage only 25% of the time (verified: `docs/findings.md` D6).
  - **Never targets its partner** below a score of 101. Ignores spread moves 75% of the time when you have Wide Guard.
  - **Speed-order partner coordination**: the slower AI mon accounts for its faster partner's chosen move and target.

## 5. Open questions for the community

- What flag `0x10C0` is (it blocks AI switching entirely when set).
- Which bosses use special battle IDs `0x10` / `0x12` (small hazard and ability exceptions).
- Live testing of the hazard re-use quirk would confirm the code reading in play.
