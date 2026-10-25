# Doubles: Moves and Targets

How the Radical Red 4.1 AI picks moves and targets in double battles. Read `../ai-guide.md` first for the tags and damage roll.

Doubles uses different move scoring from singles. These rules apply whenever both sides are not down to one Pokemon each. Once it is 1 vs 1, the singles rules in `../singles/move-or-switch.md` apply. All of this was checked in the ROM and matches CFRU. The parts tested in game, with evidence, are in `../findings.md` ("Doubles: move selection", D1 to D6).

## Overview with examples

"Enemy A/B" are the AI's two Pokemon on the field, "your X/Y" are yours. Every move starts at 100; the highest score is used.

**1. The faster enemy decides first** [TESTED, D1]. The slower one already knows its partner's move and target.
*Example:* Enemy A (Speed 110) picks a move into your X; Enemy B (Speed 90) decides next, and if A's move will KO X, B goes for Y.

**2. Every move is scored against every target, partner included** [TESTED, D1]. Partner targets scoring under 101 are dropped.
*Example:* Enemy A gets 4 scores against X, 4 against Y and 4 against Enemy B; its Earthquake into Enemy B scores 70, so that target is never picked.

**3. Only the best attack per target gets a damage bonus** [TESTED, D2]. Points: hit +4, KO +2 more, strongest move (no KO) +1 more, weak hit with both foes up -3 (under 1/4 HP) or -2 (under 1/3 HP); a spread move adds its points for each foe. The points become a bonus by role (All-Out Attacker: 5 points = +10, 6 = +11, 10 = +16).
*Example:* Enemy A (All-Out Attacker) against your X (100 HP): Move 1 does 60 (strongest, no KO: 4 + 1 = 5 points) = **110**; Move 2 does 55 and Move 3 does 20, not the best, both **100**. If Move 1 did 100+, it would be a KO: 6 points = 111. A spread move that is the strongest on both X and Y: 5 + 5 = 10 points = **116**. A spread move doing under 1/4 HP to both: 1 + 1 = 2 points = 109, so a strong single-target move (110) beats it.

**4. Adjustments** [TESTED, D3 and D5; OBSERVED, D4]:
- *Partner already KOs the target:* Enemy A (faster) picks Fake Out into your X with 30 HP left, and Fake Out KOs it. Enemy B's best move into X drops to 100, its best into Y stays at 110, so B attacks Y.
- *No effect:* Enemy A's Electric move into your Ground-type X scores 70 (-30); into a Volt Absorb Pokemon 60 (-40).
- *Fake Out:* your X can KO one of the enemies and your Y can KO neither: Fake Out into X = 115, into Y = 114, so it Fake Outs X. From the next turn Fake Out scores 80.

**5. Picking the target when the best scores tie** [TESTED, D6] (enemies with an attacker role):
1. *More KOs wins, counting the partner's faster hit on the same foe.* Example: Enemy A's best into X and into Y are both 110. X has 60 HP; Enemy B already chose a priority move into X doing 36 and A's move does 42: together 78 is a KO, so A always hits X.
2. *If both hits do at least 50% of max HP, prefer the foe that can KO this enemy.* Example: A does 74% to X and 90% to Y, no KO; if Y can KO A and X cannot, A hits Y.
3. *Otherwise a 25% roll:* if it hits, the target taking the bigger % of its max HP wins; if not, a coin flip. Example: A does 39% to X and 69% to Y: Y about 62.5% of the time, X 37.5%. Give Y a resist berry so A only does 33% to it, and X becomes the 62.5% side.

`Random2` is a fixed formula: from the same savestate with the same inputs the pick is always the same; the percentages above are over different starting seeds.

## Step 1: each AI Pokemon gets a role [HYPOTHESIS]

The role comes from its moveset, checked in this order:

| Role | Moveset |
|---|---|
| Trick Room Setter | Has Trick Room and at most 1 attacking move |
| Trick Room Attacker | Has Trick Room and 2+ attacks (or holds Room Service, Iron Ball or Macho Brace) |
| Utility | Has Follow Me/Rage Powder, or Fake Out plus Intimidate or a pivot move |
| Phazer | Has Roar/Whirlwind/Haze/Clear Smog (Setup Attacker instead if it also has 3 attacks, or 2 attacks plus Protect) |
| All-Out Attacker | 4 attacks, or 3 attacks plus Protect |
| Setup Attacker | Attacks plus offensive boosting moves adding up to exactly 3 (or exactly 2 with Protect) |
| Team Support | Screens, Tailwind, Safeguard, Heal Bell and similar |
| Utility (default) | Anything else |

Only **All-Out Attacker, Setup Attacker and Trick Room Attacker** count as "attackers" for the tie-break rules in step 4.

Details from the ROM:

- **Inputs are the moveset, the ability and the held item.** Intimidate is the only ability checked (Utility). Room Service, Iron Ball and Macho Brace are the only items checked (Trick Room Attacker).
- **Fake Out and Nuzzle do not count as attacks.** Fake Out plus 3 attacks is not "4 attacks".
- **Setup Attacker needs exactly 3, a Radical Red change.** Current CFRU uses "3 or more". Radical Red still has the older "exactly 3" check, so a moveset adding up to 4 without Protect skips Setup Attacker. Swords Dance, Dragon Dance or Nasty Plot plus 3 attacks, or 2 attacks plus 2 boosting moves, becomes **Utility** (or Team Support with a screen or similar). That means a lower damage ladder and random target tie-breaks.
- **Rototiller counts as a boost for any Grass type**, with no grounded check (older CFRU behavior).
- **Doubles roles apply only while both of your Pokemon or its own partner are alive.** Otherwise it uses the singles roles.

## Step 2: only ONE damaging move per target gets a damage bonus [TESTED, D2]

For each of your Pokemon it might target, the AI picks a single "best damaging move" by adding up:

| Per Pokemon the move hits | Points |
|---|---|
| Hits a foe | +4 |
| KOs that foe | +2 more (none if the foe used Destiny Bond) |
| Does not KO, but is its strongest move against that foe | +1 more |
| Weak hit while both foes are up: under 1/4 of max HP | counts only +1 total |
| Weak hit while both foes are up: under 1/3 of max HP | counts only +2 total |
| Useful 50%+ secondary effect (flinch while faster, burn, paralysis, stat drops, etc.) | keeps the full +4 even if weak |
| Hits its own partner (Earthquake, Surf, etc.) | -3, unless the partner is Protecting or flying/digging |

Spread moves add these points for both foes, so a spread move that hits both scores up to 12. If your side has Wide Guard, it ignores spread moves 75% of the time. Ties between moves go to the spread move that does not hit its partner.

**Only that one best move gets a bonus.** Its total (0 to 12) is converted into a bonus from its role's priority ladder (section "Priority ladders", +1 to +19). Every other damaging move gets no damage bonus and stays near the base score of 100. This is why the AI often looks like it is ignoring an obviously good move: that move simply was not the single "best" one for that target.

## Step 3: status and support moves compete on the same ladder [HYPOTHESIS: ladders from RR code, rules from CFRU]

Fake Out, Protect, Tailwind, Trick Room, redirection, sleep, Will-O-Wisp, screens, Helping Hand, healing its partner and so on each get fixed role bonuses from the same ladders. For support roles many of these outrank attacking, so they often pick status moves even when they could hit hard.

## Step 4: picking the target [TESTED for attacker roles, D6]

Seen in game: Mr. Mime's two tied targets went 68% / 32% toward the harder-hit one, flipped to 40% / 60% when a Payapa Berry lowered that damage, and became 100% when the partner's Fake Out plus its own hit would KO. Traced: the 25% roll and the damage % decide exactly as below.

1. It scores its moves against each living Pokemon separately (both of yours, plus its own partner) and keeps the best move for each. **If several moves tie, it picks one at random.**
2. It never targets its own partner unless that score is above 100 (for example, to trigger the partner's absorb ability or Justified).
3. It picks the target with the highest score. When targets tie:
   - **Attacker roles**: prefer the move that KOs more targets. If both KO equally, prefer the foe that can KO the AI, then a Mega Evolved foe. If nothing KOs but both take 50%+ damage, same threat check. Otherwise prefer the target taking more damage, **but only 25% of the time**.
   - **Every other role (Utility, Phazer, Team Support, Trick Room Setter)**: **random** among the tied targets.
4. It will not waste a status move on a target its partner is about to KO first.
5. If its pick lands on its own partner with a negative score, it retargets one of your Pokemon.

## Step 5: partner coordination [TESTED for the first two points, D1 and D3]

The AI processes its two Pokemon in speed order, so the slower one knows what the faster one chose (seen: Boltund 110 before Ambipom 105 before Mr. Mime 93):

- A target the partner is about to KO counts as "already handled", so it looks elsewhere.
- If the partner is about to KO both foes with a spread move, it does too, unless the partner is slower than a foe.
- It Protects if the partner is about to use a move that would hit it, and does not double up on the same Fake Out target.

## Why doubles feels random

1. Two random rolls per turn: one between equally scored moves, one between equally scored targets.
2. Support and utility roles pick targets at random whenever scores tie, which is common.
3. Attacker roles go for the most damage only 25% of the time when KOs and threats are equal.
4. Only one damaging move per target gets a bonus, so its other strong moves sit at the same score as each other and get picked at random.
5. The 75% Wide Guard check changes from turn to turn.
6. Its choices depend on its partner's choice, which changes the whole picture when the faster partner picks differently.
7. Moves with a 50%+ crit chance get a coin flip on whether the crit is counted, which can change whether a move "KOs".
8. Replacements after a KO are also coin flips on ties, and in doubles every tie is a flip (`post-ko-switch-in.md` section 3).

## Other doubles rules

| Rule | Detail | Source |
|---|---|---|
| Fake Out | First turn only: +15 for All-Out/Setup Attackers, +17 Trick Room/team support, +19 Utility/Phazer; -1 against the less threatening foe (the one whose partner can KO more of the AI's Pokemon), so it goes to the bigger threat. Never two Fake Outs on the same foe. After the first turn it scores 80 (-20). Seen: Ambipom 115 vs 114, Fake Out into Mightyena in 100 of 100 runs; Perrserker 119 (Utility). `0x090C67A4`, `../findings.md` D5. | [TESTED] |
| Protect | Second Protect in a row has no penalty in Radical Red; third gets -10. | [HYPOTHESIS] |
| Penalties | All "avoid" penalties from `../singles/move-or-switch.md` are doubled. Seen: moves with no effect score 70 (-30, singles -15), into an absorbing ability 60 (-40). | [HYPOTHESIS, CFRU], -30 [OBSERVED] |
| Thaw | A frozen AI Pokemon with a thawing move gets +20. | [HYPOTHESIS] |
| Switching mid-turn | Step 1 of the mid-turn swap (should it switch?). In doubles "about to die" and "save a sweeper" are off; it can still switch to absorb your predicted attack when its own attacks are weak, when it has only bad moves against both foes, for Yawn/sleep/residual damage, or with an attacking stat at -3 (seen once). Full table: `../findings.md` M1 to M3. | [HYPOTHESIS], stat drop [TESTED] |
| Replacements after a KO | Scored against both of your Pokemon and summed. Its own damage never counts (the bench damage cache bug: bench damage reads as 0, `../findings.md` rule 14); your offense uses only the type chart; Speed against each of your Pokemon is +14. Details in `post-ko-switch-in.md`. | [VERIFIED]; bench damage [OBSERVED] |

## Priority ladders

Bonus added to the base score of 100, by role. Numbers in parentheses are the step 2 damage score. The damage entries come from a table that is byte-identical in the ROM [HYPOTHESIS]. The other entries come from CFRU's doubles strategy file and code [HYPOTHESIS, CFRU].

**All-Out Attacker**: +19 hit 2 foes and KO 2 (12) · +18 Intimidate pivot · +17 (11) · +16 (10) · +15 Protect from ally / Fake Out · +14 (9) · +13 (8) · +12 Protect from foes · +11 (6) · +10 (5) · +9 (4) · +8 Wide/Quick Guard · +7 heal partner · +6 raise partner stats

**Setup Attacker**: +19 (12) · +18 Tailwind if slower · +17 one offensive boost · +16 (11) · +15 (10) · +14 Protect from ally / Fake Out · +13 (9) · +12 (8) · +11 (6) · +10 Protect from foes · +9 (5) · +5 to +8 status moves · +4 (4) · +3 Wide/Quick Guard · +2 heal partner · +1 Helping Hand etc.

**Trick Room Attacker**: +19 Trick Room · +18 (12) · +17 Fake Out · +16 (11) · +15 (10) · +14 (9) · +13 Stealth Rock · +12 Protect from ally · +11 (8) · +10 (6) · +9 (5) · +5 to +8 status moves · +4 Protect from foes · +3 Wide/Quick Guard or (4) · +2 heal partner · +1 Helping Hand etc.

**Trick Room Setter**: +19 Trick Room · +18 (12) · +17 Fake Out · +16 recovery · +15 Helping Hand etc. · +14 Protect from ally · +13 Wide/Quick Guard/Mat Block · +12 heal partner · +8 to +11 status moves · +7 Protect from foes · +6 (11) · +5 (10) · +4 (9) · +3 (8) · +2 (6) · +1 (5)

**Utility**: +19 Fake Out · +18 (12) · +17 sleep · +16 redirection / Intimidate pivot · +15 heal partner / Taunt Wide Guard user · +14 Protect from ally · +13 Helping Hand etc. · +12 Wide/Quick Guard · +11 speed control / Tailwind / Will-O-Wisp · +10 Protect from foes · +9 (11) · +8 (10) · +4 to +7 status moves · +3 (9) · +2 (8) · +1 (6)

**Phazer**: +19 Fake Out · +18 (12) · +17 hazards · +16 Roar/Dragon Tail/Clear Smog (if it can't KO) · +15 Haze · +14 Protect from ally · +13 Protect from foes · +9 to +12 status moves · +8 (11) · +7 (10) · +6 (9) · +5 (8) · +4 (6) · +3 Wide/Quick Guard · +2 heal partner · +1 Helping Hand etc.

**Team Support**: +19 Aurora Veil · +18 Tailwind · +17 weather / Fake Out · +16 (12) · +15 screens · +14 Protect from ally · +13 heal partner / Taunt Wide Guard user · +12 Wide/Quick Guard · +11 speed control / Will-O-Wisp · +10 Helping Hand etc. · +9 (11) · +8 Safeguard/Mist/Lucky Chant · +7 (10) · +3 to +6 status moves · +2 (9) · +1 Protect from foes

## Practical takeaways

- **Read its roles.** Attackers (4 attacks, or 3 attacks plus Protect) are the predictable ones: they go for KOs, then whichever of your Pokemon threatens them.
- **Support roles are coin flips.** When scores tie, Utility, Phazer and Team Support pick targets at random.
- **Its non-best attacks are interchangeable.** Expect it to rotate between its other attacks at random.
- **Bait the slower partner.** The slower AI Pokemon plans around what its faster partner chose, so it avoids a target the partner is about to KO.
