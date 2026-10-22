# Radical Red 4.1: How the Enemy AI Decides

As of 2026-10-22. Built from the CFRU source (the engine Radical Red is built on) and checked against the Radical Red 4.1 ROM with Ghidra. Start here, then read the topic docs:

| Doc | Covers |
|---|---|
| [`move-or-switch.md`](move-or-switch.md) | Single battles: how it picks a move, when it switches out, Hardcore anti-switch rule |
| [`post-ko-switch-in.md`](post-ko-switch-in.md) | Which Pokemon it sends in, after a faint or a voluntary switch |
| [`double-battles.md`](double-battles.md) | Doubles: roles, move scoring, target choice, partner coordination, why it feels random |
| [`community-doc-comparison.md`](community-doc-comparison.md) | How the community AI doc compares to the ROM findings |
| [`ai-notes.md`](ai-notes.md) | Raw evidence and ROM addresses |

## How to read these docs

- **[ROM]** = confirmed by reading Radical Red's own compiled code.
- **[CFRU]** = from the CFRU source. The surrounding Radical Red code was checked and matches, but this specific rule was not line-checked.
- **Score** = every move starts at 100 each turn. Rules add or subtract points. The highest score wins. Ties are broken at random. Only the order matters, so "+9" beats "+2".
- "You" means the player. "AI" means the opposing trainer's Pokemon.

## 1. The big picture

| Fact | Detail | Source |
|---|---|---|
| Every trainer uses the full smart AI | Radical Red ignores the per-trainer AI setting and gives every trainer battle the full "Check Bad Move + Check Good Move" AI. There are no "dumb" route trainers. | [ROM] |
| Wild Pokemon act randomly | Wild battles get no scoring scripts, so they pick any usable move at random. Scripted legendary encounters use a lighter "semi-smart" AI. | [ROM] |
| Difficulty does not change AI intelligence | No difficulty variable is read when picking AI flags. Hardcore Mode only adds the anti-switch rule (`move-or-switch.md` section 6). | [ROM] |
| Trainers never use items | The item-use step was removed. Full Restores listed in trainer data are never used. | [ROM] |
| The AI sees everything | It reads your real moves, ability, held item, stats, stat stages and speed, including whether your Quick Claw will activate this turn. | [CFRU] |
| It predicts your move | Each turn it scores your moveset with its own rules and assumes you pick the top move. If none of your moves scores at least 100, it predicts you will switch. | [CFRU] |
| Megas are planned ahead | Before deciding, it evaluates every Pokemon that will Mega Evolve (yours and its own) as already Mega Evolved. | [CFRU] |

## 2. How the AI judges damage

| Rule | Detail | Source |
|---|---|---|
| Damage roll | Real damage uses one of 16 equally likely rolls, 85% to 100% (`100 - (Random() & 15)`). For the Pokemon on the field the AI always assumes the 93% roll: the 9th of 16, sorted low to high. For benched Pokemon (switch-in decisions) it assumes 96%: the 12th of 16. No randomness in either assumption. Estimates can be off by about 1 HP from rounding. | [ROM] |
| "Can KO" | The AI treats a move as a KO only if the 9th roll reaches your current HP. On a damage calc, check the 9th of the 16 rolls. If you sit right at that threshold, the real KO chance is only about 50% (rolls 93 to 100). If the 9th roll falls short, the AI does not plan for the KO, even though the higher rolls (94 to 100) can still kill you. | [ROM] |
| Crits | Counted only for guaranteed crits, or moves with 50%+ crit chance (then a coin flip). | [ROM] |
| Sturdy / Focus Sash | Single hits are capped at HP-1. Multi-hit moves and Disguise/Substitute are handled. | [ROM] |
| Fixed damage | Super Fang = half HP, Seismic Toss/Night Shade = level, Endeavor and Pain Split exact. | [ROM] |
| Strongest move | Highest damage, capped at your HP. When several moves all KO, it prefers: higher priority, then better accuracy, then non-contact (if contact is punished), then no recoil, then no stat drop, then random. Counter/Mirror Coat/Future Sight never win a tie. Pursuit is preferred once you have shown you like switching. | [CFRU] |

## 3. Not yet verified

- The exact meaning of game flag 0x10C0 (it blocks AI switching when set).
- Which bosses use special battle ID 0x10 / 0x12 (minor hazard and ability exceptions).
- No live testing in an emulator yet. All results come from reading the code.

## Sources

- CFRU source: github.com/Skeli789/Complete-Fire-Red-Upgrade (commit b637a27), `src/Battle_AI/`.
- Radical Red 4.1 ROM (`roms/rr.gba`), decompiled with Ghidra 12.1.4. Key addresses: GetAIFlags 0x090C77B0, AI_TrySwitchOrUseItem 0x090C802C, ShouldSwitch 0x090D824C, switch-in scoring 0x090D7168, Negatives 0x090C904C, Positives 0x090D10D4, AI damage calc 0x09087080, Hardcore re-pick 0x090C8F04 / 0x090C8CA4, doubles chooser 0x090C82C0.
- Full working notes: `ai-notes.md`.
