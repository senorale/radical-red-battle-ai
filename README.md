# Radical Red Battle AI

How the enemy AI in **Pokemon Radical Red 4.1** decides what to do each turn: which move it picks, when it switches, which Pokemon it sends in, and how it targets in double battles. Every finding comes from the game's actual code, not guessed from play.

> **Status: beta.** All content in this repo is beta. Most findings come from reading the ROM's decompiled code; a first set has been tested in play (one playthrough, up to the second gym so far) and is collected in [`docs/findings.md`](docs/findings.md). Each finding carries a confidence tag (see "Tags" below), from [HYPOTHESIS] (code only) to [VERIFIED] (logs and our model's predictions both match the game). I'm using these docs as a reference while playtesting, and will update them where the game behaves differently than the code suggests. Keep in mind that some behavior, in the code or in play, may come from a bug rather than what the code seems intended to do (the hazard re-use quirk in `docs/singles/move-or-switch.md` is one likely example), so "what the AI does" and "what the AI was meant to do" are not always the same.

## What is Radical Red?

[Radical Red](https://www.pokecommunity.com/threads/pok%C3%A9mon-radical-red-version-4-1-released-gen-9-dlc-pokemon-character-customization-now-available.437688/) is a difficulty-focused ROM hack of Pokemon FireRed for the Game Boy Advance, made by Soupercell and koala4. It adds Pokemon, moves and abilities from later generations, Mega Evolution, level caps and much harder trainers and bosses, with optional modes such as Restricted, Hardcore and Minimal Grinding.

Under the hood it is built on the **Complete Fire Red Upgrade (CFRU)** engine, whose battle AI is open source. Radical Red's own changes to that AI are not public. This repo fills that gap.

## Version: 4.1 only

Everything here was researched against **Radical Red 4.1**. ROM addresses, rules and numbers can change in any other version.

| ROM | SHA1 |
|---|---|
| Radical Red 4.1 (patched) | `964f951a0fdaf209e4ea1344883ef0d557bb3a80` |
| FireRed US v1.0 (base, game code BPRE) | `41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc` |

## Read the findings

Start with [`docs/ai-guide.md`](docs/ai-guide.md), then:

| Doc | Covers |
|---|---|
| [`docs/findings.md`](docs/findings.md) | Rules seen in the running game, tagged by confidence, with the evidence and a worked example traced turn by turn |
| [`docs/singles/move-or-switch.md`](docs/singles/move-or-switch.md) | Singles: how it scores moves, when it switches out, Hardcore's anti-switch rule |
| [`docs/singles/post-ko-switch-in.md`](docs/singles/post-ko-switch-in.md) | Singles: which Pokemon it sends in after a faint or a switch |
| [`docs/doubles/moves-and-targets.md`](docs/doubles/moves-and-targets.md) | Doubles: roles, move scoring, target choice, and why it feels random |
| [`docs/doubles/post-ko-switch-in.md`](docs/doubles/post-ko-switch-in.md) | Doubles: which Pokemon it sends in after a faint |
| [`docs/community-doc-comparison.md`](docs/community-doc-comparison.md) | Where the community AI doc matches or contradicts the code |
| [`docs/ai-notes.md`](docs/ai-notes.md) | Raw evidence and ROM addresses |

A few highlights:

- Every trainer uses the full smart AI. There are no "dumb" route trainers.
- Trainers never use items, and on 25% of turns the AI does not consider switching at all.
- When judging KOs, the AI takes the highest damage roll and cuts the final damage to 93%. This is often not the 9th of the 16 rolls, and sometimes not any of the 16 rolls (see "How the AI estimates damage" below).
- **Switch-ins do not count their own damage** (the bench damage cache bug, [`docs/findings.md`](docs/findings.md) rule 14, [OBSERVED] in every switch-in logged so far): the AI picks replacements on Speed and on how well they take your hits, not on how hard they hit you. In doubles, being faster than both of your Pokemon is worth the most.
- In doubles, ties between targets are broken by KOs (counting the partner's hit), then a 25% roll for the harder-hit target, else a coin flip ([TESTED]).
- Difficulty modes share the same AI. The only difference is Hardcore's anti-switch rule.

## How the AI estimates damage

Every "can I KO you?" check uses one damage number per move. RR computes it in `0x09087080` [TESTED]:

```
AI damage = floor(max roll x 93 / 100)
```

The max roll is the normal damage formula with the random factor at 100%, after STAB, type effectiveness, items and abilities. The 93% is applied once, to the final number. (RR then caps it at your current HP. A crit stage of 2 adds a 50% chance of x1.5, and stage 3 or more always does.)

It is easy to read this as "the AI uses the 9th of the 16 rolls", since the 9th roll's random factor is also 93% (the factors run 85, 86, ... 100). It is not the same number. The game applies the random factor in the middle of the formula, before STAB and type effectiveness, and rounds down at each step. The AI's 93% comes after all of that.

**Example** (Dynamic-Calc engine, Gen 8 mechanics, level 20): Garchomp's Earthquake into Heatran, STAB and x4.

| | Step by step | Result |
|---|---|---|
| 9th roll | base 32, x93% = 29.76 rounds to 29, STAB x1.5 = 43.5 rounds to 43, x4 | **172** |
| AI damage | base 32, x100%, STAB x1.5 = 48, x4 = 192 (the max roll), then x93/100 = 178.56 | **178** |

The 16 possible rolls are `160, 160, 160, 168, 168, 168, 172, 172, 172, 180, 180, 180, 184, 184, 184, 192`. They jump in steps of 4 because x4 is applied after the random factor. The AI's 178 falls between two rolls: it is not any damage the move can actually do. Against a target with 175 HP, the AI believes it KOs (178), the 9th roll says it does not (172), and in the real game it KOs on 7 of the 16 rolls.

**How big the gap gets** (same calc, 24 matchups from level 20 to 100, physical and special, neutral to x4): AI damage minus the 9th roll ranged from -2 to +6 HP. It matched exactly in 7 of 24, and was one of the 16 possible rolls in only 8 of 24. The gap grows with the multipliers applied after the random factor (STAB, super-effective), not with level: neutral non-STAB hits matched every time, the x4 hit had the largest gap. Near a KO threshold this decides whether the AI thinks it kills, and with it the +9 "KO and goes first" bonus (`docs/findings.md` rule 7).

**Evidence:** the formula is read in the decompile of `0x09087080` (the damage call `0x09085A10` has no random roll; then `x 0x5D / 100`). On one battle (`rr.ss6`, sandstorm), RR's cached AI damage matched `floor(max roll x 93 / 100)` from Dynamic-Calc in 6 of 6 moves, while the 9th roll matched 4 of 6 (Body Slam: 9th roll 6, RR 5; Sucker Punch: 9th roll 21, RR 22). Crit stages and multi-hit moves are not tested yet.

## How this was compiled

1. **Baseline from CFRU.** Read the open-source CFRU battle AI (`src/Battle_AI/`) to learn how the AI is structured.
2. **Check Radical Red uses it.** Scanned the ROM for CFRU's code hooks (540 of 624 present) and located the AI script table and trainer data.
3. **Decompile the real code.** Used Ghidra in headless mode to decompile Radical Red's AI functions. Custom scripts fix three things that otherwise break the output for CFRU code: long calls through register stubs, Thumb switch-table helpers, and long branches inside a function.
4. **Compare rule by rule.** Diffed each decompiled function against the CFRU source, case by case, and checked key spots in raw assembly. Every rule in the docs is tagged (see "Tags" below).
5. **Cross-check with the community.** Compared the results with the community-maintained AI doc and recorded where the code agrees or disagrees.

## Tags

| Tag | Meaning | Seen in game? |
|---|---|---|
| **[HYPOTHESIS]** | Read in Radical Red's own decompiled code, not tested yet. **[HYPOTHESIS, CFRU]**: from the CFRU source, with the surrounding Radical Red code matching. | No |
| **[OBSERVED]** | A behavior seen repeatedly in game that the code found so far does not explain. | Yes |
| **[TESTED]** | A code hypothesis supported by in-game output from our tools (viewer logs, repeat tests, traces). | Yes |
| **[VERIFIED]** | Tested, and our model's predictions also match the real game. | Yes |

All of these are leading hypotheses from a limited sample. [OBSERVED], [TESTED] and [VERIFIED] findings are collected in [`docs/findings.md`](docs/findings.md) with the evidence and its size.

Several CFRU behaviors turned out to be different in Radical Red, for example the hardcoded smart AI for all trainers, the removed item use, the reworked anti-switch counter and changes to Protect, Taunt, Counter, Sucker Punch and hazard scoring.

## Watch the AI live

Scripts for mGBA that stop the game inside the AI's own functions and print what it computed: every move's score, ties, the move chosen, and for switches the reason and the switch-in scores. They read the real decisions; nothing is simulated.

> **Quick start**
> - **You need:** the **mGBA 0.11 development build** (the stable 0.10 release has no breakpoint API and will not work), and your own Radical Red 4.1 ROM (SHA1 above, not included). Python 3 is only needed for the optional extras below.
> - **Start:** open your ROM in mGBA, then Tools > Scripting > File > Load script > `tools/mgba/rr_ai_viewer.lua`. On macOS, `tools/mgba/run_viewer.sh` does both if the ROM is at `roms/rr.gba`.
> - **You will see:** a "RR AI scores" tab in the Scripting window that says "RR AI viewer ready". Start a trainer battle: each enemy decision, switch check and switch-in appears there. Wild Pokemon do not show (they pick moves at random).
> - **Logs:** everything is also written to `tools/mgba/logs/` (`decisions.jsonl`, `viewer.log`). If the tab shows a "cannot write" warning, create that folder.
> - **Optional (Python 3):** `python3 -I tools/mgba/watch_switchins.py` in a terminal prints switch checks and switch-ins as they happen; `tools/mgba/run_repeat_test.sh` replays a savestate many times (see below).

1. Get the **mGBA 0.11 development build** (stable 0.10 has no breakpoint API): https://mgba.io/downloads.html#development-downloads
2. Put your own Radical Red 4.1 ROM at `roms/rr.gba` (SHA1 above; not included).
3. Start it with the viewer: `tools/mgba/run_viewer.sh` (macOS, mGBA in `/Applications`), or open the ROM in mGBA and load `tools/mgba/rr_ai_viewer.lua` with Tools > Scripting > File > Load script.
4. Open Tools > Scripting and the "RR AI scores" tab. A block appears each time an enemy trainer Pokemon decides (wild Pokemon pick random moves and do not show).

In single battles the viewer also shows a PREDICT block from `tools/mgba/rr_model.lua` above the real scores, and a MODEL line saying how many scores it got right. Switch-ins after a faint get a prediction in singles and doubles, with the reason for each party slot's score and the battle status at that moment. Every decision is logged to `tools/mgba/logs/decisions.jsonl` with HP and RR's own damage and KO verdicts for every target; `python3 -I tools/mgba/watch_switchins.py` follows the log and prints only the switch-ins.

To replay one position many times and see how often each decision happens (the AI's randomness is seeded per run), make an mGBA savestate just before a trainer battle and run `tools/mgba/run_repeat_test.sh <state file> 50 random`. Options and the trace mode are in [`tools/README.md`](tools/README.md).

## Export your team to the damage calc

`tools/mgba/rr_showdown_export.lua` exports your party and all 25 PC boxes as Showdown text (species, item, ability, level, nature, EVs, IVs, moves) that imports into [hzla's Dynamic-Calc-Decomps calc](https://hzla.github.io/Dynamic-Calc-Decomps/?data=e91164d90d06a009e6cc&dmgGen=8&gen=8&types=6&noSwitch=1&view=calculator) (Radical Red data sets). It works from any point in the game, including savestates and mid-battle, and also lists each Pokemon's Hidden Power type.

1. Open your ROM in mGBA (tested on the 0.11 development build; the exporter uses no breakpoints, so stable 0.10 may work but is untested), then Tools > Scripting > File > Load script > `tools/mgba/rr_showdown_export.lua`. It can run next to the AI viewer.
2. The export is written to `tools/mgba/logs/showdown.txt` and shown in the "Showdown Export" tab. Type `export()` in the scripting console to refresh it after changes in game.
3. Copy the text from `showdown.txt` (copying from the mGBA tab adds a blank line between lines, which breaks the import) and paste it into the calc's import box.

Abilities follow Radical Red's own rules, including the randomized-abilities option and the ability changes for your own Pokemon in the modes that use them. Names are spelled as the calc spells them (`tools/mgba/rr_calc_names.lua`, generated from the calc's tables by `gen_calc_names.js`).

## Reproduce it

The scripts are in [`tools/`](tools/README.md). You need your own copies of both ROMs in `roms/` (not included), a clone of CFRU in `vendor/cfru`, and Ghidra with Java 21 (`brew install openjdk@21 ghidra`). See [`tools/README.md`](tools/README.md) for setup and usage.

## Open questions

- The meaning of game flag `0x10C0`, which blocks AI switching when set.
- Which bosses use special battle IDs `0x10` / `0x12`, which have small hazard and ability exceptions.
- Most findings are still code-only; see [`docs/findings.md`](docs/findings.md) for what has been checked in game.

## Disclaimer

Fan research project, not affiliated with Radical Red, CFRU, Nintendo, Game Freak or The Pokemon Company. No ROMs, ROM data or decompiled code are distributed here. Credit to Skeli789 for CFRU and to the authors of the community AI doc listed in [`docs/community-doc-comparison.md`](docs/community-doc-comparison.md).
