# Check Radical Red AI claims against rr.gba code

Method: Ghidra headless decompile of RR functions (Thumb, base 0x08000000), labeled with CFRU symbols (BPRE.ld, hook targets, routine pointers). Compare each decompiled function against CFRU source (`vendor/cfru/src/Battle_AI`, commit b637a27). Mark each claim MATCHES / CHANGED / UNCHECKED. These are code findings, not human verification.

Already checked by data scan:
- AI script table 0x091491E0 (Negatives/SemiSmart/Positives/Roaming/Safari/FirstBattle).
- Trainer aiFlags (574 x 0x1, 168 x 0x7) read by CFRU via pointer at 0x0800FC00.
- Doubles damage priority table identical (0x093504B0).
- Trainer items: Mega Ring 88, Z-Power Ring 28, Full Restore 50, Hyper Potion 11.

## Claims to check (function to decompile)
1. Turn flow: switch check, then item, then move (AI_TrySwitchOrUseItem 0x090C802C).
2. Scripts run per flag bit, score starts 100, max wins, random tie (BattleAI_DoAIProcessing hook target, ChooseMoveOrAction_Singles/Doubles).
3. GetAIFlags: difficulty overrides present or not (look for VarGet calls inside).
4. Dumb AI kill rate 50% (Negatives start: gRandomTurnNumber % 100 < 50, +7 / +2).
5. Damage roll 93%, crit handling (AI_CalcDmg).
6. Switching order and constants (ShouldSwitch, CalcMostSuitableMonToSwitchInto: +31/+17/+8/+14/+2/+2, -39/-15/-1).
7. Item use thresholds (ShouldAIUseItem: 25% dumb, 50% smart).
8. Positives key numbers (+9 fast KO, +2 strongest, setup gates).
9. Anti-cheese rechoose (RechooseAIMoveAfterSwitchIfNecessary) compiled in or empty.
10. AIRandom LCG constants 1103515245 / 24691.

Output: findings appended to `docs/ai-notes.md`, then player guide `docs/ai-guide.md`.
