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
-- Not covered: the switch decision (ShouldSwitch) and post-KO replacement choice.

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

local installed = false
local function install()
	if installed or not emu then return end
	emu:setBreakpoint(snapshot, SITE_SINGLES)
	emu:setBreakpoint(snapshot, SITE_DOUBLES)
	emu:setBreakpoint(on_exit, SITE_EXIT)
	installed = true
	buffer:clear()
	buffer:print("RR AI viewer ready. Scores appear when the enemy picks a move.\n")
end

callbacks:add("start", install)
install()
