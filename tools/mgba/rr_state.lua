-- Radical Red 4.1 battle-state reader, shared by the mGBA scripts. Every read goes through `mem`,
-- which must have read8/read16/read32 methods (mGBA's `emu`, or a fake in the offline tests).
--
-- Evidence for the layouts (RR 4.1 code unless noted):
--   gBattleMons 0x02023BE4, 0x58 bytes per battler. Layout = CFRU struct BattlePokemon
--     (vendor/cfru/include/pokemon.h): +0x18 is type3 (vanilla's HP stat stage), stat stages for
--     Atk, Def, Spe, SpA, SpD, Acc, Eva at +0x19..+0x1F. The decompile 0x0906CB64 reads +0x21,
--     +0x22 and +0x18 with the blank-type tests (9, 0x13, 0x14). Checked against a real battle
--     (rr.ss2: Tepig vs Poochyena): species, stats, moves, ability, types, HP, level, item, all
--     match, type3 = 20 (TYPE_BLANK) and every stage = 6.
--   gPlayerParty 0x02024284, gEnemyParty 0x0202402C, 6 x 100 bytes. RR stores Pokemon
--     unencrypted with a fixed substructure order: EncryptBoxMon 0x0803F8F8 has both eor
--     replaced by nops (0x0803F906, 0x0803F90C), GetSubstruct 0x0803F940 sets the order index
--     to 0 (mov r0,#0 at 0x0803F94C, then nops), and GetBoxMonData's decrypt/checksum block is
--     nopped (0x0803FD94-0x0803FDA6). Order 0 is G A E M (growth, attacks, EVs, misc), so the
--     substructures sit at +0x20, +0x2C, +0x38, +0x44. The stored checksum is 0.
--   gPlayerPartyCount 0x02024029 (rr.ss2 has 1 there with one Pokemon; symbols.txt's 0x02024028
--     holds 15). Not checked in code; the reader below stops at species 0 instead.
--   gBattleTypeFlags 0x02022B4C: bit 0 = doubles (0x090C82C0 tests it to pick the singles or
--     doubles path, decompile line 67).
--   gBattlersCount 0x02023BCC, gBattlerPartyIndexes 0x02023BCE (u16 x4), gSideStatuses
--     0x02023DDE (u16 x2), gStatuses3 0x02023DFC (u32 x4), gBattleWeather 0x02023F1C (u16):
--     vanilla FireRed addresses, all referenced by RR code. Bit meanings follow CFRU and are
--     not checked yet.

local M = {}

M.BATTLE_TYPE_FLAGS = 0x02022B4C
M.BATTLERS_COUNT = 0x02023BCC
M.BATTLER_PARTY_INDEXES = 0x02023BCE
M.BATTLE_MONS, M.BATTLE_MON_SIZE = 0x02023BE4, 0x58
M.SIDE_STATUSES = 0x02023DDE
M.STATUSES3 = 0x02023DFC
M.BATTLE_WEATHER = 0x02023F1C
M.PLAYER_PARTY, M.ENEMY_PARTY, M.PARTY_MON_SIZE = 0x02024284, 0x0202402C, 100
M.PLAYER_PARTY_COUNT = 0x02024029

M.MOVE_NAMES, M.MOVE_NAME_LEN = 0x090F3188, 13
M.SPECIES_NAMES, M.SPECIES_NAME_LEN = 0x094042CC, 11

M.STAGE_NAMES = { "atk", "def", "spe", "spa", "spd", "acc", "eva" }
M.TYPE_NAMES = { [0] = "Normal", "Fighting", "Flying", "Poison", "Ground", "Rock", "Bug", "Ghost",
	"Steel", "???", "Fire", "Water", "Grass", "Electric", "Psychic", "Ice", "Dragon", "Dark",
	[0x13] = "Roostless", [0x14] = "Blank", [0x17] = "Fairy" }

local CHARS = { [0x00] = " ", [0xAB] = "!", [0xAC] = "?", [0xAD] = ".", [0xAE] = "-", [0xB4] = "'",
	[0xB5] = "M", [0xB6] = "F", [0xB8] = ",", [0xBA] = "/", [0x1B] = "e" }
for i = 0, 9 do CHARS[0xA1 + i] = string.char(48 + i) end
for i = 0, 25 do CHARS[0xBB + i] = string.char(65 + i); CHARS[0xD5 + i] = string.char(97 + i) end

local function signed8(v) return v >= 128 and v - 256 or v end
M.signed8 = signed8

function M.text(mem, addr, len)
	local out = {}
	for i = 0, len - 1 do
		local c = mem:read8(addr + i)
		if c == 0xFF then break end
		out[#out + 1] = CHARS[c] or "?"
	end
	return (table.concat(out):gsub("%s+$", ""))
end

function M.move_name(mem, id)
	return id == 0 and "-" or M.text(mem, M.MOVE_NAMES + id * M.MOVE_NAME_LEN, M.MOVE_NAME_LEN)
end

function M.species_name(mem, id)
	return M.text(mem, M.SPECIES_NAMES + id * M.SPECIES_NAME_LEN, M.SPECIES_NAME_LEN)
end

function M.read_battle_mon(mem, battler)
	local a = M.BATTLE_MONS + battler * M.BATTLE_MON_SIZE
	local ivs = mem:read32(a + 0x14)
	local m = {
		battler = battler,
		species = mem:read16(a + 0x00),
		attack = mem:read16(a + 0x02), defense = mem:read16(a + 0x04), speed = mem:read16(a + 0x06),
		sp_attack = mem:read16(a + 0x08), sp_defense = mem:read16(a + 0x0A),
		moves = {}, pp = {}, stages = {},
		ivs = { ivs & 31, (ivs >> 5) & 31, (ivs >> 10) & 31, (ivs >> 15) & 31, (ivs >> 20) & 31, (ivs >> 25) & 31 },
		is_egg = (ivs >> 30) & 1, alt_ability = (ivs >> 31) & 1,
		type3 = mem:read8(a + 0x18),
		ability = mem:read8(a + 0x20),
		type1 = mem:read8(a + 0x21), type2 = mem:read8(a + 0x22),
		hp = mem:read16(a + 0x28), level = mem:read8(a + 0x2A), friendship = mem:read8(a + 0x2B),
		max_hp = mem:read16(a + 0x2C), item = mem:read16(a + 0x2E),
		nickname = M.text(mem, a + 0x30, 11),
		pp_bonuses = mem:read8(a + 0x3B),
		personality = mem:read32(a + 0x48),
		status1 = mem:read32(a + 0x4C), status2 = mem:read32(a + 0x50),
		ot_id = mem:read32(a + 0x54),
	}
	for i = 0, 3 do
		m.moves[i] = mem:read16(a + 0x0C + i * 2)
		m.pp[i] = mem:read8(a + 0x24 + i)
	end
	for i = 1, 7 do m.stages[M.STAGE_NAMES[i]] = signed8(mem:read8(a + 0x18 + i)) end
	return m
end

-- One party slot; nil when empty (species 0).
function M.read_party_mon(mem, a)
	local species = mem:read16(a + 0x20)
	if species == 0 then return nil end
	local ivs = mem:read32(a + 0x48)
	local m = {
		personality = mem:read32(a + 0x00), ot_id = mem:read32(a + 0x04),
		nickname = M.text(mem, a + 0x08, 10),
		species = species, item = mem:read16(a + 0x22), experience = mem:read32(a + 0x24),
		pp_bonuses = mem:read8(a + 0x28), friendship = mem:read8(a + 0x29), pokeball = mem:read8(a + 0x2A),
		moves = {}, pp = {}, evs = {},
		ivs = { ivs & 31, (ivs >> 5) & 31, (ivs >> 10) & 31, (ivs >> 15) & 31, (ivs >> 20) & 31, (ivs >> 25) & 31 },
		is_egg = (ivs >> 30) & 1, hidden_ability = (ivs >> 31) & 1,
		status1 = mem:read32(a + 0x50), level = mem:read8(a + 0x54),
		hp = mem:read16(a + 0x56), max_hp = mem:read16(a + 0x58),
		attack = mem:read16(a + 0x5A), defense = mem:read16(a + 0x5C), speed = mem:read16(a + 0x5E),
		sp_attack = mem:read16(a + 0x60), sp_defense = mem:read16(a + 0x62),
	}
	for i = 0, 3 do
		m.moves[i] = mem:read16(a + 0x2C + i * 2)
		m.pp[i] = mem:read8(a + 0x34 + i)
	end
	for i = 0, 5 do m.evs[i + 1] = mem:read8(a + 0x38 + i) end
	return m
end

-- side: "player" or "enemy". Returns slots 0-5 (missing entries are empty slots).
function M.read_party(mem, side)
	local base = side == "player" and M.PLAYER_PARTY or M.ENEMY_PARTY
	local party = {}
	for slot = 0, 5 do
		local m = M.read_party_mon(mem, base + slot * M.PARTY_MON_SIZE)
		if m then m.slot = slot; party[slot] = m end
	end
	return party
end

function M.read_battle(mem)
	local flags = mem:read32(M.BATTLE_TYPE_FLAGS)
	local s = {
		type_flags = flags, doubles = (flags & 1) == 1,
		battlers_count = mem:read8(M.BATTLERS_COUNT),
		weather = mem:read16(M.BATTLE_WEATHER),
		side_statuses = { [0] = mem:read16(M.SIDE_STATUSES), mem:read16(M.SIDE_STATUSES + 2) },
		party_index = {}, statuses3 = {}, mons = {},
		parties = { player = M.read_party(mem, "player"), enemy = M.read_party(mem, "enemy") },
	}
	for b = 0, s.battlers_count - 1 do
		s.party_index[b] = mem:read16(M.BATTLER_PARTY_INDEXES + b * 2)
		s.statuses3[b] = mem:read32(M.STATUSES3 + b * 4)
		s.mons[b] = M.read_battle_mon(mem, b)
	end
	return s
end

local function types_text(m)
	local t = { M.TYPE_NAMES[m.type1] or m.type1 }
	if m.type2 ~= m.type1 then t[#t + 1] = M.TYPE_NAMES[m.type2] or m.type2 end
	if m.type3 ~= 0x14 and m.type3 ~= 9 then t[#t + 1] = M.TYPE_NAMES[m.type3] or m.type3 end
	return table.concat(t, "/")
end

local function moves_text(mem, m)
	local t = {}
	for i = 0, 3 do if m.moves[i] ~= 0 then t[#t + 1] = string.format("%s(%d)", M.move_name(mem, m.moves[i]), m.pp[i]) end end
	return table.concat(t, ", ")
end

-- Compact lines for the Pokemon on the field: position, HP, types, stats, stages, status, moves.
-- speed_fn (optional) gives the effective Speed the AI uses.
function M.field_lines(mem, speed_fn)
	local POS = { [0] = "you L", [1] = "foe L", [2] = "you R", [3] = "foe R" }
	local lines = {}
	for b = 0, mem:read8(M.BATTLERS_COUNT) - 1 do
		local m = M.read_battle_mon(mem, b)
		if m.species ~= 0 then
			local st = {}
			for i = 1, 7 do
				local v = m.stages[M.STAGE_NAMES[i]] - 6
				if v ~= 0 then st[#st + 1] = string.format("%s%+d", M.STAGE_NAMES[i], v) end
			end
			lines[#lines + 1] = string.format("  field %s %-10s %3d/%3d HP [%s] Atk %d Def %d SpA %d SpD %d Spe %d%s%s%s | %s",
				POS[b] or b, M.species_name(mem, m.species), m.hp, m.max_hp, types_text(m),
				m.attack, m.defense, m.sp_attack, m.sp_defense, m.speed,
				speed_fn and string.format(" (eff %d)", speed_fn(m)) or "",
				#st > 0 and (" " .. table.concat(st, " ")) or "",
				m.status1 ~= 0 and string.format(" status 0x%X", m.status1) or "",
				moves_text(mem, m))
		end
	end
	return lines
end

-- Human-readable lines for one battle state.
function M.format(mem, s)
	local POS = { [0] = "your left", [1] = "foe left", [2] = "your right", [3] = "foe right" }
	local lines = { string.format("%s battle, flags 0x%X, weather 0x%X, side status you 0x%X foe 0x%X",
		s.doubles and "double" or "single", s.type_flags, s.weather, s.side_statuses[0], s.side_statuses[1]) }
	for b = 0, s.battlers_count - 1 do
		local m = s.mons[b]
		local st = {}
		for i = 1, 7 do
			local v = m.stages[M.STAGE_NAMES[i]] - 6
			if v ~= 0 then st[#st + 1] = string.format("%s%+d", M.STAGE_NAMES[i], v) end
		end
		lines[#lines + 1] = string.format("  %d %-10s %s Lv%d %d/%d HP  %s  ability %d item %d  %d/%d/%d/%d/%d%s%s",
			b, POS[b] or b, M.species_name(mem, m.species), m.level, m.hp, m.max_hp, types_text(m), m.ability, m.item,
			m.attack, m.defense, m.sp_attack, m.sp_defense, m.speed,
			#st > 0 and ("  " .. table.concat(st, " ")) or "",
			m.status1 ~= 0 and string.format("  status1 0x%X", m.status1) or "")
		lines[#lines + 1] = "      " .. moves_text(mem, m)
	end
	for _, side in ipairs({ "player", "enemy" }) do
		lines[#lines + 1] = "  " .. side .. " party:"
		for slot = 0, 5 do
			local m = s.parties[side][slot]
			if m then
				lines[#lines + 1] = string.format("    %d %s Lv%d %d/%d HP item %d  %d/%d/%d/%d/%d  %s", slot,
					M.species_name(mem, m.species), m.level, m.hp, m.max_hp, m.item,
					m.attack, m.defense, m.sp_attack, m.sp_defense, m.speed, moves_text(mem, m))
			end
		end
	end
	return lines
end

return M
