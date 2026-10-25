# Radical Red Battle AI

How the enemy AI in **Pokemon Radical Red 4.1** decides what to do each turn: which move it picks, when it switches, which Pokemon it sends in, and how it targets in double battles. Every finding comes from the game's actual code, not guessed from play.

> **Status: beta.** All content in this repo is beta. Most findings come from reading the ROM's decompiled code; a first set has been verified in play and is collected in [`docs/verified.md`](docs/verified.md). Code findings and human verification are tracked separately (see "Tags" below): a finding gets **[VERIFIED]** only after it has been tested in game. I'm using these docs as a reference while playtesting, and will update them where the game behaves differently than the code suggests. Keep in mind that some behavior, in the code or in play, may come from a bug rather than what the code seems intended to do (the hazard re-use quirk in `docs/singles/move-or-switch.md` is one likely example), so "what the AI does" and "what the AI was meant to do" are not always the same.

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
| [`docs/verified.md`](docs/verified.md) | Rules verified in the running game, with a worked example traced turn by turn |
| [`docs/singles/move-or-switch.md`](docs/singles/move-or-switch.md) | Singles: how it scores moves, when it switches out, Hardcore's anti-switch rule |
| [`docs/singles/post-ko-switch-in.md`](docs/singles/post-ko-switch-in.md) | Singles: which Pokemon it sends in after a faint or a switch |
| [`docs/doubles/moves-and-targets.md`](docs/doubles/moves-and-targets.md) | Doubles: roles, move scoring, target choice, and why it feels random |
| [`docs/doubles/post-ko-switch-in.md`](docs/doubles/post-ko-switch-in.md) | Doubles: which Pokemon it sends in after a faint |
| [`docs/community-doc-comparison.md`](docs/community-doc-comparison.md) | Where the community AI doc matches or contradicts the code |
| [`docs/ai-notes.md`](docs/ai-notes.md) | Raw evidence and ROM addresses |

A few highlights:

- Every trainer uses the full smart AI. There are no "dumb" route trainers.
- Trainers never use items, and on 25% of turns the AI does not consider switching at all.
- The AI assumes the 9th of the 16 damage rolls (93%) when judging KOs.
- **Switch-ins never count their own damage** (verified in game): the AI picks replacements on Speed and on how well they take your hits, never on how hard they hit you. In doubles, being faster than both of your Pokemon is worth the most.
- In doubles, ties between targets are broken by KOs (counting the partner's hit), then a 25% roll for the harder-hit target, else a coin flip (verified).
- Difficulty modes share the same AI. The only difference is Hardcore's anti-switch rule.

## How this was compiled

1. **Baseline from CFRU.** Read the open-source CFRU battle AI (`src/Battle_AI/`) to learn how the AI is structured.
2. **Check Radical Red uses it.** Scanned the ROM for CFRU's code hooks (540 of 624 present) and located the AI script table and trainer data.
3. **Decompile the real code.** Used Ghidra in headless mode to decompile Radical Red's AI functions. Custom scripts fix three things that otherwise break the output for CFRU code: long calls through register stubs, Thumb switch-table helpers, and long branches inside a function.
4. **Compare rule by rule.** Diffed each decompiled function against the CFRU source, case by case, and checked key spots in raw assembly. Every rule in the docs is tagged (see "Tags" below).
5. **Cross-check with the community.** Compared the results with the community-maintained AI doc and recorded where the code agrees or disagrees.

## Tags

| Tag | Meaning | Human-verified? |
|---|---|---|
| **[ROM]** | Found by reading Radical Red's own decompiled code. | No |
| **[CFRU]** | From the CFRU source, with the surrounding Radical Red code matching. | No |
| **[VERIFIED]** | Tested in game by a person and the game behaves as described. | Yes |

[ROM] and [CFRU] are code findings only. [VERIFIED] findings are collected in [`docs/verified.md`](docs/verified.md).

Several CFRU behaviors turned out to be different in Radical Red, for example the hardcoded smart AI for all trainers, the removed item use, the reworked anti-switch counter and changes to Protect, Taunt, Counter, Sucker Punch and hazard scoring.

## Watch the AI live

Scripts for mGBA that stop the game inside the AI's own functions and print what it computed: every move's score, ties, the move chosen, and for switches the reason and the switch-in scores. They read the real decisions; nothing is simulated.

1. Get the **mGBA 0.11 development build** (stable 0.10 has no breakpoint API): https://mgba.io/downloads.html#development-downloads
2. Put your own Radical Red 4.1 ROM at `roms/rr.gba` (SHA1 above; not included).
3. Start it with the viewer: `tools/mgba/run_viewer.sh` (macOS, mGBA in `/Applications`), or open the ROM in mGBA and load `tools/mgba/rr_ai_viewer.lua` with Tools > Scripting > File > Load script.
4. Open Tools > Scripting and the "RR AI scores" tab. A block appears each time an enemy trainer Pokemon decides (wild Pokemon pick random moves and do not show).

In single battles the viewer also shows a PREDICT block from `tools/mgba/rr_model.lua` above the real scores, and a MODEL line saying how many scores it got right. Switch-ins after a faint get a prediction in singles and doubles, with the reason for each party slot's score and the battle status at that moment. Every decision is logged to `tools/mgba/logs/decisions.jsonl` with HP and RR's own damage and KO verdicts for every target; `python3 -I tools/mgba/watch_switchins.py` follows the log and prints only the switch-ins.

To replay one position many times and see how often each decision happens (the AI's randomness is seeded per run), make an mGBA savestate just before a trainer battle and run `tools/mgba/run_repeat_test.sh <state file> 50 random`. Options and the trace mode are in [`tools/README.md`](tools/README.md).

## Reproduce it

The scripts are in [`tools/`](tools/README.md). You need your own copies of both ROMs in `roms/` (not included), a clone of CFRU in `vendor/cfru`, and Ghidra with Java 21 (`brew install openjdk@21 ghidra`). See [`tools/README.md`](tools/README.md) for setup and usage.

## Open questions

- The meaning of game flag `0x10C0`, which blocks AI switching when set.
- Which bosses use special battle IDs `0x10` / `0x12`, which have small hazard and ability exceptions.
- Most findings are still code-only; see [`docs/verified.md`](docs/verified.md) for what has been checked in game.

## Disclaimer

Fan research project, not affiliated with Radical Red, CFRU, Nintendo, Game Freak or The Pokemon Company. No ROMs, ROM data or decompiled code are distributed here. Credit to Skeli789 for CFRU and to the authors of the community AI doc listed in [`docs/community-doc-comparison.md`](docs/community-doc-comparison.md).
