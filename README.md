# Radical Red Battle AI

How the enemy AI in **Pokemon Radical Red 4.1** decides what to do each turn: which move it picks, when it switches, which Pokemon it sends in, and how it targets in double battles. Every finding is checked against the game's actual code, not guessed from play.

## What is Radical Red?

[Radical Red](https://www.pokecommunity.com/threads/pok%C3%A9mon-radical-red-version-4-1-released-gen-9-dlc-pokemon-character-customization-now-available.437688/) is a difficulty-focused ROM hack of Pokemon FireRed for the Game Boy Advance, made by Soupercell and koala4. It adds Pokemon, moves and abilities from later generations, Mega Evolution, level caps and much harder trainers and bosses, with optional modes such as Restricted, Hardcore and Minimal Grinding.

Under the hood it is built on the **Complete Fire Red Upgrade (CFRU)** engine, whose battle AI is open source. Radical Red's own changes to that AI are not public. This repo fills that gap.

## Version: 4.1 only

Everything here was verified against **Radical Red 4.1**. ROM addresses, rules and numbers can change in any other version.

| ROM | SHA1 |
|---|---|
| Radical Red 4.1 (patched) | `964f951a0fdaf209e4ea1344883ef0d557bb3a80` |
| FireRed US v1.0 (base, game code BPRE) | `41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc` |

## Read the findings

Start with [`docs/ai-guide.md`](docs/ai-guide.md), then:

| Doc | Covers |
|---|---|
| [`docs/move-or-switch.md`](docs/move-or-switch.md) | Single battles: how it scores moves, when it switches out, Hardcore's anti-switch rule |
| [`docs/post-ko-switch-in.md`](docs/post-ko-switch-in.md) | Which Pokemon it sends in after a faint or a switch |
| [`docs/double-battles.md`](docs/double-battles.md) | Doubles: roles, move scoring, target choice, and why it feels random |
| [`docs/community-doc-comparison.md`](docs/community-doc-comparison.md) | Where the community AI doc matches or contradicts the code |
| [`docs/ai-notes.md`](docs/ai-notes.md) | Raw evidence and ROM addresses |

A few highlights:

- Every trainer uses the full smart AI. There are no "dumb" route trainers.
- Trainers never use items, and on 25% of turns the AI does not consider switching at all.
- The AI assumes the 9th of the 16 damage rolls (93%) when judging KOs, and the 12th (96%) for switch-ins.
- Difficulty modes share the same AI. The only difference is Hardcore's anti-switch rule.

## How this was compiled

1. **Baseline from CFRU.** Read the open-source CFRU battle AI (`src/Battle_AI/`) to learn how the AI is structured.
2. **Confirm Radical Red uses it.** Scanned the ROM for CFRU's code hooks (540 of 624 present) and located the AI script table and trainer data.
3. **Decompile the real code.** Used Ghidra in headless mode to decompile Radical Red's AI functions. Custom scripts fix three things that otherwise break the output for CFRU code: long calls through register stubs, Thumb switch-table helpers, and long branches inside a function.
4. **Compare rule by rule.** Diffed each decompiled function against the CFRU source, case by case, and checked key spots in raw assembly. Every rule in the docs is tagged **[ROM]** (confirmed in Radical Red's code) or **[CFRU]** (from the source, with the surrounding Radical Red code matching).
5. **Cross-check with the community.** Compared the results with the community-maintained AI doc and recorded where the code agrees or disagrees.

Several CFRU behaviors turned out to be different in Radical Red, for example the hardcoded smart AI for all trainers, the removed item use, the reworked anti-switch counter and changes to Protect, Taunt, Counter, Sucker Punch and hazard scoring.

## Reproduce it

The scripts are in [`tools/`](tools/README.md). You need your own copies of both ROMs in `roms/` (not included), a clone of CFRU in `vendor/cfru`, and Ghidra with Java 21 (`brew install openjdk@21 ghidra`). See [`tools/README.md`](tools/README.md) for setup and usage.

## Not yet verified

- The meaning of game flag `0x10C0`, which blocks AI switching when set.
- Which bosses use special battle IDs `0x10` / `0x12`, which have small hazard and ability exceptions.
- No live emulator testing yet. All findings come from reading the code.

## Disclaimer

Fan research project, not affiliated with Radical Red, CFRU, Nintendo, Game Freak or The Pokemon Company. No ROMs, ROM data or decompiled code are distributed here. Credit to Skeli789 for CFRU and to the authors of the community AI doc listed in [`docs/community-doc-comparison.md`](docs/community-doc-comparison.md).
