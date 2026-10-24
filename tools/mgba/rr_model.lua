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
-- Approximations (v1), each a likely source of mismatches to chase:
--   damage: generic Gen 5+ formula with stats, stages, STAB, type and the 93% roll; no items,
--     abilities, weather, crits, multi-hit counts or RR's own damage code.
--   speed: stats with stages and paralysis only; ties count as "goes second".
--   role: no Choice item / ability / Assault Vest check.
--   status moves other than healing, poison and Stockpile, and stat boosts, are not scored ("?").
--   the AI's prediction of your move, and every switch check except the 25% roll, are not modelled.

local S = require("rr_state")
local M = {}

M.MOVES, M.MOVE_SIZE = 0x091521D0, 12
M.TYPE_CHART = 0x09146CE2
M.KO_ROLL = 93 -- percent; the AI's assumed damage roll for KO checks (from docs/ai-guide.md, not yet verified)

local function s8(v) return v >= 128 and v - 256 or v end

function M.move(mem, id)
	local a = M.MOVES + id * M.MOVE_SIZE
	return {
		id = id, effect = mem:read8(a), power = mem:read8(a + 1), type = mem:read8(a + 2),
		accuracy = mem:read8(a + 3), chance = mem:read8(a + 5), priority = s8(mem:read8(a + 7)),
		split = mem:read8(a + 10), name = S.move_name(mem, id),
	}
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

function M.speed(mon)
	local v = staged(mon.speed, mon.stages.spe - 6)
	if mon.status1 & 0x40 ~= 0 then v = v // 2 end -- paralysis
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

-- Predict one AI battler's move scores against one target.
-- Returns { role, moves = { [slot] = { name, score, alt (score with coin), notes, unknown } }, odds }
function M.predict(mem, ai_b, target_b)
	local ai, foe = S.read_battle_mon(mem, ai_b), S.read_battle_mon(mem, target_b)
	local role = M.role(mem, ai)
	local mvs, dmg = {}, {}
	local strongest, best_dmg = nil, -1
	local has_protect = false
	for i = 0, 3 do
		if ai.moves[i] ~= 0 then
			mvs[i] = M.move(mem, ai.moves[i])
			if mvs[i].effect == 0x6F then has_protect = true end
			dmg[i] = M.damage(mem, ai, foe, mvs[i], M.KO_ROLL)
			if dmg[i] > best_dmg then best_dmg, strongest = dmg[i], i end
		end
	end
	-- Can the foe 2HKO the AI (its best move, approximation)?
	local foe_best = 0
	for i = 0, 3 do
		if foe.moves[i] ~= 0 then
			local d = M.damage(mem, foe, ai, M.move(mem, foe.moves[i]), M.KO_ROLL)
			if d > foe_best then foe_best = d end
		end
	end
	local foe_can_2hko = foe_best * 2 >= ai.hp
	local ai_first_base = M.speed(ai) > M.speed(foe)
	local ai_can_ko = best_dmg >= foe.hp
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
				local goes_first = mv.priority > 0 or (mv.priority == 0 and ai_first_base)
				if dmg[i] >= foe.hp and goes_first then add(9, "KO, goes first")
				elseif dmg[i] >= foe.hp and not has_protect then add(SLOW_KO[role] or 0, "KO, goes second (role)")
				elseif i == strongest then add(2, "strongest move") end
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
			elseif e == 0xA0 then
				add(status_bonus(role, 1, foe_can_2hko), "Stockpile, status bonus by role (boost 1; full stacks not modelled)")
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
