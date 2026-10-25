-- Radical Red 4.1 AI predictor (singles), built only from the rules in docs/verified.md and data
-- read from RR's ROM and RAM. Every reads goes through `mem` (mGBA's `emu` or a fake).
-- It predicts, it does not run the game's AI: where the rules need something not modelled yet the
-- move is marked with "?" (low confidence) and kept at its known score.
--
-- RR data used (evidence in docs/verified.md and the comments below):
--   gBattleMoves 0x091521D0, 12 bytes: +0 effect, +1 power, +2 type, +3 accuracy, +5 secondary
--     chance (0x090DB220), +7 priority (signed, 0x090DC344), +10 split (0 phys, 1 spec, 2 status).
--   Type chart 0x09146CE2 + attackType * 0x18 + defenderType (0x09082090): 0 = x1, 5 = x0.5,
--     20 = x2, 1 = immune.
--   Roles: RR's 0x090C40C4 singles path (docs/verified.md rule 8).
--
-- Inputs read from RR's own caches when present (opts.cache), so the test is on the scoring
-- rules, not on damage formulas: AI damage per move gNewBS +0x2F0 (0x090DEAC4), strongest move
-- gNewBS +0x22E (0x090DFE00; can lag one Pokemon behind after a faint replacement), the AI's
-- predicted move for you gNewBS +0x1EE (used for turn order, MoveWouldHitFirst 0x090DA062).
--
-- Approximations, each a likely source of mismatches to chase:
--   damage fallback (no cache): generic Gen 5+ formula, multi-hit x3, no items/abilities/weather.
--   speed: RR's stage table and weather abilities, Tailwind, paralysis; no held items.
--   role: no Choice item / ability / Assault Vest check, hazards counted even if already set.
--   "good idea to boost": you have no phazing move, cannot 2HKO it, and it does not KO first.
--   status moves other than healing, poison, Stockpile and stat boosts are not scored ("?").
--   switch checks: only the 25% roll.
-- Measured on two rr.ss6 battle paths (mash A; switch to Pignite on turn 1, 31 enemy move decisions):
-- every move score matched except Recover at full HP once (bonus via 0x090C4C08, not modelled).

local S = require("rr_state")
local M = {}

M.MOVES, M.MOVE_SIZE = 0x091521D0, 12
M.TYPE_CHART = 0x09146CE2
M.KO_ROLL = 93 -- percent; the AI's assumed damage roll for KO checks (from docs/ai-guide.md, not yet verified)

local function s8(v) return v >= 128 and v - 256 or v end

function M.move(mem, id, mon)
	local a = M.MOVES + id * M.MOVE_SIZE
	local mv = {
		id = id, effect = mem:read8(a), power = mem:read8(a + 1), type = mem:read8(a + 2),
		accuracy = mem:read8(a + 3), chance = mem:read8(a + 5), priority = s8(mem:read8(a + 7)),
		split = mem:read8(a + 10), flags = mem:read8(a + 8), name = S.move_name(mem, id),
	}
	-- Hidden Power (0xED): type from the IVs' low bits, x15/63, +1, +2 past Steel (0x090830A8).
	if id == 0xED and mon then
		local bits = 0
		for k = 1, 6 do bits = bits | ((mon.ivs[k] & 1) << (k - 1)) end
		local t = bits * 15 // 63 + 1
		if t > 8 then t = t + 1 end
		mv.type = t
	end
	return mv
end

-- Type effectiveness of a move type against a battle mon (x0, x0.25 ... x4).
function M.effectiveness(mem, mtype, mon)
	local mult = 1
	local seen = {}
	for _, t in ipairs({ mon.type1, mon.type2, mon.type3 }) do
		if t ~= 9 and t ~= 0x13 and t ~= 0x14 and not seen[t] then
			seen[t] = true
			local v = mem:read8(M.TYPE_CHART + mtype * 0x18 + t)
			if v == 1 then mult = 0 elseif v == 5 then mult = mult / 2 elseif v == 20 then mult = mult * 2 end
		end
	end
	return mult
end

local STAGE = { [0] = { 2, 8 }, { 2, 7 }, { 2, 6 }, { 2, 5 }, { 2, 4 }, { 2, 3 }, { 2, 2 }, { 3, 2 }, { 4, 2 }, { 5, 2 }, { 6, 2 }, { 7, 2 }, { 8, 2 } }
local function staged(value, stage) local r = STAGE[stage + 6] or STAGE[6]; return value * r[1] // r[2] end

-- Speed as RR's SpeedCalc 0x0906F284 computes it, partly: stage ratio table 0x09124898 (num, den
-- per stage), weather abilities 0x0906E320 (Sand Rush 0x7C in sandstorm 0x18, Swift Swim 0x21 in
-- rain 0x1007, Chlorophyll 0x22 in sun 0x860, Slush Rush 0xAB in hail 0x180: x2), Tailwind
-- (gNewBS +0x13 +side: x2), paralysis /2 unless Quick Feet 0x70 (x2 when statused).
-- Not modelled: held items (0x0906E2B4), Cloud Nine, Utility Umbrella, Unburden-type, 0x09075480.
M.STAGE_TABLE = 0x09124898
M.WEATHER = 0x02023F1C
function M.speed(mem, mon)
	local st = mon.stages.spe
	local v = mon.speed * mem:read8(M.STAGE_TABLE + st * 2) // mem:read8(M.STAGE_TABLE + st * 2 + 1)
	local w = mem:read16(M.WEATHER)
	local ab = mon.ability
	if (ab == 0x7C and w & 0x18 ~= 0) or (ab == 0x21 and w & 0x1007 ~= 0) or
		(ab == 0x22 and w & 0x860 ~= 0) or (ab == 0xAB and w & 0x180 ~= 0) then v = v * 2 end
	if mem:read8(mem:read32(M.GNEWBS) + 0x13 + (mon.battler & 1)) ~= 0 then v = v * 2 end
	if mon.status1 & 0xFF ~= 0 and ab == 0x70 then v = v * 2
	elseif mon.status1 & 0x40 ~= 0 then v = v // 2 end
	return v
end

-- Item hold effect and parameter (item table 0x093C0000, 44 bytes: +0x12 effect, +0x13 parameter).
M.ITEMS = 0x093C0000
function M.hold(mem, item)
	if item == 0 then return 0, 0 end
	local a = M.ITEMS + item * 44
	return mem:read8(a + 0x12), mem:read8(a + 0x13)
end

-- RR ability IDs (name table 0x090E32C0, tools/rom/ability_ids.py).
local AB = { HUGE_POWER = 37, HUSTLE = 55, GUTS = 62, OVERGROW = 65, BLAZE = 66, TORRENT = 67, SWARM = 68,
	DEFEATIST = 144, STRONG_JAW = 129, TECHNICIAN = 82, IRON_FIST = 93, TOUGH_CLAWS = 128, SHEER_FORCE = 92,
	ADAPTABILITY = 88, MEGA_LAUNCHER = 127, SKILL_LINK = 79, THICK_FAT = 47, WATER_ABSORB = 11, STORM_DRAIN = 131,
	DRY_SKIN = 98, VOLT_ABSORB = 10, LIGHTNING_ROD = 31, MOTOR_DRIVE = 80, FLASH_FIRE = 18, SAP_SIPPER = 113,
	LEVITATE = 26, WONDER_GUARD = 25, FILTER = 263, SOLID_ROCK = 100, MULTISCALE = 81, FUR_COAT = 148, ICE_SCALES = 248 }
local function has_word(name, words) for _, w in ipairs(words) do if name:find(w, 1, true) then return true end end return false end

-- Damage estimate following RR's AI damage (0x09087080 -> 0x09085A10, then x93/100): the main
-- stat, ability, item, weather and type factors; not every special case. roll in percent.
function M.damage(mem, atk, def, mv, roll)
	if mv.split == 2 or mv.power == 0 then return 0 end
	local t = mv.type
	-- Immunities from abilities.
	local da = def.ability
	if (t == 11 and (da == AB.WATER_ABSORB or da == AB.STORM_DRAIN or da == AB.DRY_SKIN)) or
		(t == 13 and (da == AB.VOLT_ABSORB or da == AB.LIGHTNING_ROD or da == AB.MOTOR_DRIVE)) or
		(t == 10 and da == AB.FLASH_FIRE) or (t == 12 and da == AB.SAP_SIPPER) or (t == 4 and da == AB.LEVITATE) then
		return 0
	end
	local eff = M.effectiveness(mem, t, def)
	if eff == 0 or (da == AB.WONDER_GUARD and eff <= 1) then return 0 end
	local power = mv.power
	local aa = atk.ability
	if aa == AB.TECHNICIAN and power <= 60 then power = power * 3 // 2 end
	if aa == AB.STRONG_JAW and has_word(mv.name, { "Bite", "Fang", "Crunch", "Jaw" }) then power = power * 3 // 2 end
	if aa == AB.IRON_FIST and mv.name:find("Punch", 1, true) then power = power * 6 // 5 end
	if aa == AB.MEGA_LAUNCHER and has_word(mv.name, { "Pulse", "Aura Sphere" }) then power = power * 3 // 2 end
	if aa == AB.TOUGH_CLAWS and mv.flags and mv.flags & 1 ~= 0 then power = power * 13 // 10 end
	if aa == AB.SHEER_FORCE and mv.chance > 0 then power = power * 13 // 10 end
	local he, hp_ = M.hold(mem, atk.item)
	if he == 0x81 and hp_ == t then power = power * 6 // 5 end -- type-boosting item
	local a, d
	local def_item_e = M.hold(mem, def.item)
	if mv.split == 0 then
		a, d = staged(atk.attack, atk.stages.atk - 6), staged(def.defense, def.stages.def - 6)
		if aa == AB.HUGE_POWER then a = a * 2 end
		if aa == AB.HUSTLE then a = a * 3 // 2 end
		if aa == AB.GUTS and atk.status1 ~= 0 then a = a * 3 // 2 end
		if da == AB.FUR_COAT then d = d * 2 end
	else
		a, d = staged(atk.sp_attack, atk.stages.spa - 6), staged(def.sp_defense, def.stages.spd - 6)
		local w = mem:read16(M.WEATHER)
		if w & 0x18 ~= 0 and (def.type1 == 5 or def.type2 == 5 or def.type3 == 5) then d = d * 3 // 2 end
	end
	if def.item == 700 then d = d * 3 // 2 end -- Eviolite (assumes it can still evolve)
	if aa == AB.DEFEATIST and atk.hp * 2 <= atk.max_hp then a = a // 2 end
	if atk.hp * 3 <= atk.max_hp and ((aa == AB.OVERGROW and t == 12) or (aa == AB.BLAZE and t == 10) or
		(aa == AB.TORRENT and t == 11) or (aa == AB.SWARM and t == 6)) then a = a * 3 // 2 end
	if da == AB.THICK_FAT and (t == 10 or t == 15) then a = a // 2 end
	if d < 1 then d = 1 end
	local base = ((2 * atk.level) // 5 + 2) * power * a // d // 50 + 2
	local w = mem:read16(M.WEATHER)
	if w & 0x07 ~= 0 then -- rain
		if t == 11 then base = base * 3 // 2 elseif t == 10 then base = base // 2 end
	elseif w & 0x60 ~= 0 then -- sun
		if t == 10 then base = base * 3 // 2 elseif t == 11 then base = base // 2 end
	end
	if mv.type == atk.type1 or mv.type == atk.type2 or mv.type == atk.type3 then
		base = aa == AB.ADAPTABILITY and base * 2 or base * 3 // 2
	end
	base = math.floor(base * eff)
	if eff > 1 then
		local de, dp = M.hold(mem, def.item)
		if de == 0x5F and dp == t then base = base // 2 end -- resist berry
		if da == AB.FILTER or da == AB.SOLID_ROCK then base = base * 3 // 4 end
	end
	if da == AB.MULTISCALE and def.hp == def.max_hp then base = base // 2 end
	if da == AB.ICE_SCALES and mv.split == 1 then base = base // 2 end
	if mv.split == 0 and atk.status1 & 0x10 ~= 0 and aa ~= AB.GUTS then base = base // 2 end -- burn
	if mv.effect == 0x1D then base = base * (aa == AB.SKILL_LINK and 5 or 2) end -- multi-hit: RR assumes 2 hits
	return base * roll // 100
end

-- RR role (docs/verified.md rule 8), singles path of 0x090C40C4, without the Choice/Assault Vest check.
local BOOST = {}
for e = 0x0A, 0x10 do BOOST[e] = true end
for e = 0x32, 0x38 do BOOST[e] = true end
for _, e in ipairs({ 0x8B, 0xCE, 0xD0, 0xD3, 0xD4 }) do BOOST[e] = true end
M.ROLE_NAMES = { [1] = "pure attacker", [2] = "setup stats sweeper", [3] = "setup status sweeper",
	[5] = "stall", [6] = "Baton Pass support", [7] = "cleric", [8] = "screens support",
	[9] = "phazing support", [10] = "hazard setter" }

function M.role(mem, mon)
	local attacks, status, screens, hazards = 0, 0, 0, 0
	local boosting, roar, leech, protect = false, false, false, false
	for i = 0, 3 do
		local id = mon.moves[i]
		if id ~= 0 then
			local mv = M.move(mem, id)
			local e = mv.effect
			if id == 0xE2 then return 6 end -- Baton Pass (viable-count check not modelled)
			if e == 0x19 or e == 0xDE then return 9 end
			if e == 0x66 or e == 0xB3 then return 7 end
			if e == 0x2A or e == 0x6A then return 5 end
			if e == 0x23 or e == 0x41 then screens = screens + 1 end
			if e == 0x1C then roar = true end
			if e == 0x54 then leech = true end
			if e == 0x6F then protect = true end
			if mv.split == 2 then
				if e == 0x70 then hazards = hazards + 1 -- "already set" check not modelled
				elseif BOOST[e] then boosting = true
				else status = status + 1 end
			else
				attacks = attacks + 1
				if BOOST[e] then boosting = true end
			end
		end
	end
	if screens > 0 then return 8 end
	if hazards > 0 then return roar and 9 or 10 end
	if attacks >= 3 then
		if boosting then return 2 end
		if status == 0 then return 1 end
		return 3
	end
	if attacks == 2 and not (leech and protect) then
		if boosting then return 2 end
		if status > 0 or roar then return 3 end
	end
	return 5
end

-- Slow-KO bonus by role (0x090C69F4), without the "KO the last Pokemon" and 2HKO refinements.
local SLOW_KO = { [1] = 8, [2] = 6, [3] = 8, [5] = 8, [6] = 8, [7] = 7, [8] = 9, [9] = 8, [10] = 6 }
-- Status-move bonus by role (0x090C5C90), boost added where the table says so.
local function status_bonus(role, boost, foe_can_2hko)
	if role == 2 then return foe_can_2hko and 0 or 3 + boost end
	if role == 3 or role == 9 then return 4 + boost end
	if role == 8 then return 2 + boost end
	if role == 5 or role == 7 then return 3 + boost end
	if role == 6 then return boost >= 3 and 1 or 0 end
	if role == 10 then return 3 end
	return 0
end

-- Stat-boost bonus by role (0x090C5D0C, table 0x090C5E0E). "Good idea to boost" (0x090C3C64), singles:
-- no if you have a Roar/Whirlwind/Haze-type move (a 50% main-Random coin can skip this; not modelled);
-- if the AI moves first: yes when you cannot KO it, counting its end-of-turn chip (0x090E031C,
-- 0x090DADF8), and the stat is below +3; if it moves second: yes when you cannot 2HKO it and the
-- stat is below +4. Returns nil when no bonus.
local STAT_BOOST = { [1] = 5, [2] = 5, [3] = 5, [5] = 4, [7] = 4, [8] = 3, [9] = 5, [10] = 3 }
-- Stat each boosting effect raises (stage index name in rr_state).
local BOOST_STAT = { [0x0A] = "atk", [0x32] = "atk", [0x8B] = "atk", [0xD0] = "atk", [0xD4] = "atk",
	[0x0B] = "def", [0x33] = "def", [0xA0] = "def", [0xCE] = "def", [0x0C] = "spe", [0x34] = "spe",
	[0x0D] = "spa", [0x35] = "spa", [0xD3] = "spa", [0x0E] = "spd", [0x36] = "spd" }
local function stat_boost(role, effect, ai, ctx)
	if ctx.foe_phazes then return nil end
	local stage = ai.stages[BOOST_STAT[effect] or "atk"] - 6
	if ctx.ai_first then
		if ctx.foe_can_ko or stage >= 3 then return nil end
	else
		if ctx.foe_can_2hko or stage >= 4 then return nil end
	end
	return STAT_BOOST[role]
end

-- RR's AI damage cache (0x090DEAC4): u32 at gNewBS + 0x2F0 + ((atk*4 + def)*4 + slot)*4,
-- 0xFFFFFFFF = not computed yet. Predicted moves: u16 at gNewBS + 0x1EE + (bank*4 + target)*2
-- (read by MoveWouldHitFirst 0x090DA0D2).
M.GNEWBS = 0x0203E038
function M.cached_damage(mem, atk_b, def_b, slot)
	local v = mem:read32(mem:read32(M.GNEWBS) + 0x2F0 + ((atk_b * 4 + def_b) * 4 + slot) * 4)
	if v == 0xFFFFFFFF then return nil end
	return v
end
-- Strongest-move cache (IsStrongestMove 0x090DFE00): u16 move ID at gNewBS + 0x22E + (atk*4 + def)*2.
function M.cached_strongest(mem, atk_b, def_b)
	local v = mem:read16(mem:read32(M.GNEWBS) + 0x22E + (atk_b * 4 + def_b) * 2)
	if v == 0xFFFF then return nil end
	return v
end
function M.predicted_move(mem, bank, target)
	local v = mem:read16(mem:read32(M.GNEWBS) + 0x1EE + (bank * 4 + target) * 2)
	if v == 0xFFFF then return 0 end
	return v
end

-- Predict one AI battler's move scores against one target.
-- Returns { role, moves = { [slot] = { name, score, alt (score with coin), notes, unknown } }, odds }
function M.predict(mem, ai_b, target_b, opts)
	local cached = 0
	local ai, foe = S.read_battle_mon(mem, ai_b), S.read_battle_mon(mem, target_b)
	local role = M.role(mem, ai)
	local mvs, dmg = {}, {}
	local strongest, best_dmg = nil, -1
	local has_protect = false
	for i = 0, 3 do
		if ai.moves[i] ~= 0 then
			mvs[i] = M.move(mem, ai.moves[i], ai)
			if mvs[i].effect == 0x6F then has_protect = true end
			dmg[i] = (opts and opts.cache and M.cached_damage(mem, ai_b, target_b, i)) or M.damage(mem, ai, foe, mvs[i], M.KO_ROLL)
			if opts and opts.cache and M.cached_damage(mem, ai_b, target_b, i) then cached = cached + 1 end
			if dmg[i] > best_dmg then best_dmg, strongest = dmg[i], i end
		end
	end
	-- Can the foe 2HKO the AI (its best move, approximation)?
	local foe_best, foe_phazes, foe_cached = 0, false, false
	for i = 0, 3 do
		if foe.moves[i] ~= 0 then
			local fm = M.move(mem, foe.moves[i], foe)
			if fm.effect == 0x1C or fm.effect == 0x19 or fm.effect == 0xDE then foe_phazes = true end
			local cd = opts and opts.cache and M.cached_damage(mem, target_b, ai_b, i)
			if cd then foe_cached = true end
			local d = cd or M.damage(mem, foe, ai, fm, M.KO_ROLL)
			if d > foe_best then foe_best = d end
		end
	end
	local foe_can_2hko = foe_best * 2 >= ai.hp
	-- End-of-turn damage the AI takes: RR's cache gNewBS +0x810 +battler*4 (0x090DADF8, all sources,
	-- RR's own immunity checks); fallback sandstorm 1/16 unless Rock/Ground/Steel (abilities ignored).
	local chip = 0
	local w = mem:read16(M.WEATHER)
	local cached_chip = opts and opts.cache and mem:read32(mem:read32(M.GNEWBS) + 0x810 + ai_b * 4)
	if cached_chip and cached_chip ~= 0xFFFFFFFF then
		chip = cached_chip
	elseif w & 0x18 ~= 0 then
		local immune = false
		for _, t in ipairs({ ai.type1, ai.type2, ai.type3 }) do if t == 5 or t == 4 or t == 8 then immune = true end end
		if not immune then chip = ai.max_hp // 16 end
	end
	local foe_can_ko = foe_best + chip >= ai.hp
	-- Goes first: priority, then Speed, against the AI's predicted move for you (MoveWouldHitFirst
	-- 0x090DA0D2 uses that prediction); Speed ties count as going second.
	local foe_pred = M.predicted_move(mem, target_b, ai_b)
	local foe_prio = foe_pred ~= 0 and M.move(mem, foe_pred).priority or 0
	local ai_first_base = M.speed(mem, ai) > M.speed(mem, foe)
	-- The KO bonuses go only to the most accurate KO move(s) (0x090E11FC).
	local best_ko_acc = -1
	for i, mv in pairs(mvs) do
		if mv.split ~= 2 and dmg[i] >= foe.hp then
			local acc = mv.accuracy == 0 and 101 or mv.accuracy
			if acc > best_ko_acc then best_ko_acc = acc end
		end
	end
	local ai_can_ko = best_dmg >= foe.hp
	local boost_ctx = { foe_phazes = foe_phazes, foe_can_2hko = foe_can_2hko, foe_can_ko = foe_can_ko, ai_first = ai_first_base }
	-- RR's strongest-move cache is what the AI uses (it can lag one Pokemon behind after a faint
	-- replacement, seen in game); fall back to the model's own pick when it is empty.
	if opts and opts.cache then
		local cs = M.cached_strongest(mem, ai_b, target_b)
		if cs then for i, mv in pairs(mvs) do if mv.id == cs then strongest = i end end end
	end
	local hp_pct = ai.max_hp > 0 and (ai.hp * 100 // ai.max_hp) or 0

	local out = { role = role, moves = {} }
	-- Starting scores: RR's AI setup (0x090C7880, run just before the move choice) sets 0 for moves
	-- it cannot use (Choice lock, Disable, no PP, ...); the scripts then leave them at 0.
	local start = {}
	if opts and opts.cache then
		local aist = mem:read32(mem:read32(0x02023FF4) + 0x14)
		for i = 0, 3 do start[i] = mem:read8(aist + 4 + i) end
	end
	local first_turn = mem:read8(0x02023E0C + ai_b * 0x1C + 0x16) ~= 0 -- gDisableStructs isFirstTurn
	for i, mv in pairs(mvs) do
		local r = { name = mv.name, score = 100, notes = {}, unknown = false }
		if start[i] == 0 then
			r.score = 0
			r.notes[#r.notes + 1] = "cannot be used (starting score 0)"
			out.moves[i] = r
			goto continue
		end
		local function add(n, why) r.score = r.score + n; r.notes[#r.notes + 1] = string.format("%+d %s", n, why) end
		local eff = M.effectiveness(mem, mv.type, foe)
		-- Ground move into an airborne target (Flying type, Levitate 26, Air Balloon item 703): RR scores 0
		-- (seen in game twice, Bulldoze vs Gyarados), unlike other immunities (-15). Code spot not yet found.
		local airborne = foe.type1 == 2 or foe.type2 == 2 or foe.type3 == 2 or foe.ability == 26 or foe.item == 703
		if mv.split ~= 2 and mv.type == 4 and airborne then
			r.score = 0
			r.notes[#r.notes + 1] = "Ground move into an airborne target: 0"
		elseif mv.split ~= 2 then
			if eff == 0 then
				add(-15, "no effect")
			else
				-- RR's MoveWouldHitFirst 0x090DA062: higher priority than your predicted move wins; otherwise
				-- (equal OR LOWER, asm 0x090DA0A6 `ble`) it falls through to bracket and Speed, so your
				-- priority advantage is ignored. With no prediction only positive priority counts.
				local goes_first = (foe_pred ~= 0 and mv.priority > foe_prio) or (foe_pred == 0 and mv.priority > 0) or ai_first_base
				local acc = mv.accuracy == 0 and 101 or mv.accuracy
				local ko = dmg[i] >= foe.hp and acc == best_ko_acc
				if mv.effect == 0x9E then
					-- Fake Out: -10 after the first turn out (Negatives); +8 in singles on the first turn when
					-- it works (ShouldUseFakeOut 0x090C562C, bonus 0x090C67A4). Choice-item case not modelled.
					if not first_turn then add(-10, "Fake Out after the first turn")
					elseif mv.id == 0xFC then add(8, "Fake Out on the first turn") end
				end
				if ko and goes_first then add(9, "KO, goes first")
				elseif ko and not has_protect then add(SLOW_KO[role] or 0, "KO, goes second (role)")
				elseif i == strongest then add(2, "strongest move") end
				if BOOST[mv.effect] then
					local b = stat_boost(role, mv.effect, ai, boost_ctx)
					if b then add(b, "stat-boosting attack, bonus by role") else r.notes[#r.notes + 1] = "boost not a good idea" end
				end
				if mv.effect == 0x46 and mv.chance >= 50 and not ai_first_base and not ai_can_ko then
					r.alt = r.score + 3
					r.notes[#r.notes + 1] = "+3 on a 50% coin (Speed drop)"
				end
			end
		else
			local e = mv.effect
			if e == 0x20 or e == 0x84 then
				if hp_pct >= 100 then add(-10, "healing at full HP")
				elseif hp_pct >= 90 then add(-9, "healing at 90-99% HP")
				else r.unknown = true; r.notes[#r.notes + 1] = "healing below 90% (bonus not modelled)" end
			elseif e == 0x21 or e == 0x42 then -- Toxic / poison
				-- Negatives 0x090CB186-0x090CB1C2: -10 if it would have no effect or you cannot be poisoned
				-- (CanBePoisoned 0x09076380: Immunity 0x11, Poison or Steel type unless the AI has Corrosion
				-- 0x9E, already statused).
				local can = foe.status1 == 0 and foe.ability ~= 0x11
				if ai.ability ~= 0x9E then
					for _, t in ipairs({ foe.type1, foe.type2, foe.type3 }) do if t == 3 or t == 8 then can = false end end
				end
				if not can then add(-10, "you cannot be poisoned")
				else add(status_bonus(role, 1, foe_can_2hko), "poison, status bonus by role (boost 1)") end
			elseif e == 0xA0 or BOOST[e] then
				local b = stat_boost(role, mv.effect, ai, boost_ctx)
				if b then add(b, "stat boost, bonus by role (max stacks not modelled)")
				else r.notes[#r.notes + 1] = "boost not a good idea" end
			else
				r.unknown = true
				r.notes[#r.notes + 1] = "status move not modelled"
			end
		end
		out.moves[i] = r
		::continue::
	end

	-- Odds of each move being chosen: enumerate the coins, top score wins, ties split evenly.
	local coins = {}
	for i, r in pairs(out.moves) do if r.alt then coins[#coins + 1] = i end end
	local odds = {}
	for mask = 0, (1 << #coins) - 1 do
		local p = 1 / (1 << #coins)
		local sc = {}
		for i, r in pairs(out.moves) do sc[i] = r.score end
		for k, i in ipairs(coins) do if mask & (1 << (k - 1)) ~= 0 then sc[i] = out.moves[i].alt end end
		local top = -999
		for _, v in pairs(sc) do if v > top then top = v end end
		local n = 0
		for _, v in pairs(sc) do if v == top then n = n + 1 end end
		for i, v in pairs(sc) do if v == top then odds[i] = (odds[i] or 0) + p / n end end
	end
	out.odds = odds
	out.foe_can_2hko, out.ai_first, out.ai_can_ko = foe_can_2hko, ai_first_base, ai_can_ko
	out.cached = cached
	out.dbg = string.format("spd ai %d you %d weather 0x%X yourbest %d%s chip %d", M.speed(mem, ai), M.speed(mem, foe), mem:read16(M.WEATHER), foe_best, foe_cached and "c" or "f", chip)
	out.strongest_model = strongest and mvs[strongest].id or 0
	out.strongest_cache = M.cached_strongest(mem, ai_b, target_b) or 0
	out.foe_pred, out.foe_prio = foe_pred, foe_prio
	return out
end

-- ===== Switch-in prediction (faint replacements), RR's scorer 0x090D7168 =====
-- Species base stats 0x097B98EC, 28 bytes: +0 HP Atk Def Spe SpA SpD, +6 type1, +7 type2,
-- +0x16 ability 1, +0x17 ability 2, +0x1A hidden ability (layout checked on Tepig, Poochyena, Cacturne).
-- Party ability: hidden if the IV word's top bit is set, else ability 2 when the personality is odd
-- and it exists, else ability 1 (CFRU's rule; not checked in RR code).
M.BASE_STATS, M.BASE_SIZE = 0x097B98EC, 28
M.SWITCH_ROLL = 96 -- percent; damage roll assumed for switch-ins (docs/ai-guide.md, not verified)

function M.party_battle_mon(mem, pm)
	local b = M.BASE_STATS + pm.species * M.BASE_SIZE
	local a1, a2, ah = mem:read8(b + 0x16), mem:read8(b + 0x17), mem:read8(b + 0x1A)
	local ability = a1
	if pm.hidden_ability == 1 and ah ~= 0 then ability = ah
	elseif pm.personality & 1 == 1 and a2 ~= 0 then ability = a2 end
	local st = {}
	for _, k in ipairs(S.STAGE_NAMES) do st[k] = 6 end
	return { species = pm.species, level = pm.level, hp = pm.hp, max_hp = pm.max_hp,
		attack = pm.attack, defense = pm.defense, speed = pm.speed, sp_attack = pm.sp_attack, sp_defense = pm.sp_defense,
		type1 = mem:read8(b + 6), type2 = mem:read8(b + 7), type3 = 0x14, ability = ability, status1 = pm.status1, item = pm.item,
		moves = pm.moves, ivs = pm.ivs, stages = st, battler = 1 }
end

-- Scores one candidate against the foe battle mon. Mirrors the RR scorer's rules
-- (docs/verified.md "switch-in" notes and the decompile lines cited there), with the model's damage.
-- RR's bench damage cache (0x090DA8A4): u32 at gNewBS + 0x3F0 + (((side*6 + slot)*4 + foe)*4 + move)*4.
-- It is only reset to -1 (not computed) by ClearCachedAIData 0x090C8BA4, which outside Hardcore's re-pick
-- never runs, so it stays 0 and RR treats bench Pokemon as dealing no damage (seen in game: every
-- lookup read 0). The model uses the cached value when it is not -1.
local function bench_damage(mem, side, slot, foe_b, k)
	local v = mem:read32(mem:read32(M.GNEWBS) + 0x3F0 + (((side * 6 + slot) * 4 + foe_b) * 4 + k) * 4)
	if v == 0xFFFFFFFF then return nil end
	return v
end

local function score_candidate(mem, cand, foe, side, slot, foe_b)
	local score, flags = 0, 0
	cand.battler = side
	local cspd, fspd = M.speed(mem, cand), M.speed(mem, foe)
	if cspd >= fspd then score = score + 14; flags = flags | 0x40 end
	local ko, two, usable, prio_ko = false, false, false, false
	for i = 0, 3 do
		local id = cand.moves[i]
		if id ~= 0 then
			local mv = M.move(mem, id, cand)
			if mv.split ~= 2 and mv.power > 0 then
				usable = true
				local d = bench_damage(mem, side, slot, foe_b, i) or M.damage(mem, cand, foe, mv, M.SWITCH_ROLL)
				if d >= foe.hp then ko = true; if mv.priority > 0 then prio_ko = true end end
				if d * 2 >= foe.hp then two = true end
			end
		end
	end
	if ko then
		score = score + 31; flags = flags | 1
		if prio_ko then
			score = score + 8; flags = flags | 4
			if flags & 0x40 == 0 then score = score + 14; flags = flags | 0x40 end
		end
	elseif not usable then
		return -1, flags
	elseif two then
		score = score + 2; flags = flags | 0x10
	end
	local faints, weak, normal, phys, spec = false, false, 0, false, false
	for i = 0, 3 do
		local id = foe.moves[i]
		if id ~= 0 then
			local mv = M.move(mem, id, foe)
			if mv.split ~= 2 and mv.power > 0 then
				if mv.split == 0 then phys = true else spec = true end
				local d = M.damage(mem, foe, cand, mv, M.SWITCH_ROLL)
				if d >= cand.hp then faints = true
				elseif d * 2 >= cand.hp then weak = true
				elseif d * 3 >= cand.hp then normal = normal + 1 end
			end
		end
	end
	if faints then
		if flags & 0x40 == 0 then
			flags = flags | 0x80
			score = score >= 39 and score - 39 or 0
		elseif flags & 1 == 0 then
			score = score >= 15 and score - 15 or 0
		else
			score = score >= 1 and score - 1 or 0
		end
	elseif weak then
		score = score >= 1 and score - 1 or 0
	elseif normal == 0 then
		score = score + 17; flags = flags | 2
	else
		local fa = staged(foe.attack, foe.stages.atk - 6)
		local fs = staged(foe.sp_attack, foe.stages.spa - 6)
		if not ((phys and cand.defense <= fa) or (spec and cand.sp_defense <= fs)) then
			score = score + 2; flags = flags | 8
		end
	end
	return score, flags
end

-- Predict which party slot replaces battler ai_b against foe battler foe_b.
-- Returns { slots = { [slot] = { name, score, flags } }, odds = { [slot] = p } }.
function M.predict_switchin(mem, ai_b, foe_b)
	local side = ai_b & 1
	local party = S.read_party(mem, side == 1 and "enemy" or "player")
	local foe = S.read_battle_mon(mem, foe_b)
	local on_field = mem:read16(S.BATTLER_PARTY_INDEXES + ai_b * 2)
	local out = { slots = {}, odds = {} }
	local order = {}
	for slot = 0, 5 do
		local pm = party[slot]
		if pm and pm.hp > 0 and pm.is_egg == 0 and slot ~= on_field and (pm.status1 & 7 == 0 or pm.status1 == 1) then
			local cand = M.party_battle_mon(mem, pm)
			local sc, fl = score_candidate(mem, cand, foe, side, slot, foe_b)
			local maxd, per = 0, {}
			for i = 0, 3 do
				local id = cand.moves[i]
				if id ~= 0 then
					local mv = M.move(mem, id, cand)
					local d = M.damage(mem, cand, foe, mv, M.SWITCH_ROLL)
					per[#per + 1] = tostring(d)
					if d > maxd then maxd = d end
				end
			end
			out.slots[slot] = { name = S.species_name(mem, pm.species), score = sc, flags = fl, maxd = maxd, foe_hp = foe.hp,
				permoves = table.concat(per, "/") }
			order[#order + 1] = slot
		end
	end
	-- Walk in party order: a higher score takes over; an equal score takes over on a 50% flip when
	-- neither "faints" or both do; one that does not faint beats one that does on a tie.
	local dist = {}
	for _, slot in ipairs(order) do
		local r = out.slots[slot]
		if r.score >= 0 then
			if next(dist) == nil then dist[slot] = 1
			else
				local nd = {}
				for b, p in pairs(dist) do
					local rb = out.slots[b]
					if r.score > rb.score then nd[slot] = (nd[slot] or 0) + p
					elseif r.score < rb.score then nd[b] = (nd[b] or 0) + p
					else
						local fb, fr = rb.flags & 0x80 ~= 0, r.flags & 0x80 ~= 0
						if fb and not fr then nd[slot] = (nd[slot] or 0) + p
						elseif fr and not fb then nd[b] = (nd[b] or 0) + p
						else nd[slot] = (nd[slot] or 0) + p / 2; nd[b] = (nd[b] or 0) + p / 2 end
					end
				end
				dist = nd
			end
		end
	end
	out.odds = dist
	return out
end

function M.format(p)
	local lines = { string.format("  PREDICT  role: %s%s", M.ROLE_NAMES[p.role] or p.role,
		"   switch: 25% stays without checking; other switch checks not modelled") }
	for i = 0, 3 do
		local r = p.moves[i]
		if r then
			local sc = r.alt and string.format("%d/%d", r.score, r.alt) or tostring(r.score)
			lines[#lines + 1] = string.format("    %-13s %7s%s  %3d%%  %s", r.name, sc, r.unknown and "?" or " ",
				math.floor((p.odds[i] or 0) * 100 + 0.5), table.concat(r.notes, ", "))
		end
	end
	return lines
end

return M
