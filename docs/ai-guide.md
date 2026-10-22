# Radical Red 4.1: How the Enemy AI Decides (Player Guide)

As of 2026-10-22. Built from the CFRU source (the engine Radical Red is built on) and checked against the Radical Red 4.1 ROM with Ghidra.

## How to read this

- **[ROM]** = confirmed by reading Radical Red's own compiled code.
- **[CFRU]** = from the CFRU source. The surrounding Radical Red code was checked and matches, but this specific rule was not line-checked.
- **Score** = every move starts at 100 each turn. Rules add or subtract points. The highest score wins. Ties are broken at random. Only the order matters, so "+9" beats "+2".
- "You" means the player. "AI" means the opposing trainer's Pokemon.

## 1. The big picture

| Fact | Detail | Source |
|---|---|---|
| Every trainer uses the full smart AI | Radical Red ignores the per-trainer AI setting and gives every trainer battle the full "Check Bad Move + Check Good Move" AI. There are no "dumb" route trainers. | [ROM] |
| Wild Pokemon act randomly | Wild battles get no scoring scripts, so they pick any usable move at random. Scripted legendary encounters use a lighter "semi-smart" AI. | [ROM] |
| Difficulty does not change AI intelligence | No difficulty variable is read when picking AI flags. Hardcore Mode only adds the anti-switch rule in section 8. | [ROM] |
| Trainers never use items | The item-use step was removed. Full Restores listed in trainer data are never used. | [ROM] |
| The AI sees everything | It reads your real moves, ability, held item, stats, stat stages and speed, including whether your Quick Claw will activate this turn. | [CFRU] |
| It predicts your move | Each turn it scores your moveset with its own rules and assumes you pick the top move. If none of your moves scores at least 100, it predicts you will switch. | [CFRU] |
| Megas are planned ahead | Before deciding, it evaluates every Pokemon that will Mega Evolve (yours and its own) as already Mega Evolved. | [CFRU] |

## 2. Order of decisions each turn

1. **Switch check.** On 25% of turns the AI skips this entirely and will not switch no matter what. [ROM] Otherwise it runs the switch rules in section 6. Puzzle/trial battles never switch. [ROM]
2. **Pick a move** by score (sections 3 to 5).
3. **Hardcore Mode only:** after you switch, it may re-pick its move (section 8). [ROM]

## 3. How the AI judges damage

| Rule | Detail | Source |
|---|---|---|
| Damage roll | Real damage uses one of 16 equally likely rolls, 85% to 100% (`100 - (Random() & 15)`). The AI always assumes the 93% roll: the 9th of 16, sorted low to high. No randomness in this assumption. Its estimate can be off by about 1 HP from rounding. | [ROM] |
| "Can KO" | The AI treats a move as a KO only if the 9th roll reaches your current HP. On a damage calc, check the 9th of the 16 rolls. If you sit right at that threshold, the real KO chance is only about 50% (rolls 93 to 100). If the 9th roll falls short, the AI does not plan for the KO, even though the higher rolls (94 to 100) can still kill you. | [ROM] |
| Crits | Counted only for guaranteed crits, or moves with 50%+ crit chance (then a coin flip). | [ROM] |
| Sturdy / Focus Sash | Single hits are capped at HP-1. Multi-hit moves and Disguise/Substitute are handled. | [ROM] |
| Fixed damage | Super Fang = half HP, Seismic Toss/Night Shade = level, Endeavor and Pain Split exact. | [ROM] |
| Strongest move | Highest damage, capped at your HP. When several moves all KO, it prefers: higher priority, then better accuracy, then non-contact (if contact is punished), then no recoil, then no stat drop, then random. Counter/Mirror Coat/Future Sight never win a tie. Pursuit is preferred once you have shown you like switching. | [CFRU] |

## 4. Move scoring in single battles

### Attacking moves (applies to every trainer) [ROM]

| Situation | Bonus |
|---|---|
| Move KOs you and goes first (accuracy 70+, or no accuracy booster, or the AI is about to die anyway) | **+9** |
| Skipped if | you are predicted to switch; you are predicted to use Sucker Punch (unless the AI is an attacker type or its move outspeeds); you used Destiny Bond (unless you would KO it anyway) |
| Move KOs but goes second, and the AI has no Protect | +3 to +9 depending on its role |
| You will KO the AI first, and it has a priority move that goes first | **+9** "desperation" (can repeat ~75% of the time after you attacked, ~25% after you used a status move) |
| Otherwise, its strongest move | **+2** (support roles get 4 to 8 if it KOs) |
| AI is frozen and has a thawing move | +10 (+20 in doubles) |

Practical meaning: if it can kill you first, it almost always does. If it cannot kill, it usually just clicks its strongest move unless a status/setup rule scores higher.

### Status and utility moves

Everything labeled "Radical Red" in this table is [ROM]. The base conditions (when it likes setup, sleep, Protect, recovery) come from CFRU helper functions whose call sites were confirmed in the ROM but whose bodies were not line-checked, so treat them as [CFRU].

| Move type | When the AI likes it |
|---|---|
| **Taunt** | **+8 whenever your Pokemon has any usable status move** (Radical Red addition), plus more if you are predicted to use a status move or are a stall/support set. Expect Taunt a lot against setup and support mons. |
| **Protect** | When you can KO or 2HKO it and protecting helps: chip from Leftovers/poison/Leech Seed, Speed Boost or Moody, your Perish count, your Explosion, you coming down from Fly/Dig. Radical Red rules: a second Protect in a row has **no penalty**; a third gets -6 in singles (-10 in doubles). So double-Protect is common. Never Protects against Unseen Fist. |
| **Recovery** | When you can KO now but not after it heals, or (50%) you can 2HKO and the heal is bigger than its current HP. Never at full HP; heavily discouraged at 90%+. |
| **Setup (Swords Dance etc.)** | Only if you cannot KO it this turn (when it moves first) or cannot 2HKO it (when it moves second), and not into Unaware, and not into Sturdy/Sash when it cannot break them. Normally sets up to +2; up to +6 if you look passive (stall/support, did not attack last turn) or are predicted to switch. |
| **Sleep / Yawn** | Big bonus for setup and support roles (+7 to +9 with 80%+ accuracy). Not if it can just KO you. |
| **Paralysis (Thunder Wave etc.)** | Bonus if it would then outspeed you. Radical Red penalties: -5 if you know Rest, -2 if its side is already faster. |
| **Will-O-Wisp** | +3 if you are predicted to KO it with a physical move, more if you are physical in general. |
| **Toxic** | Mild bonus (+1, +2 with Venoshock/Barb Barrage/Merciless). |
| **Encore** | When your last move (it moving first) or predicted move is a status move. |
| **Counter / Mirror Coat** | Radical Red adds a flat 50% chance of -10 every turn, so it uses them about half as often as it otherwise would. Never when you are predicted to use a status move. |
| **Sucker Punch** | Radical Red rule: only when it predicts you will attack and it would go first. -10 if it predicts a status move from you; 50% penalty if it predicts you switch. |
| **Explosion** | Only when no other move KOs and staying in does not win. Radical Red adds: never into a Protect you did not use last turn, never if you know Fly/Dig/etc. Never with Damp on field. |
| **U-turn / Volt Switch / Parting Shot** | Used to pivot into a better matchup, break Sash/Sturdy/Multiscale, or escape bad stat drops. Penalized (-9) when pivoting is a bad idea. |
| **Pursuit** | +3 for attacker roles when you are predicted to switch. |
| **Fake Out** | First turn only, when flinching is useful. |
| **Destiny Bond** | When you will KO it (it is faster) or 2HKO it (it is slower). |
| **Entry hazards** | Bonus if any of your benched Pokemon would be hurt. Radical Red changes: if you have **3 or fewer** healthy Pokemon (singles), the "already set" penalty is skipped, so a hazard setter can waste turns re-using Stealth Rock/Spikes. With 4+ mons, it avoids hazards 50% of the time if you have Rapid Spin, Defog or Magic Coat. |
| **Speed-lowering attacks (Icy Wind etc.)** | Small bonus, only 50% of the time (Radical Red). |

### Things the AI avoids (penalties, every trainer) [ROM]

- Moves your ability blocks: Volt Absorb, Lightning Rod, Motor Drive, Water Absorb, Storm Drain, Dry Skin, Flash Fire, Sap Sipper, Soundproof, Bulletproof, Magic Bounce, Dazzling/Queenly Majesty vs priority, Clear Body vs stat drops, Contrary vs stat drops, and many newer immunity abilities.
- Moves that do nothing: type immunity or guaranteed miss (-15), powder vs Grass/Overcoat/Goggles, status into an already-statused or immune target, stat boosts at +6.
- Terrain: no sleep in Electric Terrain, no status in Misty Terrain, no priority into grounded targets in Psychic Terrain.
- Stat-drop moves that would trigger Defiant/Competitive; contact or type moves that trigger Justified, Rattled, Steam Engine.
- Prankster status into Dark types.
- Two-turn moves when you can Protect or KO it during the charge.

## 5. What the AI predicts you will do

- It scores your moves with the same rules, so it expects you to click your best KO or strongest move.
- Several rules react to that prediction: it Protects against predicted Explosion, burns predicted physical attackers, uses Sucker Punch only when you are predicted to attack, and avoids attacks when you are predicted to switch.
- If your predicted move fails to happen (you did something else), some switch logic notices and stops trusting that prediction.

## 6. Switching

### When it switches (singles) [order from CFRU, presence confirmed in ROM]

Only checked on 75% of turns. Never when trapped. The first matching rule wins:

1. **Absorb your predicted attack**: switches to a Flash Fire / Volt Absorb / Lightning Rod / Motor Drive / Water Absorb / Dry Skin / Storm Drain / Sap Sipper teammate. Not if it can KO you first, is boosted, or is behind a working Substitute. Less likely if it already did this.
2. Pass a pending Wish to a teammate below 50% HP.
3. Dodge your locked-in move (Outrage, or you coming down from Fly/Dig) with an immune or resisting teammate.
4. Perish Song about to end.
5. Facing Wonder Guard with no way to hurt it.
6. Only bad moves left, and a teammate can come in safely.
7. Natural Cure (statused, 50%+ HP) or Regenerator (50% or less HP, you would KO it).
8. About to fall asleep from Yawn (various exceptions).
9. Asleep: 50% chance to switch.
10. Heavy residual damage: Leech Seed (25%), Curse, Nightmare, long Toxic.
11. **About to die**: you will KO it first, it is above 20% HP, and a teammate can come in immune, walls you, or outspeeds and KOs.
12. Attacking stat at -3 or worse.
13. **Save a sweeper**: an attacker that cannot KO you right now may switch to a teammate that outspeeds and KOs, or resists everything (partly random to stay unpredictable).

### Which Pokemon it sends in [ROM]

Each healthy teammate is scored against your active Pokemon:

| Trait | Points |
|---|---|
| Can KO you | +31 |
| Outspeeds you (or has a priority move that KOs) | +14 |
| Revenge kill (priority KO, Moxie, trapping ability, Pursuit/Fell Stinger KO) | +8 |
| Resists or is immune to all your damaging moves | +17 |
| Walls you (its defenses beat your attack stats) | +2 |
| Can 2HKO you (only if it cannot KO) | +2 |
| You KO it and it is slower | -39 |
| You KO it, it is faster but cannot KO you | -15 |
| You 2HKO it | -1 |

Perfect score is 70. Smart trainers in singles use real damage calcs; in doubles it uses type matchups only. Teammates that would faint to hazards or are asleep are skipped. A Rapid Spin/Defog user (or a grounded Poison type vs Toxic Spikes) is preferred when hazards are up, unless the top pick outspeeds-and-KOs or resists everything. Ties are a coin flip. The same scoring picks its next Pokemon after a faint.

**Puzzle/trial battles** skip scoring and send Pokemon in fixed party order. [ROM]

## 7. Double battles

| Rule | Detail | Source |
|---|---|---|
| Target choice | It scores every move against each of your Pokemon (and its partner) and picks the best target. It only targets its own partner with a score above 100 (for example, to trigger an absorb ability). | [CFRU] |
| Tie-breaks | Prefers the move that KOs more targets, then the target that can KO it (and Mega Evolved targets), then the target taking the most damage (only 25% of the time for attacker types, to stay unpredictable). | [CFRU] |
| Roles | Each AI Pokemon is classed by moveset: All-Out Attacker, Setup Attacker, Trick Room Setter/Attacker, Utility (Follow Me, Fake Out + Intimidate/pivot), Phazer, Team Support. Each role has its own priority ladder. | [ROM table identical to CFRU] |
| Spread moves | Big bonuses for moves that hit and KO both foes. It Protects if its partner is about to use Earthquake-style moves that would hit it. | [CFRU] |
| Fake Out | Strong preference on turn 1, aimed at the more threatening target. | [CFRU] |
| Protect | Second Protect in a row has no penalty in Radical Red; third gets -10. | [ROM] |
| Penalties | All "avoid" penalties are doubled in doubles. | [CFRU] |
| Status on doomed targets | It will not waste a status move on a target its partner will KO first. | [CFRU] |

## 8. Hardcore Mode: anti-switch rule [ROM]

Only in Hardcore Mode, and never in puzzle/trial battles. After you switch, each AI Pokemon that chose a move may throw it away and re-pick a move against your new Pokemon, with a new target:

- **Always** if you switched back to the Pokemon you had two switches ago (double-switching between two mons).
- **Randomly** if you have switched many turns in a row: 25% chance at 9 to 11 consecutive switches, 33% at 12 to 15, 50% at 16+.
- Not if you were forced out by Yawn. It never re-picks into Pursuit.

## 9. Practical takeaways

- **No dumb trainers.** Plan every trainer fight assuming the AI sees your whole set.
- **It always takes a guaranteed KO.** If you are within KO range of a faster move, expect it. Since it assumes a 93% roll, sitting just above that threshold can bait a non-KO move.
- **Bait with predictions.** It predicts your strongest move. Switching into an absorber or immunity on its predicted target works because it often keeps clicking the same strongest move.
- **It cannot switch every turn.** 25% of turns it will not even consider switching, and it never uses items.
- **Status users get Taunted.** Any status move on your active Pokemon gives Taunt +8.
- **Double-Protect is real.** Do not assume a Protect user will not Protect twice.
- **Sucker Punch reads your prediction.** If it expects you to use a status move, it will not Sucker Punch.
- **Counter/Mirror Coat is half as likely** as the logic alone suggests.
- **Late-game hazard waste.** With 3 or fewer of your Pokemon left, hazard setters may waste turns re-setting hazards.
- **Hardcore Mode punishes ping-pong switching** between the same two Pokemon.

## 10. Not yet verified

- Double battle target-selection code was not line-checked against CFRU (the data table is identical).
- The exact meaning of game flag 0x10C0 (it blocks AI switching when set).
- Which bosses use special battle ID 0x10 / 0x12 (minor hazard and ability exceptions).
- No live testing in an emulator yet. All results come from reading the code.

## Sources

- CFRU source: github.com/Skeli789/Complete-Fire-Red-Upgrade (commit b637a27), `src/Battle_AI/`.
- Radical Red 4.1 ROM (`roms/rr.gba`), decompiled with Ghidra 12.1.4. Key addresses: GetAIFlags 0x090C77B0, AI_TrySwitchOrUseItem 0x090C802C, ShouldSwitch 0x090D824C, switch-in scoring 0x090D7168, Negatives 0x090C904C, Positives 0x090D10D4, AI damage calc 0x09087080, Hardcore re-pick 0x090C8F04 / 0x090C8CA4.
- Full working notes: `docs/ai-notes.md`.
