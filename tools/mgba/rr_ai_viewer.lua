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

-- Predictor (rr_model.lua, same folder): runs at the move-choice entry from the battle state alone
-- and is printed above the real scores. Singles only for now.
local SCRIPT_DIR = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
package.path = SCRIPT_DIR .. "?.lua;" .. package.path
local model_ok, Model = pcall(require, "rr_model")
local SITE_CHOICE_ENTRY = 0x090C82C0
local predictions = {} -- per AI battler
local LOG_DIR -- set in the diagnostics section below; decisions.jsonl goes here
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

local function on_choice_entry()
	if not model_ok or (emu:read32(0x02022B4C) & 1) ~= 0 then return end -- singles only
	local b = emu:read8(0x02023BC4)
	local ok, p = pcall(Model.predict, emu, b, b ~ 1, { cache = true })
	predictions[b] = ok and p or { error = tostring(p) }
end

local function json_escape(v) return (tostring(v):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end)) end
local function log_decision(battler, runs, choice, pred)
	if not LOG_DIR then return end
	local parts = { string.format('"frame":%d,"ai":"%s","battler":%d,"choice":%d', emu:currentFrame(),
		json_escape(species_name(battler)), battler, choice) }
	local s = runs[1]
	if s then
		local mv, sc = {}, {}
		for i = 0, 3 do
			mv[#mv + 1] = '"' .. json_escape(move_name(s.moves[i])) .. '"'
			sc[#sc + 1] = tostring(s.scores[i])
		end
		parts[#parts + 1] = string.format('"target":"%s","moves":[%s],"actual":[%s]', json_escape(species_name(s.target)),
			table.concat(mv, ","), table.concat(sc, ","))
	end
	if pred and pred.moves then
		local ps, po = {}, {}
		for i = 0, 3 do
			local r = pred.moves[i]
			ps[#ps + 1] = r and (r.alt and string.format('[%d,%d]', r.score, r.alt) or tostring(r.score)) or "null"
			po[#po + 1] = string.format("%.3f", pred.odds[i] or 0)
		end
		parts[#parts + 1] = string.format('"role":%d,"predicted":[%s],"odds":[%s]', pred.role, table.concat(ps, ","), table.concat(po, ","))
	end
	pcall(function()
		local f = io.open(LOG_DIR .. "decisions.jsonl", "a")
		if f then f:write("{", table.concat(parts, ","), "}\n"); f:close() end
	end)
end

local function on_exit()
	local battler = emu:read8(AI_BATTLER)
	local runs = pending[battler]
	pending[battler] = nil
	if not runs then return end
	local choice = emu:readRegister("r0") & 0xFF
	local final_target = emu:read8(AI_TARGET)
	local lines = { string.format("frame %d  %s (%s)", emu:currentFrame(), species_name(battler), POSITION[battler] or battler) }
	local pred = predictions[battler]
	predictions[battler] = nil
	if pred and pred.moves then
		for _, l in ipairs(Model.format(pred)) do lines[#lines + 1] = l end
		lines[#lines + 1] = "  ACTUAL"
	elseif pred and pred.error then
		lines[#lines + 1] = "  PREDICT error: " .. pred.error
	end
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
	if pred and pred.moves and runs[1] then
		local match, total = 0, 0
		for i = 0, 3 do
			local r = pred.moves[i]
			if r then
				total = total + 1
				if runs[1].scores[i] == r.score or runs[1].scores[i] == r.alt then match = match + 1 end
			end
		end
		lines[#lines + 1] = string.format("  MODEL: %d/%d scores right, gave the chosen move %d%%", match, total,
			math.floor(((choice < 4 and pred.odds[choice]) or 0) * 100 + 0.5))
	end
	log_decision(battler, runs, choice, pred)
	table.insert(history, table.concat(lines, "\n"))
	while #history > MAX_HISTORY do table.remove(history, 1) end
	redraw()
end

local log -- set in the diagnostics section below

local ACTIVE_BATTLER = 0x02023BC4
local GBATTLE_STRUCT = 0x02023FE8
local GNEWBS = 0x0203E038
local ENEMY_PARTY, PLAYER_PARTY = 0x0202402C, 0x02024284
local SITE_PRESET = 0x090C80DE
local SITE_SWITCH = 0x090C8246
local SITE_KO_SWITCH = 0x09068B20
local SITE_CHOOSE_POKEMON = 0x09068A28 -- OpponentHandleChoosePokemon entry
-- 0x09068B0E: slot chosen (r4), just before 0x090D9D78 -> 0x090D6CB0 consumes the scorer's best
-- (best <- second best, second <- 6). Best/second must be read here, not at the store.
local SITE_KO_PICKED = 0x09068B0E
local SITE_SCORER = 0x090D7168        -- switch-in scorer entry
local SITE_SHOULD_SWITCH = 0x090D824C  -- ShouldSwitch entry
local SITE_SHOULD_SWITCH_RET = 0x090D8264 -- every return passes here: mov r0,r4 (r4 = result)
local FLAG_NAMES = { [0x01] = "KO foe", [0x02] = "resists all", [0x04] = "revenge kill", [0x08] = "walls",
	[0x10] = "2HKO", [0x20] = "removes hazards", [0x40] = "outspeeds", [0x80] = "faints to foe" }

-- ShouldSwitch 0x090D824C inlines CFRU's checks in CFRU's order. Each address below is the first
-- instruction of one check's block; the last block entered before a TRUE return is the reason.
-- Names follow CFRU ShouldSwitch (src/Battle_AI/ai_switching.c), matched by structure in the
-- decompile (abilities, globals and helper calls each block uses); RR moved several helpers to
-- its own code at 0x0935xxxx.
local SWITCH_CHECKS = {
	{ 0x090D831C, "absorb: a party member absorbs the foe's predicted move (Volt/Water Absorb, Flash Fire, ...)" },
	{ 0x090D8664, "pass Wish: Wish is about to heal, send in a Pokemon that needs it" },
	{ 0x090D8676, "stop locked move: foe is locked into a move a party member handles" },
	{ 0x090D8696, "Perish Song count is about to KO it" },
	{ 0x090D86A2, "Wonder Guard check (RR code 0x09350AC6)" },
	{ 0x090D86B2, "only bad moves left" },
	{ 0x090D8ABE, "Natural Cure / Regenerator: switch to heal" },
	{ 0x090D8AEC, "foe is semi-invulnerable (Fly, Dig, ...)" },
	{ 0x090D8F24, "Yawn: about to fall asleep" },
	{ 0x090D90AC, "asleep" },
	{ 0x090D9146, "taking annoying secondary damage (Leech Seed, Curse, toxic, ...)" },
	{ 0x090D9158, "avoid death: foe outspeeds and KOs, a party member survives" },
	{ 0x090D9182, "offensive stats too low" },
	{ 0x090D98B2, "save sweeper for later" },
}

local preset = {}        -- per battler: AI_monToSwitchIntoId[side] after ShouldSwitch said yes (6 = none)
local check_now = nil    -- name of the ShouldSwitch block being run
local switch_reason = {} -- per battler: reason from the last TRUE ShouldSwitch
local ko_ctx = {}        -- per battler: state while OpponentHandleChoosePokemon runs

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

-- Why this slot: compares it with the scorer's best and second best for the battler
-- (gNewBS +0x840/+0x841 +battler*2, written by the scorer 0x090D7168; GetMostSuitableMonToSwitchInto's
-- core 0x090D8168 returns the best unless a partner already took it, then the second best).
local function read_best(battler)
	local nbs = emu:read32(GNEWBS)
	return emu:read8(nbs + 0x840 + battler * 2), emu:read8(nbs + 0x841 + battler * 2)
end

local function pick_reason(battler, slot, scores, preset_slot, best, second)
	if best == nil then best, second = read_best(battler) end
	local lines = {}
	if preset_slot ~= nil and preset_slot ~= 6 then
		lines[#lines + 1] = string.format("  pick: slot %d was set by the decision itself (AI_monToSwitchIntoId), not by best score", preset_slot)
	elseif slot == best then
		lines[#lines + 1] = "  pick: best switch-in score"
	elseif slot == second then
		lines[#lines + 1] = string.format("  pick: second best (best, slot %d, already reserved by partner or a pending switch)", best)
	else
		lines[#lines + 1] = "  pick: no scored option; first healthy party slot (fallback)"
	end
	local ties = {}
	for i = 0, 5 do
		if i ~= slot and scores[i] ~= nil and scores[i] == scores[slot] then ties[#ties + 1] = tostring(i) end
	end
	if #ties > 0 and slot == best then
		lines[#lines + 1] = string.format("  tie with slot %s: scorer walks the party in order and a later equal score wins a 50%% Random2 flip (0x090D7168)",
			table.concat(ties, ", "))
	end
	return lines
end

local function report_switch(battler, slot, kind, extra)
	local side = battler & 1
	local nbs = emu:read32(GNEWBS)
	local base = side == 1 and ENEMY_PARTY or PLAYER_PARTY
	local _, to_name = party_species(side, slot)
	local lines = { string.format("frame %d  %s (%s) %s -> slot %d %s", emu:currentFrame(), species_name(battler),
		POSITION[battler] or battler, kind, slot, to_name) }
	for _, l in ipairs(extra) do lines[#lines + 1] = l end
	local scores, rows = {}, {}
	for i = 0, 5 do
		local id, name = party_species(side, i)
		if id ~= 0 then
			local hp = emu:read16(base + i * 100 + 0x56)
			scores[i] = signed16(emu:read16(nbs + 0x860 + side * 0xC + i * 2))
			local f = emu:read8(nbs + 0x878 + side * 6 + i)
			local mark = (i == slot) and "  <= CHOSEN" or ""
			if emu:read16(0x02023BCE + battler * 2) == i then mark = "  (on field)" end
			rows[#rows + 1] = string.format("    %d %-11s hp %3d  score %4d  flags 0x%02X %s%s", i, name, hp, scores[i], f,
				flags_text(f), mark)
		end
	end
	return lines, scores, rows
end

local function emit(lines, rows)
	lines[#lines + 1] = "  switch-in scores (latest scorer run for this side):"
	for _, r in ipairs(rows) do lines[#lines + 1] = r end
	-- Also log the switch block to decisions.jsonl (text lines, so a session can read it while playing).
	if LOG_DIR then
		pcall(function()
			local f = io.open(LOG_DIR .. "decisions.jsonl", "a")
			if f then
				local esc = {}
				for i, l in ipairs(lines) do esc[i] = '"' .. l:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end
				f:write('{"frame":', emu:currentFrame(), ',"switch":[', table.concat(esc, ","), ']}\n')
				f:close()
			end
		end)
	end
	table.insert(history, table.concat(lines, "\n"))
	while #history > MAX_HISTORY do table.remove(history, 1) end
	redraw()
end

local function on_should_switch() check_now = "pre-checks" end
for _, c in ipairs(SWITCH_CHECKS) do c[3] = function() check_now = c[2] end end
local function on_should_switch_ret()
	if emu:readRegister("r4") ~= 0 then
		switch_reason[emu:read8(ACTIVE_BATTLER)] = check_now
		log("ShouldSwitch TRUE: " .. tostring(check_now))
	end
	check_now = nil
end
local function on_preset() preset[emu:read8(ACTIVE_BATTLER)] = emu:readRegister("r3") & 0xFF end

-- OpponentHandleChoosePokemon also runs to carry out a voluntary switch (it reads the slot the AI
-- already stored), so it is only reported when the Pokemon fainted or no voluntary switch preceded it
-- (forced out by a move or item, for example U-turn or Eject Button).
local switched = {} -- per battler: voluntary switch already reported, waiting for its ChoosePokemon
local function on_switch()
	local battler = emu:read8(ACTIVE_BATTLER)
	local slot = emu:readRegister("r2") & 0xFF
	switched[battler] = true
	local reason = switch_reason[battler] or "unknown (ShouldSwitch block not seen)"
	local lines, scores, rows = report_switch(battler, slot, "SWITCHES", { "  reason: " .. reason })
	for _, l in ipairs(pick_reason(battler, slot, scores, preset[battler])) do lines[#lines + 1] = l end
	switch_reason[battler], preset[battler] = nil, nil
	emit(lines, rows)
end

local function on_choose_pokemon()
	local battler = emu:read8(ACTIVE_BATTLER)
	local gbs = emu:read32(GBATTLE_STRUCT)
	ko_ctx[battler] = { preset = emu:read8(gbs + 0x92 + (battler & 1)), rescored = false }
end
local function on_ko_picked()
	local ctx = ko_ctx[emu:read8(ACTIVE_BATTLER)]
	if ctx then ctx.best, ctx.second = read_best(emu:read8(ACTIVE_BATTLER)) end
end
local function on_scorer()
	local ctx = ko_ctx[emu:read8(ACTIVE_BATTLER)]
	if ctx then ctx.rescored = true end
end
local function on_ko_switch()
	local battler = emu:read8(ACTIVE_BATTLER)
	local slot = emu:readRegister("r4") & 0xFF
	local ctx = ko_ctx[battler] or {}
	ko_ctx[battler] = nil
	local fainted = emu:read16(BATTLE_MONS + battler * MON_SIZE + 0x28) == 0
	local voluntary = switched[battler]
	switched[battler] = nil
	if voluntary and not fainted then return end
	local extra = { fainted and "  reason: its Pokemon fainted" or "  reason: forced out by a move or item (U-turn, Volt Switch, Eject Button, ...)" }
	if ctx.preset ~= nil and ctx.preset == 6 then
		extra[#extra + 1] = ctx.rescored and "  scorer re-ran now (cached best was missing or fainted)"
			or "  used the scorer's cached result from earlier this turn"
	end
	local lines, scores, rows = report_switch(battler, slot,
		fainted and "replacement after faint" or "sent out (forced switch)", extra)
	for _, l in ipairs(pick_reason(battler, slot, scores, ctx.preset, ctx.best, ctx.second)) do lines[#lines + 1] = l end
	emit(lines, rows)
end

-- Diagnostics: every hook hit and error goes to the mGBA log and to logs/viewer.log next to
-- this script (git-ignored), so a session without output can be debugged afterwards.
local LOG_PATH
do
	local src = debug.getinfo(1, "S").source
	local dir = src:sub(1, 1) == "@" and src:sub(2):match("(.*/)") or nil
	if dir and not RR_VIEWER_NO_LOG then LOG_PATH = dir .. "logs/viewer.log"; LOG_DIR = dir .. "logs/" end
end
log = function(msg)
	local line = string.format("[rr-ai] %s", msg)
	pcall(function() console:log(line) end)
	if LOG_PATH then
		pcall(function()
			local f = io.open(LOG_PATH, "a")
			if f then f:write(os.date("%H:%M:%S "), line, "\n"); f:close() end
		end)
	end
end

local function guard(name, fn, quiet)
	return function()
		local frame = -1
		pcall(function() frame = emu:currentFrame() end)
		if not quiet then log(string.format("hit %s frame %d", name, frame)) end
		local ok, err = pcall(fn)
		if not ok then
			log(string.format("ERROR in %s: %s", name, tostring(err)))
			buffer:print(string.format("ERROR in %s: %s\n", name, tostring(err)))
		end
	end
end

local SITES = {
	{ "singles", snapshot, SITE_SINGLES }, { "doubles", snapshot, SITE_DOUBLES }, { "exit", on_exit, SITE_EXIT },
	{ "choice_entry", on_choice_entry, SITE_CHOICE_ENTRY, quiet = true },
	{ "preset", on_preset, SITE_PRESET }, { "switch", on_switch, SITE_SWITCH }, { "ko_switch", on_ko_switch, SITE_KO_SWITCH },
	{ "choose_pokemon", on_choose_pokemon, SITE_CHOOSE_POKEMON }, { "ko_picked", on_ko_picked, SITE_KO_PICKED, quiet = true }, { "scorer", on_scorer, SITE_SCORER, quiet = true },
	{ "should_switch", on_should_switch, SITE_SHOULD_SWITCH, quiet = true },
	{ "should_switch_ret", on_should_switch_ret, SITE_SHOULD_SWITCH_RET, quiet = true },
}
for _, c in ipairs(SWITCH_CHECKS) do SITES[#SITES + 1] = { string.format("check_%08X", c[1]), c[3], c[1], quiet = true } end
local breakpoint_ids = {}

-- Runs at load and again on every start/reset, since a restarted core may drop breakpoints.
local function install(why)
	if not emu then log("install(" .. tostring(why) .. "): no emu yet"); return end
	for _, id in ipairs(breakpoint_ids) do pcall(function() emu:clearBreakpoint(id) end) end
	breakpoint_ids = {}
	local parts = {}
	for _, site in ipairs(SITES) do
		local id = emu:setBreakpoint(guard(site[1], site[2], site.quiet), site[3])
		breakpoint_ids[#breakpoint_ids + 1] = id
		parts[#parts + 1] = string.format("%s@%08X=%s", site[1], site[3], tostring(id))
	end
	pending, preset, switched, switch_reason, ko_ctx, check_now = {}, {}, {}, {}, {}, nil
	log("install(" .. tostring(why) .. "): " .. table.concat(parts, " "))
	buffer:clear()
	buffer:print("RR AI viewer ready. Scores appear when the enemy picks a move.\n")
end

callbacks:add("start", function() install("start") end)
callbacks:add("reset", function() install("reset") end)
install("load")
