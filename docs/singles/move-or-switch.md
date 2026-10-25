# Singles: Move or Switch

How the Radical Red 4.1 AI decides each turn in a single battle: attack, use a status move, or switch out. Read `../ai-guide.md` first for the tags ([HYPOTHESIS] / [HYPOTHESIS, CFRU]), the damage roll and what the AI knows about you.

## 1. Order of decisions each turn

1. **Switch check.** On 25% of turns the AI skips this entirely and will not switch no matter what. [HYPOTHESIS] Otherwise it runs the switch rules in section 4. Puzzle/trial battles never switch. [HYPOTHESIS]
2. **Pick a move** by score (sections 2 and 3). Trainers never use items. [HYPOTHESIS]
3. **Hardcore Mode only:** after you switch, it may re-pick its move (section 6). [HYPOTHESIS]

Every move starts at a score of 100. Rules add or subtract points. The highest score wins; ties are a random pick.

## 2. Attacking moves [HYPOTHESIS]

| Situation | Bonus |
|---|---|
| Move KOs you and goes first (accuracy 70+, or no accuracy booster, or the AI is about to die anyway) | **+9** |
| Skipped if | you are predicted to switch; you are predicted to use Sucker Punch (unless the AI is an attacker type or its move outspeeds); you used Destiny Bond (unless you would KO it anyway) |
| Move KOs but goes second, and the AI has no Protect | +3 to +9 depending on its role |
| You will KO the AI first, and it has a priority move that goes first | **+9** "desperation" (can repeat ~75% of the time after you attacked, ~25% after you used a status move) |
| Otherwise, its strongest move | **+2** (support roles get 4 to 8 if it KOs) |
| AI is frozen and has a thawing move | +10 |

Practical meaning: if it can kill you first, it almost always does. If it cannot kill, it usually just clicks its strongest move unless a status/setup rule scores higher.

## 3. Status and utility moves

Everything labeled "Radical Red" in this table is [HYPOTHESIS]. The base conditions (when it likes setup, sleep, Protect, recovery) come from CFRU helper functions whose call sites were found in the ROM but whose bodies were not line-checked, so treat them as [HYPOTHESIS, CFRU].

| Move type | When the AI likes it |
|---|---|
| **Taunt** | **+8 whenever your Pokemon has any usable status move** (Radical Red addition), plus more if you are predicted to use a status move or are a stall/support set. Expect Taunt a lot against setup and support mons. |
| **Protect** | When you can KO or 2HKO it and protecting helps: chip from Leftovers/poison/Leech Seed, Speed Boost or Moody, your Perish count, your Explosion, you coming down from Fly/Dig. Radical Red rules: a second Protect in a row has **no penalty**; a third gets -6. So double-Protect is common. Never Protects against Unseen Fist. |
| **Recovery** | When you can KO now but not after it heals, or (50%) you can 2HKO and the heal is bigger than its current HP. Never at full HP; heavily discouraged at 90%+. |
| **Setup (Swords Dance etc.)** | Only if you cannot KO it this turn (when it moves first) or cannot 2HKO it (when it moves second), and not into Unaware, and not into Sturdy/Sash when it cannot break them. Normally sets up to +2; up to +6 if you look passive (stall/support, did not attack last turn) or are predicted to switch. |
| **Sleep / Yawn** | Big bonus for setup and support roles (+7 to +9 with 80%+ accuracy). Not if it can just KO you. |
| **Paralysis (Thunder Wave etc.)** | Bonus if it would then outspeed you. Radical Red penalties: -5 if you know Rest, -2 if it is already faster. |
| **Will-O-Wisp** | +3 if you are predicted to KO it with a physical move, more if you are physical in general. |
| **Toxic** | Mild bonus (+1, +2 with Venoshock/Barb Barrage/Merciless). |
| **Encore** | When your last move (it moving first) or predicted move is a status move. |
| **Counter / Mirror Coat** | Radical Red adds a flat 50% chance of -10 every turn, so it uses them about half as often as it otherwise would. Never when you are predicted to use a status move. |
| **Sucker Punch** | Radical Red rule: only when it predicts you will attack and it would go first. -10 if it predicts a status move from you; 50% penalty if it predicts you switch. |
| **Explosion** | Only when no other move KOs and staying in does not win. Radical Red adds: never into a Protect you did not use last turn, never if you know Fly/Dig/etc. Never with Damp on field. |
| **U-turn / Volt Switch / Flip Turn** | [VERIFIED, `../findings.md` rule 16] RR's ShouldPivot (`0x090C5704`) gives one of: bad time to pivot **-9** (and the strongest-move +2 moves to its next best attack); good time to pivot, a bonus by role (+3 pure attacker or hazard setter, +9 setup/stall/Baton Pass roles, +7 cleric/screens, +4 phazer); pivot now (set by the switch logic) +9; no change when it has nothing to switch to. It pivots when you are predicted to switch, to break Sash/Sturdy/Multiscale, when it is about to be KOd, or into a teammate that resists or walls you. |
| **Last Resort** | [VERIFIED, rule 15] -10 until every other move it knows was used since it came in; -10 always if Last Resort is its only move. |
| **Pursuit** | +3 for attacker roles when you are predicted to switch. |
| **Fake Out** | [TESTED] First turn only, when flinching is useful: +8. After the first turn: -10. |
| **Destiny Bond** | When you will KO it (it is faster) or 2HKO it (it is slower). |
| **Entry hazards** | Bonus if any of your benched Pokemon would be hurt. Radical Red changes: if you have **3 or fewer** healthy Pokemon, the "already set" penalty is skipped, so a hazard setter can waste turns re-using Stealth Rock/Spikes. With 4+ mons, it avoids hazards 50% of the time if you have Rapid Spin, Defog or Magic Coat. |
| **Speed-lowering attacks (Icy Wind etc.)** | Small bonus, only 50% of the time (Radical Red). |

### Things the AI avoids (penalties) [HYPOTHESIS]

- Moves your ability blocks: Volt Absorb, Lightning Rod, Motor Drive, Water Absorb, Storm Drain, Dry Skin, Flash Fire, Sap Sipper, Soundproof, Bulletproof, Magic Bounce, Dazzling/Queenly Majesty vs priority, Clear Body vs stat drops, Contrary vs stat drops, and many newer immunity abilities.
- Moves that do nothing: type immunity or guaranteed miss (-15), powder vs Grass/Overcoat/Goggles, status into an already-statused or immune target, stat boosts at +6.
- Terrain: no sleep in Electric Terrain, no status in Misty Terrain, no priority into grounded targets in Psychic Terrain.
- Stat-drop moves that would trigger Defiant/Competitive; contact or type moves that trigger Justified, Rattled, Steam Engine.
- Prankster status into Dark types.
- Two-turn moves when you can Protect or KO it during the charge.

## 4. When it switches out [order from CFRU, presence found in ROM]

Only checked on 75% of turns. Never when trapped. The first matching rule wins:

1. **Absorb your predicted attack**: switches to a Flash Fire / Volt Absorb / Lightning Rod / Motor Drive / Water Absorb / Dry Skin / Storm Drain / Sap Sipper teammate. Not if it can KO you first, is boosted, or is behind a working Substitute. Less likely if it already did this.
2. Pass a pending Wish to a teammate below 50% HP.
3. Dodge your locked-in move (Outrage, or you coming down from Fly/Dig) with an immune or resisting teammate.
4. Perish Song about to end.
5. Facing Wonder Guard with no way to hurt it.
6. **Only bad moves left**, and a teammate that outspeeds, walls you or resists all your moves can come in without taking too much from your predicted move.
7. Natural Cure (statused, 50%+ HP) or Regenerator (50% or less HP, you would KO it).
8. About to fall asleep from Yawn (various exceptions).
9. Asleep: 50% chance to switch (25% if it has +2 Atk/SpA/Spe or +3 evasion).
10. Heavy residual damage: Leech Seed (25%), Curse, Nightmare, long Toxic.
11. **About to die**: you will KO it first, it is above 20% HP, and a teammate can come in immune, walls you, or outspeeds and KOs.
12. Attacking stat at -3 or worse.
13. **Save a sweeper**: an attacker that cannot KO you right now may switch to a teammate that outspeeds and KOs, or resists everything (partly random to stay unpredictable).

Which teammate comes in is decided by the same scoring as a post-KO switch-in, see `post-ko-switch-in.md`. That scoring never counts the teammate's own damage (the bench damage cache bug, `../findings.md` rule 14), so switch-ins favor fast and resisting Pokemon. Some rules above (absorb, save a sweeper) set the teammate themselves.

## 5. What it expects you to do

- It scores your moves with the same rules, so it expects you to click your best KO or strongest move. If none of your moves scores at least 100, it predicts you will switch. [HYPOTHESIS, CFRU]
- Several rules react to that prediction: it Protects against predicted Explosion, burns predicted physical attackers, uses Sucker Punch only when you are predicted to attack, and avoids attacks when you are predicted to switch.
- If your predicted move fails to happen (you did something else), some switch logic notices and stops trusting that prediction.

## 6. Hardcore Mode: anti-switch rule [HYPOTHESIS]

Only in Hardcore Mode, and never in puzzle/trial battles. After you switch, each AI Pokemon that chose a move may throw it away and re-pick a move against your new Pokemon:

- **Always** if you switch straight back to the Pokemon you had out before your last switch (A to B, then B back to A on the next turn).
- **Randomly**, based on a switch counter:
  - **+3** each time you switch, if the AI side did not also switch that turn.
  - **-1** at the end of every turn, but never below 0.
  - **Reset to 0** whenever any Pokemon faints.
  - When you switch with the counter at 9 to 11: 25% chance. At 12 to 15: 33%. At 16 or more: 50%.
  - The roll uses the counter including the switch you just made. Example, switching every turn: 3, then 5, then 7, then 9. So the 4th switch in a row is the first one that can trigger. Switching every other turn (+3 -1 -1) climbs only 1 per two turns.
- Not if you were forced out by Yawn. It never re-picks into Pursuit.

## 7. Practical takeaways

- **It always takes a guaranteed KO.** If you are within KO range of a faster move, expect it. Since it assumes the 9th damage roll, sitting just above that threshold can bait a non-KO move.
- **Bait with predictions.** It predicts your strongest move. Switching into an absorber or immunity on its predicted target works because it often keeps clicking the same strongest move.
- **It cannot switch every turn.** 25% of turns it will not even consider switching, and it never uses items.
- **Status users get Taunted.** Any status move on your active Pokemon gives Taunt +8.
- **Double-Protect is real.** Do not assume a Protect user will not Protect twice.
- **Sucker Punch reads your prediction.** If it expects you to use a status move, it will not Sucker Punch.
- **Counter/Mirror Coat is half as likely** as the logic alone suggests.
- **Late-game hazard waste.** With 3 or fewer of your Pokemon left, hazard setters may waste turns re-setting hazards.
- **Hardcore Mode punishes ping-pong switching** between the same two Pokemon.
