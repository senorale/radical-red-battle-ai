-- Radical Red 4.1 AI move-score viewer for mGBA 0.11+ (development builds; needs emu:setBreakpoint).
-- Load: Tools > Scripting > File > Load script, with the Radical Red 4.1 ROM running.
--
-- Shows, for every move decision the enemy AI makes, the final score of each of its moves
-- against each target it considered, and what it picked. Scores start at 100; the highest wins,
-- ties are broken at random.
--
-- How it works (all addresses from Radical Red 4.1's code, not from CFRU source):
--   0x090C82C0  move-choice function (CFRU BattleAI_ChooseMoveOrAction, singles and doubles inlined).
--               It is the only caller of BattleAI_DoAIProcessing (0x090C6F3C, call sites 0x090C838C
--               and 0x090C871E). Move predictions call the AI scripts directly into local arrays,
--               so the AI struct's scores below only ever come from real decisions.
--   0x090C83AC  singles: scores final, about to pick the best (reads score[0]).
--   0x090C875C  doubles: scores for the current target final (reads score[0]); runs once per target.
--   0x090C837A  the function's only exit; r0 = chosen move slot (0-3), 4 = flee, 5 = watch.
--   0x02023FF4  gBattleResources; [+0x14] = AI struct: +0 aiState, +1 movesetIndex,
--               +2 moveConsidered, +4 score[4] (s8), +0xC aiFlags, +0x10 aiAction, +0x11 aiLogicId.
--   0x02023D6B  battler being scored (the AI's Pokemon); 0x02023D6C target.
--   0x02023BE4  gBattleMons, 0x58 bytes per battler: +0 species (u16), +0xC moves (4 x u16).
--   0x090F3188  move names, 13 bytes each; 0x094042CC species names, 11 bytes each.
--
-- Switching (trainer battles):
--   0x090C80DE  in AI_TrySwitchOrUseItem 0x090C802C after ShouldSwitch 0x090D824C said yes:
--               r3 = AI_monToSwitchIntoId[side] (gBattleStruct +0x92 +side); 6 = none picked yet,
--               so GetMostSuitableMonToSwitchInto's core 0x090D8168 picks.
--   0x090C8246  voluntary switch committed: strb r2 -> gBattleStruct +0x5C +battler (r2 = party slot).
--   0x09068B20  post-KO replacement in OpponentHandleChoosePokemon 0x09068A28: strb r4, r4 = party slot.
--   0x02023FE8  gBattleStruct pointer; 0x02023BC4 gActiveBattler; 0x0203E038 gNewBS pointer.
--   gNewBS +0x860 +side*0xC: s16 score per party slot, +0x878 +side*6: flag byte per slot. RR copies
--   both there at the end of the switch-in scorer 0x090D7168 (memcpy at 0x090D7C48 and 0x090D7C6A;
--   CFRU keeps them local). They come from the scorer's latest run for that side. Flag bits are
--   CFRU's SWITCHING_FLAG_* (include/new/ai_switching.h), not yet checked bit by bit in RR.

local GBATTLE_RESOURCES = 0x02023FF4
local AI_BATTLER = 0x02023D6B
local AI_TARGET = 0x02023D6C
local BATTLE_MONS, MON_SIZE = 0x02023BE4, 0x58
local MOVE_NAMES, MOVE_NAME_LEN = 0x090F3188, 13
local SPECIES_NAMES, SPECIES_NAME_LEN = 0x094042CC, 11

local SITE_SINGLES = 0x090C83AC
local SITE_DOUBLES = 0x090C875C
local SITE_EXIT = 0x090C837A

local POSITION = { [0] = "your left", [1] = "foe left", [2] = "your right", [3] = "foe right" }

local CHARS = { [0x00] = " ", [0xAB] = "!", [0xAC] = "?", [0xAD] = ".", [0xAE] = "-", [0xB4] = "'",
	[0xB5] = "M", [0xB6] = "F", [0xB8] = ",", [0xBA] = "/", [0x1B] = "e" }
for i = 0, 9 do CHARS[0xA1 + i] = string.char(48 + i) end
for i = 0, 25 do CHARS[0xBB + i] = string.char(65 + i); CHARS[0xD5 + i] = string.char(97 + i) end

local function name_at(addr, len)
	local out = {}
	for i = 0, len - 1 do
		local c = emu:read8(addr + i)
		if c == 0xFF then break end
		out[#out + 1] = CHARS[c] or "?"
	end
	return table.concat(out)
end

local function move_name(id) return id == 0 and "-" or name_at(MOVE_NAMES + id * MOVE_NAME_LEN, MOVE_NAME_LEN) end
local function species_name(battler)
	return name_at(SPECIES_NAMES + emu:read16(BATTLE_MONS + battler * MON_SIZE) * SPECIES_NAME_LEN, SPECIES_NAME_LEN)
end
local function signed8(v) return v >= 128 and v - 256 or v end

local buffer = console:createBuffer("RR AI scores")
local pending = {}   -- per AI battler: list of {target, moves, scores}
local history = {}   -- printed decisions, newest last
local MAX_HISTORY = 6

local function snapshot()
	local ai = emu:read32(emu:read32(GBATTLE_RESOURCES) + 0x14)
	local battler, target = emu:read8(AI_BATTLER), emu:read8(AI_TARGET)
	local s = { target = target, moves = {}, scores = {} }
	for i = 0, 3 do
		s.moves[i] = emu:read16(BATTLE_MONS + battler * MON_SIZE + 0x0C + i * 2)
		s.scores[i] = signed8(emu:read8(ai + 4 + i))
	end
	pending[battler] = pending[battler] or {}
	table.insert(pending[battler], s)
end

local function redraw()
	buffer:clear()
	for _, block in ipairs(history) do buffer:print(block .. "\n") end
end

local function on_exit()
	local battler = emu:read8(AI_BATTLER)
	local runs = pending[battler]
	pending[battler] = nil
	if not runs then return end
	local choice = emu:readRegister("r0") & 0xFF
	local final_target = emu:read8(AI_TARGET)
	local lines = { string.format("frame %d  %s (%s)", emu:currentFrame(), species_name(battler), POSITION[battler] or battler) }
	for _, s in ipairs(runs) do
		local best = -999
		for i = 0, 3 do if s.moves[i] ~= 0 and s.scores[i] > best then best = s.scores[i] end end
		local ties = 0
		for i = 0, 3 do if s.moves[i] ~= 0 and s.scores[i] == best then ties = ties + 1 end end
		lines[#lines + 1] = string.format("  vs %s (%s)%s", species_name(s.target), POSITION[s.target] or s.target,
			ties > 1 and string.format("  [%d-way tie, random]", ties) or "")
		for i = 0, 3 do
			if s.moves[i] ~= 0 then
				local mark = ""
				if s.scores[i] == best then mark = "  best" end
				if i == choice and s.target == final_target then mark = mark .. "  <= CHOSEN" end
				lines[#lines + 1] = string.format("    %-13s %4d%s", move_name(s.moves[i]), s.scores[i], mark)
			end
		end
	end
	if choice == 4 then lines[#lines + 1] = "  => flee" elseif choice == 5 then lines[#lines + 1] = "  => watch" end
	table.insert(history, table.concat(lines, "\n"))
	while #history > MAX_HISTORY do table.remove(history, 1) end
	redraw()
end

local ACTIVE_BATTLER = 0x02023BC4
local GBATTLE_STRUCT = 0x02023FE8
local GNEWBS = 0x0203E038
local ENEMY_PARTY, PLAYER_PARTY = 0x0202402C, 0x02024284
local SITE_PRESET = 0x090C80DE
local SITE_SWITCH = 0x090C8246
local SITE_KO_SWITCH = 0x09068B20
local FLAG_NAMES = { [0x01] = "KO foe", [0x02] = "resists all", [0x04] = "revenge kill", [0x08] = "walls",
	[0x10] = "2HKO", [0x20] = "removes hazards", [0x40] = "outspeeds", [0x80] = "faints to foe" }

local preset = {} -- per battler: AI_monToSwitchIntoId[side] seen before the pick (6 = none)

local function signed16(v) return v >= 0x8000 and v - 0x10000 or v end

local function flags_text(f)
	local t = {}
	for _, bit in ipairs({ 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80 }) do
		if f & bit ~= 0 then t[#t + 1] = FLAG_NAMES[bit] end
	end
	return table.concat(t, ", ")
end

local function party_species(side, slot)
	local base = side == 1 and ENEMY_PARTY or PLAYER_PARTY
	local id = emu:read16(base + slot * 100 + 0x20)
	return id, name_at(SPECIES_NAMES + id * SPECIES_NAME_LEN, SPECIES_NAME_LEN)
end

local function report_switch(battler, slot, kind)
	local side = battler & 1
	local nbs = emu:read32(GNEWBS)
	local base = side == 1 and ENEMY_PARTY or PLAYER_PARTY
	local _, to_name = party_species(side, slot)
	local lines = { string.format("frame %d  %s (%s) %s -> slot %d %s", emu:currentFrame(), species_name(battler),
		POSITION[battler] or battler, kind, slot, to_name) }
	if kind == "SWITCHES" then
		local p = preset[battler]
		lines[#lines + 1] = (p ~= nil and p ~= 6) and string.format("  target slot was set inside ShouldSwitch (%d)", p)
			or "  target slot picked by best-switch-in scorer"
	end
	lines[#lines + 1] = "  switch-in scores (latest scorer run for this side):"
	for i = 0, 5 do
		local id, name = party_species(side, i)
		if id ~= 0 then
			local hp = emu:read16(base + i * 100 + 0x56)
			local score = signed16(emu:read16(nbs + 0x860 + side * 0xC + i * 2))
			local f = emu:read8(nbs + 0x878 + side * 6 + i)
			local mark = (i == slot) and "  <= CHOSEN" or ""
			if emu:read16(0x02023BCE + battler * 2) == i then mark = "  (on field)" end
			lines[#lines + 1] = string.format("    %d %-11s hp %3d  score %4d  flags 0x%02X %s%s", i, name, hp, score, f,
				flags_text(f), mark)
		end
	end
	preset[battler] = nil
	table.insert(history, table.concat(lines, "\n"))
	while #history > MAX_HISTORY do table.remove(history, 1) end
	redraw()
end

local function on_preset() preset[emu:read8(ACTIVE_BATTLER)] = emu:readRegister("r3") & 0xFF end
local function on_switch() report_switch(emu:read8(ACTIVE_BATTLER), emu:readRegister("r2") & 0xFF, "SWITCHES") end
local function on_ko_switch() report_switch(emu:read8(ACTIVE_BATTLER), emu:readRegister("r4") & 0xFF, "replacement after faint") end

-- Diagnostics: every hook hit and error goes to the mGBA log and to logs/viewer.log next to
-- this script (git-ignored), so a session without output can be debugged afterwards.
local LOG_PATH
do
	local src = debug.getinfo(1, "S").source
	local dir = src:sub(1, 1) == "@" and src:sub(2):match("(.*/)") or nil
	if dir then LOG_PATH = dir .. "logs/viewer.log" end
end
local function log(msg)
	local line = string.format("[rr-ai] %s", msg)
	pcall(function() console:log(line) end)
	if LOG_PATH then
		pcall(function()
			local f = io.open(LOG_PATH, "a")
			if f then f:write(os.date("%H:%M:%S "), line, "\n"); f:close() end
		end)
	end
end

local function guard(name, fn)
	return function()
		local frame = -1
		pcall(function() frame = emu:currentFrame() end)
		log(string.format("hit %s frame %d", name, frame))
		local ok, err = pcall(fn)
		if not ok then
			log(string.format("ERROR in %s: %s", name, tostring(err)))
			buffer:print(string.format("ERROR in %s: %s\n", name, tostring(err)))
		end
	end
end

local SITES = {
	{ "singles", snapshot, SITE_SINGLES }, { "doubles", snapshot, SITE_DOUBLES }, { "exit", on_exit, SITE_EXIT },
	{ "preset", on_preset, SITE_PRESET }, { "switch", on_switch, SITE_SWITCH }, { "ko_switch", on_ko_switch, SITE_KO_SWITCH },
}
local breakpoint_ids = {}

-- Runs at load and again on every start/reset, since a restarted core may drop breakpoints.
local function install(why)
	if not emu then log("install(" .. tostring(why) .. "): no emu yet"); return end
	for _, id in ipairs(breakpoint_ids) do pcall(function() emu:clearBreakpoint(id) end) end
	breakpoint_ids = {}
	local parts = {}
	for _, site in ipairs(SITES) do
		local id = emu:setBreakpoint(guard(site[1], site[2]), site[3])
		breakpoint_ids[#breakpoint_ids + 1] = id
		parts[#parts + 1] = string.format("%s@%08X=%s", site[1], site[3], tostring(id))
	end
	pending, preset = {}, {}
	log("install(" .. tostring(why) .. "): " .. table.concat(parts, " "))
	buffer:clear()
	buffer:print("RR AI viewer ready. Scores appear when the enemy picks a move.\n")
end

callbacks:add("start", function() install("start") end)
callbacks:add("reset", function() install("reset") end)
install("load")
