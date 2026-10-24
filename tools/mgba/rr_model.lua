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
-- Measured on the rr.ss6 battle (16 enemy move decisions): every move score matched.

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
		split = mem:read8(a + 10), name = S.move_name(mem, id),
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

-- Damage estimate (approximation, see header). roll in percent.
function M.damage(mem, atk, def, mv, roll)
	if mv.split == 2 or mv.power == 0 then return 0 end
	local a, d
	if mv.split == 0 then
		a, d = staged(atk.attack, atk.stages.atk - 6), staged(def.defense, def.stages.def - 6)
	else
		a, d = staged(atk.sp_attack, atk.stages.spa - 6), staged(def.sp_defense, def.stages.spd - 6)
	end
	if d < 1 then d = 1 end
	local base = ((2 * atk.level) // 5 + 2) * mv.power * a // d // 50 + 2
	if mv.type == atk.type1 or mv.type == atk.type2 or mv.type == atk.type3 then base = base * 3 // 2 end
	base = math.floor(base * M.effectiveness(mem, mv.type, def))
	if mv.effect == 0x1D then base = base * 3 end -- multi-hit (2-5 hits): 3 assumed, not checked in RR code
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

-- Stat-boost bonus by role (0x090C5D0C, table 0x090C5E0E), "good idea to boost" (0x090C3C64)
-- approximated as: you have no Roar/Whirlwind/Haze-type move (the 50% main-Random skip and the
-- other conditions are not modelled). Returns nil when no bonus.
local STAT_BOOST = { [1] = 5, [2] = 5, [3] = 5, [5] = 4, [7] = 4, [8] = 3, [9] = 5, [10] = 3 }
local function stat_boost(role, foe_phazes, foe_can_2hko, ai_ko_first)
	if foe_phazes or foe_can_2hko or ai_ko_first then return nil end
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
	local foe_best, foe_phazes = 0, false
	for i = 0, 3 do
		if foe.moves[i] ~= 0 then
			local fm = M.move(mem, foe.moves[i], foe)
			if fm.effect == 0x1C or fm.effect == 0x19 or fm.effect == 0xDE then foe_phazes = true end
			local d = (opts and opts.cache and M.cached_damage(mem, target_b, ai_b, i)) or M.damage(mem, foe, ai, fm, M.KO_ROLL)
			if d > foe_best then foe_best = d end
		end
	end
	local foe_can_2hko = foe_best * 2 >= ai.hp
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
	-- RR's strongest-move cache is what the AI uses (it can lag one Pokemon behind after a faint
	-- replacement, seen in game); fall back to the model's own pick when it is empty.
	if opts and opts.cache then
		local cs = M.cached_strongest(mem, ai_b, target_b)
		if cs then for i, mv in pairs(mvs) do if mv.id == cs then strongest = i end end end
	end
	local hp_pct = ai.max_hp > 0 and (ai.hp * 100 // ai.max_hp) or 0

	local out = { role = role, moves = {} }
	for i, mv in pairs(mvs) do
		local r = { name = mv.name, score = 100, notes = {}, unknown = false }
		local function add(n, why) r.score = r.score + n; r.notes[#r.notes + 1] = string.format("%+d %s", n, why) end
		local eff = M.effectiveness(mem, mv.type, foe)
		if mv.split ~= 2 then
			if eff == 0 then
				add(-15, "no effect")
			else
				local goes_first = mv.priority > foe_prio or (mv.priority == foe_prio and ai_first_base)
				local acc = mv.accuracy == 0 and 101 or mv.accuracy
				local ko = dmg[i] >= foe.hp and acc == best_ko_acc
				if ko and goes_first then add(9, "KO, goes first")
				elseif ko and not has_protect then add(SLOW_KO[role] or 0, "KO, goes second (role)")
				elseif i == strongest then add(2, "strongest move") end
				if BOOST[mv.effect] then
					local b = stat_boost(role, foe_phazes, foe_can_2hko, ai_can_ko and ai_first_base)
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
				if foe.status1 == 0 and eff ~= 0 then add(status_bonus(role, 1, foe_can_2hko), "poison, status bonus by role (boost 1)")
				else r.unknown = true end
			elseif e == 0xA0 or BOOST[e] then
				local b = stat_boost(role, foe_phazes, foe_can_2hko, ai_can_ko and ai_first_base)
				if b then add(b, "stat boost, bonus by role (max stacks not modelled)")
				else r.notes[#r.notes + 1] = "boost not a good idea" end
			else
				r.unknown = true
				r.notes[#r.notes + 1] = "status move not modelled"
			end
		end
		out.moves[i] = r
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
	out.strongest_model = strongest and mvs[strongest].id or 0
	out.strongest_cache = M.cached_strongest(mem, ai_b, target_b) or 0
	out.foe_pred, out.foe_prio = foe_pred, foe_prio
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
