# Double Battles

How the Radical Red 4.1 AI picks moves and targets in double battles. Read `ai-guide.md` first for the tags and damage roll.

Doubles uses different move scoring from singles. These rules apply whenever both sides are not down to one Pokemon each. Once it is 1 vs 1, the singles rules in `move-or-switch.md` apply. All of this was checked in the ROM and matches CFRU.

## Step 1: each AI Pokemon gets a role [CFRU, ladders ROM-verified]

The role comes from its moveset, checked in this order:

| Role | Moveset |
|---|---|
| Trick Room Setter | Has Trick Room and at most 1 attacking move |
| Trick Room Attacker | Has Trick Room and 2+ attacks (or holds Room Service, Iron Ball or Macho Brace) |
| Utility | Has Follow Me/Rage Powder, or Fake Out plus Intimidate or a pivot move |
| Phazer | Has Roar/Whirlwind/Haze/Clear Smog (Setup Attacker instead if it also has 3 attacks, or 2 attacks plus Protect) |
| All-Out Attacker | 4 attacks, or 3 attacks plus Protect |
| Setup Attacker | Attacks plus offensive boosting moves adding up to 3 (or 2 with Protect) |
| Team Support | Screens, Tailwind, Safeguard, Heal Bell and similar |
| Utility (default) | Anything else |

Only **All-Out Attacker, Setup Attacker and Trick Room Attacker** count as "attackers" for the tie-break rules in step 4.

## Step 2: only ONE damaging move per target gets a damage bonus [ROM]

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

## Step 3: status and support moves compete on the same ladder [ROM ladders, CFRU rules]

Fake Out, Protect, Tailwind, Trick Room, redirection, sleep, Will-O-Wisp, screens, Helping Hand, healing its partner and so on each get fixed role bonuses from the same ladders. For support roles many of these outrank attacking, so they often pick status moves even when they could hit hard.

## Step 4: picking the target [ROM]

1. It scores its moves against each living Pokemon separately (both of yours, plus its own partner) and keeps the best move for each. **If several moves tie, it picks one at random.**
2. It never targets its own partner unless that score is above 100 (for example, to trigger the partner's absorb ability or Justified).
3. It picks the target with the highest score. When targets tie:
   - **Attacker roles**: prefer the move that KOs more targets. If both KO equally, prefer the foe that can KO the AI, then a Mega Evolved foe. If nothing KOs but both take 50%+ damage, same threat check. Otherwise prefer the target taking more damage, **but only 25% of the time**.
   - **Every other role (Utility, Phazer, Team Support, Trick Room Setter)**: **random** among the tied targets.
4. It will not waste a status move on a target its partner is about to KO first.
5. If its pick lands on its own partner with a negative score, it retargets one of your Pokemon.

## Step 5: partner coordination [ROM]

The AI processes its two Pokemon in speed order, so the slower one knows what the faster one chose:

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

## Other doubles rules

| Rule | Detail | Source |
|---|---|---|
| Fake Out | Strong preference on turn 1, aimed at the more threatening target. | [CFRU] |
| Protect | Second Protect in a row has no penalty in Radical Red; third gets -10. | [ROM] |
| Penalties | All "avoid" penalties from `move-or-switch.md` are doubled. | [CFRU] |
| Thaw | A frozen AI Pokemon with a thawing move gets +20. | [ROM] |
| Switching | Most switch rules in `move-or-switch.md` are singles-only. In doubles it mainly switches to absorb your predicted attack, when it has only bad moves left against both foes, or for Yawn/asleep/residual damage. Switch-ins use type matchups, not damage calcs (`post-ko-switch-in.md`). | [CFRU] |

## Priority ladders

Bonus added to the base score of 100, by role. Numbers in parentheses are the step 2 damage score. The damage entries come from a table that is byte-identical in the ROM [ROM]. The other entries come from CFRU's doubles strategy file and code [CFRU].

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
