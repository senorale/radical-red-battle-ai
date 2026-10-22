# Radical Red AI research notes (working file)

Source: CFRU commit b637a27 at `vendor/cfru/src/Battle_AI/`. Pieces found in the rr.gba decompile noted as [ROM]. Code findings only, nothing here is human-verified in play.

## ROM DECOMPILE RESULTS (Ghidra 12.1.4 decompile of rr.gba)
- ROM BattleAI_DoAIProcessing 0x090C6F3C: same loop as CFRU (32-entry table, 4 moves, DO_NOT_ATTACK bit).
- ROM AI_TrySwitchOrUseItem 0x090C802C: raid end, mega potential, temp mega, CalculateAIPredictions, trainer check, ShouldSwitch, pivot flag, item.
- ROM Negatives 0x090C904C: dumb-AI kill rate (aiFlags==1, gRandomTurnNumber%100 < 50, +7/+2). RR ADDITION: disabled move gets -100 first.
- ROM AI_CalcDmg = 0x09087080: damage*93/100, fixed-damage cases match.
- CHANGED GetAIFlags = 0x090C77B0 (asm read):
  - Safari 0x40000000, Roamer roaming, Oak tutorial 0x80000000, Frontier, E-Reader/Trainer Tower/Raid -> 5.
  - SCRIPTED_WILD_2 -> 1 (CFRU adds WildMonIsSmart; RR does not). LEGENDARY_FRLG -> 3.
  - ANY TRAINER BATTLE -> 7 HARDCODED. Per-trainer aiFlags table is NOT used for trainers. All trainers = Negatives + Positives (SemiSmart no-ops when Positives flag set).
  - Wild (non-trainer) -> gTrainers[gTrainerBattleOpponent_A].aiFlags (trainer 0 = 0 normally => no scripts => random move among usable).
  - TWO_OPPONENTS: VarGet(0x5010) called but result discarded. No difficulty var in AI flags.
  - INGAME_PARTNER and not trainer -> |1.
  - So "dumb trainer" claims below are VOID for RR trainers.
- REMOVED AI item use: AI_TrySwitchOrUseItem asm (0x090C8262 path) has no ShouldAIUseItem call. Trainers never use items. Item section below is VOID for RR.
- CHANGED ShouldSwitch 0x090D824C: returns FALSE if flag 0x1042 (puzzle battle) or flag 0x10C0 (unknown); then Random2()%4==0 -> no switch this turn (25%). Rest of order matches CFRU (absorb, wish, locked/semi-invuln, perish, wonder guard, bad moves, natcure/regen, yawn, sleep...).
- ROM CalcMostSuitableMonToSwitchInto 0x090D7168: +14/+31/+8/+17/+2/+2, -39/-15/-1, max 70/140, hazard 71/142, 50% ties. RR ADDITION: puzzle battle (0x1042) -> first valid mon in party order.
- RR CUSTOM anti-cheese: battle script after player switch callasm 0x090C8F04. Runs only if FlagGet(0x1034)=Hardcore Mode and !0x1042. Calls 0x090C8CA4 per AI mon that chose a move: requires CHECK_GOOD_MOVE, player in control, not Frontier, player chose switch, not Yawned. Triggers if player switched back to the mon from 2 switches ago (secondPreviousMonIn) OR counter gNewBS+0x1D5 >8 with chance 25% (9-11), 33% (12-15), 50% (16+). RR CHANGED the counter vs CFRU's switchesInARow: +3 per player switch when AI side did not switch that round (0x090C02BE; CFRU +1, +2 Intimidate), -1 per battler at end of every turn if >0 (loop at 0x090911EE), reset to 0 on faint (0x0909EA9A); no reset on attacking (SetActionsAndBanksTurnOrder 0x0906FD40 only clears previousMonIn 0x1D9); turn-1 Intimidate preset removed. Matches community doc model.
- Party-mon damage calc (AI_CalcPartyDmg 0x09086DD8 and AI_CalcMonDefDmg) uses 96% roll (0x60/100), same as CFRU. Used by switch-in scoring.
- CanKnockOutFromParty 0x090DAA78 -> MoveKnocksOutFromParty 0x090DA9D0 -> damage 0x090DA8A4: all functional, so switch-in +31 KO bonus is live (community doc claims KO flags unused; code disagrees). Then fully re-chooses move+target vs new mon (no Pursuit).
- Flags: 0x1034 = Hardcore Mode (options script 0x0904F0xx). 0x1042 = puzzle/trial battle (0x09051Axx scripts).
- Var 0x5119 = special battle ID set before boss fights; a few AI rules special-case values 0x10 / 0x12.

### Negatives (0x090C904C) case-by-case vs CFRU (tooling: switch helpers patched, jump-table overrides)
- Ability IDs in RR are renumbered (199 Unseen Fist, 191 Contrary, 90 Magic Bounce, 152 Mold Breaker, 5 Sturdy, 12 Oblivious...).
- PROTECT CHANGED: protectUses==1 -> no penalty (CFRU 50% -6 singles / -10 doubles); protectUses>=2 -> -6 singles, -10 doubles (CFRU -10); King's Shield -9 rule removed; NEW -10 vs Unseen Fist.
- PARALYZE CHANGED: -5 if target knows Rest; else -2 if AI side avg speed > target side.
- EXPLOSION CHANGED: NEW -10 if target has Protect and didn't Protect last turn, or knows Fly/Dig-type move.
- COUNTER/MIRROR COAT CHANGED: random 50% -10 every evaluation (replaces CFRU conditional -8).
- SUCKER PUNCH CHANGED: no predicted move -> 50% -9 (and okay check); predicted status move or wouldn't go first -> -10.
- HAZARDS CHANGED: Rapid Spin-user penalty now 50%. Singles: foe <=3 mons -> NO hazard penalties at all (not even already-set -20). Foe >=4: if foe has Rapid Spin (AI not Ghost) / Defog / Magic Coat -> 50% -10 (boss var 0x12 exception). Already-set hazards -20. Doubles: foe <=2 mons -10.
- RECOVERY CHANGED: smart "heal at full HP to stall" exception removed (100% HP -10, >=90% -9).
- RECOIL_IF_MISS: acc <70 (CFRU <75) -6.
- TAUNT: also -10 vs ability 201.
- Fly/Bounce: CFRU two-turn checks skipped; RR-specific -10 condition.
- Disabled move -100 at top.
- Everything else read matched CFRU (sleep, toxic, burn, confuse, screens, setup moves, Substitute, Encore, Disable, Fake Out, Destiny Bond, Pain Split, weather, terrain, Trick, Knock Off, Haze, Roar, Belly Drum, Wish, Yawn, Trick Room...).

### Positives (0x090D10D4) vs CFRU
- KO logic (inlined DamageMoveViabilityIncrease) identical: +9 fast KO, slow-KO class bonus, +9 desperation priority, strongest +2 (support classes 4-8), thaw +10/+20.
- TAUNT CHANGED: NEW flat +8 if target has any usable status move (plus CFRU bonuses).
- SPEED_DOWN_HIT: +3 only 50% (Random2).
- SMACK_DOWN: NEW 50% +3 vs airborne target.
- Status, setup, Protect bonus (ShouldProtect), Fake Out, pivot, Pursuit, Encore, Destiny Bond, Trick Room, recovery (ShouldRecover) match.
- IncreaseViability value histogram consistent with CFRU (85 vs 100 call sites, all values present in source).

### Doubles (found in ROM, matches CFRU)
- UpdateBestDoublesKillingMoves 0x090C7524: loops attackers in gBanksByTurnOrder (speed order), per foe calls UpdateBestDoubleKillingMoveScore 0x090E03C4.
- 0x090E03C4: 75% Wide Guard check (<0x4b), +4 hit foe, +2 KO (Destiny Bond foe: KO bonus removed), +1 strongest, weak hit with 2 foes: -3 (<1/4 maxHP) / -2 (<1/3), 50%+ secondary effects (>0x31) keep full credit, partner handling, -3 hit partner.
- GetDoubleKillingScore 0x090E0E24: returns 0 unless move == stored best move for (atk, def); recalculates once if partner Protects vs spread move.
- IncreaseDoublesDamageViability 0x090C6E5C: viability += gDoublesDamageViabilityMapping[class-11][score].
- ChooseMoveOrAction (singles+doubles) 0x090C82C0: per-target best move with Random2 tie, ally needs >=101 (0x65), ChooseTarget tie-breaks via 0x090C470C (KO priority: player side, or attacker class when aiFlags>1), 0x090C4744 (most damage: attacker class 25% when aiFlags>2), 0x090C478C (dangerous: attacker class when aiFlags>2), 50% damage threshold (0x32), final Random2 among tied targets, partner fallback if score <0.
- Attacker classes (IsClassDoublesAttacker 0x090C407C: class-11 < 3): All-Out, Setup, Trick Room Attacker.
- Fighting class: GetBankFightingStyle 0x090C46DC (cached in gNewBS+0x888[bank], 0xFF = recompute), PredictBankFightingStyle 0x090C4618 (Dynamax/Max Move wrapper), PredictFightingStyle 0x090C40C4. Doubles branch matches CFRU at b039d662 (Aug 2021: Fake Out/Nuzzle not counted as attacks, phazer with 3 attacks or 2+Protect -> Setup, Total Team Support if <=1 attack) EXCEPT Setup Attacker check is attacks+boosts == 3 (asm 0x090C4574 `cmp r6,#0x3; beq`), CFRU uses >= 3 since dca61fa5 (2021-01-01). Sum of 4 without Protect falls through to Team Support/Utility. Rototiller: IsOfType Grass only, no CheckGrounding (pre bc516c5f). Item effects 0x85 Room Service, 0x62 Iron Ball, 0x18 Macho Brace, 0x84 Eject Pack; ability 0x16 Intimidate, Gear Up needs 0x39/0x3A. Move IDs checked against ROM name table: Trick Room 0x278, Fake Out 0xFC, Nuzzle 0x1F1, Endure 0xCB, Baton Pass 0xE2, Rototiller 0x1DF, Gear Up 0x24F, Magnet Rise 0x28A, Hyperspace Hole 0x1FD, Crafty Shield/Mat Block/Quick Guard/Wide Guard 0x27B-0x27E.

### Doubles post-KO replacement (ROM)
- OpponentHandleChoosePokemon 0x09068A28 (hook target): if no forced switchout index, recalc if stored best is none/dead (0x090D7168), then GetMostSuitableMonToSwitchInto 0x090D8230 (returns runner-up if top already chosen by partner); fallback = first valid party mon; RemoveBestMonToSwitchInto 0x090D9D78; TryRechoosePartnerMove. RR dropped CFRU's pivotTo branch and the partner-range check.
- In 0x090D7168: loop over gBattlersCount/2 foes, scores summed. Offense: CanKnockOutFromParty always (damage calc). Defense: damage calc only if (singles or ViableMonCountFromBank(foe)==1) and aiFlags>1, else type calc (SE -> weak -1). In doubles, faintsFromMove -> -1 only (doubles branch jumps to weak decrement). Max 140, hazard override 0x8E (142).

### Switching RNG
- ROM random points match CFRU (absorb 50% vs stall, Regenerator 50%, asleep 50%(+50%), Leech Seed 25%, save sweeper 50/75%, ties 50%) + RR 25% skip. RR uses Random2 here.

## Global facts
- [ROM] AI script table at 0x091491E0: [0] Negatives 0x090C904C, [1] SemiSmart 0x090D6998, [2] Positives 0x090D10D4, [29] Roaming, [30] Safari, [31] FirstBattle.
- [ROM] Trainer table at 0x0823EAC8 (pointer at 0x0800FC00), 743 entries. aiFlags: 574 trainers = 0x1 (Negatives only), 168 = 0x7 (all three). Smart = gym leaders, E4, rival Terry (27 entries), Giovanni, Archer/Ariana, Lance, Brendan/May, many named trainers. Grunts and route trainers mostly 0x1.
- The AI is omniscient: it reads player's real moves, ability, item, stats, speed (gBattleMons). No "revealed info" gating found yet in master.
- Each turn: CalculateAIPredictions once: strongest move per pair, can KO / 2HKO, doubles killing scores, predicted move of every battler (incl. player) = run Negatives+Positives (flags=7) over that battler's moveset vs each target; best viability <100 => predicted to switch; ties random.
- Order per AI mon: AI_TrySwitchOrUseItem (trainer battles): ShouldSwitch -> else ShouldAIUseItem -> else choose move.
- Move choice: score[i]=100 (0 if unusable: no PP, Disable, Taunt, Choice lock, etc.), each flag script adjusts, max wins, ties random (AIRandom).
- Temporary Mega: AI evaluates as if every mon that will Mega (both sides) already Mega evolved.
- Desperation flag: if foe faster and predicted to KO, and AI picks strongest priority move, it marks "desperate" (used elsewhere).
- simulatedRNG[i] = random 0-99 per move per turn (used in scripts).

## Difficulty / anti-cheese (compiled only if VAR_GAME_DIFFICULTY defined; NOT defined in public CFRU config) -> need ROM check
- Easy: smart -> semi, others -> negatives only. Hard: all trainers get SemiSmart. Expert: same + wild smart.
- Anti-cheese (Expert, smart trainers only): if player switches 3x in a row or double-switches between 2 mons, or turn-1 choice/Z/Fake Out lock bait, AI re-picks its move after seeing the switch. Hard+: may predict switches randomly.
- Doubles Expert: if player Protects vs turn-1 Fake Out/single-target move, AI retargets partner.
- Shift switch logic (AI switching after player faint) gated likewise.

## Items (ShouldAIUseItem)
- Trainer items from trainer data (4 slots). Not used if player bag disabled. Spread out: item i>0 only used if validMons <= itemsLeft... (spreads across mons).
- Full Restore / Max-full potions: dumb AI uses <25% HP. Smart AI uses <50% HP if ShouldRecover and foe has no faster KO move (singles); not if foe predicted Explosion/Fake Out.
- Potions that won't overheal: use whenever missing HP > heal amount (any HP!).
- Status heals: sleep, freeze, confusion always; poison/burn/para only if not beneficial (Guts etc).
- X items / Guard Spec: only on mon's first turn out.

## Switching (ShouldSwitch order; first match wins). Never if trapped / no healthy party.
1. Absorb predicted move: switch to Flash Fire / Volt Absorb / Lightning Rod / Motor Drive / Water Absorb / Dry Skin / Storm Drain / Sap Sipper mon. Singles: skipped if AI faster and can KO, or slower but boosted +1 and can KO and foe can't KO, or boosted +2 and foe can't KO, or behind Sub foe can't break, or player didn't use predicted move last turn (prediction failing). Vs stall foes only 50%. Repeat absorb-switch to same mon: 25% (75% if just switched) refuse. Full-HP absorber not used if current mon survives 3 hits. Mold Breaker foe => no.
2. Pass Wish to a mon <50% HP.
3. Stop locked/semi-invulnerable move (Fly/Dig/Outrage lock): switch to immune, then resisting mon (singles; doubles only last mon).
4. Perish Song count.
5. Wonder Guard foe (singles): if no SE/mold/status way to hurt it, switch to party mon with SE move.
6. Only bad moves left: switch if best/second mon outspeeds or walls or resists all and survives predicted move; looser when Choice locked.
7. Natural Cure (statused, >=50% HP) / Regenerator (<=50% HP, foe predicted KO and AI can't KO first). Not if hazards take 25%/33%.
8. Semi-invulnerable troll.
9. Yawned (smart checks: not if can KO last foe, Early Bird, Sleep Talk etc, sleep clause).
10. Asleep: 50% switch (another 50% stay if +2 Atk/SpA/Spe).
11. Annoying secondary dmg (smart only): Leech Seed 25%, Curse, Nightmare, Toxic 6+ turns.
12. Avoid death (smart, singles): foe's predicted move KOs, AI slower or no move, HP>20% (or perfect switch). Switch to mon immune that outspeeds/walls, or walls/outspeeds+KOs and survives, or rough-skin style contact KO. Not if paralyzed <33% HP, Destiny Bond, Aegislash King's Shield.
13. Offensive stat -3 or worse (damager class), can't KO -> switch to wall/resist or faster survivor.
14. Save sweeper for later (smart, singles): damager that can't KO now (or Fake Out incoming) and either foe will KO it, or 50%/75% random when not boosted; switch to mon that outspeeds+KOs or resists all.

## Switch-in choice (CalcMostSuitableMonToSwitchInto) scores per party mon vs each foe
+31 KO foe, +8 revenge kill (priority KO, Moxie, trapping ability, Pursuit/Fell Stinger KO), +14 outspeeds (priority KO counts), +17 resists/immune all damaging moves, +2 walls (Def/SpD > foe Atk/SpA for its splits), +2 can 2HKO (if can't KO). -39 faints to foe and slower; -15 faints but faster and can't KO; -1 weak (2HKO'd) . Max 70.
Smart AI singles uses real damage calcs; dumb AI and doubles use type matchups only.
Hazard remover (Rapid Spin/Defog) or grounded Poison vs T-Spikes overrides best unless best outspeeds+KOs or resists all.
Mons that faint to hazards are skipped. Sleeping mons skipped. Ties: prefer not-KO'd, else 50/50.

## Damage model (AI_CalcDmg, damage_calc.c:463)
- Assumes 93% damage roll (between min 85% and max 100%). Crits counted only if guaranteed (always-crit) or 50%+ chance (then coin flip via AIRandom).
- Sturdy / Focus Sash: caps damage at HP-1 for single-hit moves. Multiscale/Shadow Shield handled. Disguise/Sub: adds one hit.
- Fixed-damage moves exact (Super Fang half, Seismic Toss level). Psywave avg.
- "Strongest move" = highest 93%-roll damage capped at target HP. If several KO (tie): prefer higher priority, then better accuracy, then non-contact (if Rocky Helmet/Rough Skin etc), then no recoil, then no self stat drop, then random. Counter/Mirror Coat/Future Sight never win ties. Pursuit preferred if player has switched before.
- OHKO moves only considered if guaranteed hit and level ok.
- Speed: AI knows Quick Claw / Custap activation in advance (BracketCalc). Trick Room respected.
- When predicting player's move between equal options, uses PickMoveHumanLikelyToChoose.

## Positives (smart trainers 0x7) key bonuses (single battles)
- Damaging move that KOs and goes first (acc>=70 or no acc booster or AI dies anyway): +9. Not if player predicted to switch; not vs Sucker Punch prediction unless damager class; not if foe Destiny Bonded unless foe can KO.
- Slower but KOs (and no Protect): +8ish (by class: SlowKO).
- Foe will KO AI and AI has a priority move that goes first: +9 (desperation), unless Protect known, can heal-stall, entry hazard/phazer/stall classes, Fake Out better.
- Otherwise strongest move: +2 (more for support classes if it KOs).
- Setup: only if foe can't KO (going first) / can't 2HKO (going second), not vs Unaware, not vs Sturdy/Sash when it can't multi-hit. Set up to +2 normally; to +6 if foe is stall/support and didn't attack last turn, or player predicted to switch.
- Recovery when ShouldRecover: foe can KO now but not after heal, or 2HKO and heal > current HP (50%).
- Protect: when foe can KO (or 2HKO) and protect stalls usefully (Leftovers/poison chip/Toxic orb, Speed Boost, Moody, foe Perish/locked etc), vs Explosion, vs Fly/Dig landing, vs Dynamax. Never 3 in a row; 2nd in a row ~50% (singles) / never (doubles).
- Status: sleep big bonus for setup/support classes; paralysis if it makes AI faster; Will-O-Wisp if foe physical (bigger if foe KOs with physical); Toxic +1 (+2 with Venoshock etc). Confuse +1/+2.
- Taunt if player predicted to use status move or is stall/support class.
- Encore if player's last move was status (and AI faster) or predicted status.
- Pivot (U-turn/Volt Switch/Flip Turn/Parting Shot) via ShouldPivot: switch to better matchup, break Sash/Sturdy/Multiscale, bad stats.
- Pursuit if player predicted to switch (sweeper class).
- Fake Out: first turn only, if flinch useful; avoids Choice-lock into it when only 1 mon left unless KO.
- Destiny Bond if foe KOs (faster) / 2HKOs (slower).
- Explosion: only if no other KO move and won't win by staying; Damp blocks.
- Frozen: thaw move +10 (+20 doubles).

## Negatives (ALL trainers incl. 0x1)
- Immunity abilities (Volt/Water Absorb, Flash Fire, Sap Sipper, Lightning Rod, Storm Drain, Motor Drive, Dry Skin): -20 (also partner's Lightning Rod/Storm Drain in doubles).
- Soundproof, Bulletproof, Dazzling/Queenly Majesty (priority), Magic Bounce (-20), Clear Body etc, Contrary vs stat drops, Comatose, Leaf Guard in sun, Sweet/Flower/Aroma Veil: -10.
- Justified/Rattled/Steam Engine/Defiant/Competitive triggers: -4 to -9.
- No-effect / will miss (type immunity, Levitate etc): -15. Powder vs Grass/Overcoat/Goggles: -10.
- Terrain: Electric blocks sleep, Misty blocks status, Psychic blocks priority on grounded: -10.
- Prankster status into Dark type: -10. Primal weather: -20.
- Already statused / can't be statused / Substitute: -10. Stat boost at +6 or Contrary: -10. Setup while Choice-locked/Encored (smart): -10.
- Spikes etc: not when foe has <=1 mon left (singles), and smart AI avoids hazards if player has used Rapid Spin/Defog before (-9). Avoids hazards vs Magic Coat user.
- Sucker Punch: -10 if foe has no attacks; -9 when "not okay this round" (smart AI uses revealed SP 50%/turn).
- Doubles: all decreases are doubled.
- Dumb AI (0x1) kill rate: AI_TRY_TO_KILL_RATE 50 in CFRU config. Each turn 50% (gRandomTurnNumber) the dumb AI gives +7 to a KO move that goes first, +2 to strongest. Otherwise dumb AI picks randomly among non-penalised moves! (RR value not checked in ROM.)

## RNG
- AIRandom: own LCG seed (gNewBS->ai.randSeed), comment says it is advanced every frame. So AI random choices depend on frame timing; resetting and choosing at a different frame can change AI picks (ties, 50% coin flips).

## Doubles target choice
- Score each move vs each target (both foes and partner). Partner only if score>=101.
- Ties: KO count first (dumb always, smart only "attacker" classes), then threat (smart attacker classes: foe that can KO AI, then Mega/Dynamax), then most % damage (dumb/semi always; smart attacker 25%).
- Skips status moves on a foe partner will KO first. Avoids semi-invulnerable targets.
- Fighting classes (doubles): Trick Room setter/attacker, Utility (Follow Me/Rage Powder, Intimidate+Fake Out, Fake Out+pivot), Phazer, All-out attacker, Setup attacker, Team support. Priority ladders in "Doubles AI Strategy.txt".
