-- Repeat test: load a savestate many times, wait a different number of frames each run before
-- mashing A, and record the enemy AI's first decision (switch or stay, why, which slot or move).
-- Shows whether a decision is fixed for a savestate or depends on timing (RNG).
--
-- Run (mGBA 0.11+ development build):
--   RR_TEST_STATE=roms/rr.ss6 RR_TEST_RUNS=30 RR_TEST_OUT=tools/mgba/logs/repeat.log \
--   /Applications/mGBA.app/Contents/MacOS/mGBA -C videoSync=0 -C audioSync=0 -C fpsTarget=6000 \
--     --script tools/mgba/repeat_switch_test.lua roms/rr.gba
-- Optional: RR_TEST_DELAY_STEP (frames added per run, default 7), RR_TEST_MAX_FRAMES (default 6000),
-- RR_TEST_SEED=random to overwrite the Random2 state (0x020386D0) with a different value each run.
-- Random2 does not advance with frames (same state at the decision whatever the delay, tested on
-- rr.ss6), so only a different seed shows the AI's Random2 coin flips.
-- RR_TEST_TRACE="090D2A5A:r0,..." logs a register at an address each time it runs before the decision,
-- with the move the AI is scoring (AI struct +2 moveConsidered).
-- RR_TEST_DECISIONS=N records N enemy decisions (turns) per run. When your active Pokemon faints,
-- the script alternates RIGHT and A to send out the next party slot.
-- Each move decision is also predicted by rr_model.lua from the battle state alone (at the
-- move-choice entry 0x090C82C0) and compared with the AI's real scores: 'model:' lists
-- predicted (score or score/with-coin) vs actual per move, '=' when they match.
-- Prints '== done' at the end; the caller closes mGBA.
--
-- Addresses (RR 4.1, see rr_ai_viewer.lua for the evidence):
--   0x090D824C ShouldSwitch entry, 0x090D8264 its single return (r4 = result), the check-block
--   entries below; 0x090C8246 voluntary switch stored (r2 = party slot); 0x090C837A move choice
--   exit (r0 = move slot); 0x020386D0 Random2 state; 0x02023BC4 gActiveBattler.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
package.path = here .. "?.lua;" .. package.path
local S = require("rr_state")
local Model = require("rr_model")

local STATE = os.getenv("RR_TEST_STATE")
local RUNS = tonumber(os.getenv("RR_TEST_RUNS") or "30")
local OUT = os.getenv("RR_TEST_OUT") or (here .. "logs/repeat.log")
local STEP = tonumber(os.getenv("RR_TEST_DELAY_STEP") or "7")
local MAX_FRAMES = tonumber(os.getenv("RR_TEST_MAX_FRAMES") or "4000")
local SEED_MODE = os.getenv("RR_TEST_SEED")
local DECISIONS = tonumber(os.getenv("RR_TEST_DECISIONS") or "1") -- enemy decisions (turns) recorded per run
-- RR_TEST_PLAN="1:switch4,3:switch2": after the enemy's decision for turn N, your action that turn is
-- a switch to that party slot (battle menu DOWN to POKEMON, A, then the slot in RR's 2 x 3 grid, A, A).
-- Every other turn mashes A (FIGHT, first move).
local PLAN = {}
for k, act in (os.getenv("RR_TEST_PLAN") or ""):gmatch("(%d+):(%w+)") do PLAN[tonumber(k)] = act end
local function plan_keys(act)
	local slot = tonumber(act:match("^switch(%d)$") or "")
	if not slot then return nil end
	local A, DOWN, RIGHT = 1 << C.GBA_KEY.A, 1 << C.GBA_KEY.DOWN, 1 << C.GBA_KEY.RIGHT
	-- RR's party menu is a 2 x 3 grid: slots 0, 2, 4 on the left, 1, 3, 5 on the right.
	local q = { { 0, 240 }, { DOWN, 4 }, { 0, 30 }, { A, 4 }, { 0, 120 } }
	for _ = 1, slot // 2 do q[#q + 1] = { DOWN, 4 }; q[#q + 1] = { 0, 20 } end
	if slot % 2 == 1 then q[#q + 1] = { RIGHT, 4 }; q[#q + 1] = { 0, 20 } end
	q[#q + 1] = { A, 4 }; q[#q + 1] = { 0, 60 }; q[#q + 1] = { A, 4 }; q[#q + 1] = { 0, 60 }
	return q
end
math.randomseed(12345)
local RANDOM2 = 0x020386D0
local ACTIVE_BATTLER = 0x02023BC4

-- Same list as SWITCH_CHECKS in rr_ai_viewer.lua (first instruction of each inlined check).
local CHECKS = {
	{ 0x090D831C, "absorb" }, { 0x090D8664, "pass Wish" }, { 0x090D8676, "stop locked move" },
	{ 0x090D8696, "Perish Song" }, { 0x090D86A2, "Wonder Guard" }, { 0x090D86B2, "only bad moves" },
	{ 0x090D8ABE, "Natural Cure/Regenerator" }, { 0x090D8AEC, "semi-invulnerable foe" },
	{ 0x090D8F24, "Yawn" }, { 0x090D90AC, "asleep" }, { 0x090D9146, "secondary damage" },
	{ 0x090D9158, "avoid death" }, { 0x090D9182, "offensive stats low" }, { 0x090D98B2, "save sweeper" },
}

local function write(line)
	local f = io.open(OUT, "a")
	if f then f:write(line, "\n"); f:close() end
	console:log(line)
end

local run, phase, frame, delay = 0, "load", 0, 0
local rec          -- current run's record
local tally = {}   -- outcome -> count

local function outcome_key(r)
	if r.switched then return string.format("SWITCH to slot %s (%s)", tostring(r.slot), r.reason or "?") end
	if r.move then return string.format("STAY, move slot %d (%s)", r.move, r.move_name or "?") end
	return "TIMEOUT"
end

local last_frame = 0 -- frame of the previous decision in this run
local function field_text()
	local t = {}
	for bnk = 0, 1 do
		local m = S.read_battle_mon(emu, bnk)
		local st = {}
		for k = 1, 7 do
			local v = m.stages[S.STAGE_NAMES[k]] - 6
			if v ~= 0 then st[#st + 1] = string.format("%s%+d", S.STAGE_NAMES[k], v) end
		end
		t[#t + 1] = string.format("%s %s %d/%d%s", bnk == 0 and "you" or "foe", S.species_name(emu, m.species), m.hp, m.max_hp,
			#st > 0 and (" " .. table.concat(st, " ")) or "")
	end
	return table.concat(t, ", ")
end
local function finish()
	local key = outcome_key(rec) .. " {" .. field_text() .. "}"
	rec.done = (rec.done or 0) + 1
	if rec.done < DECISIONS and (rec.switched or rec.move) then
		rec.history = rec.history or {}
		rec.history[#rec.history + 1] = string.format("[turn %d: %s%s]", rec.done, key, rec.scores and (" scores: " .. rec.scores) or "")
		rec.trace = rec.trace or {}
		rec.trace[#rec.trace + 1] = "| end of turn " .. rec.done
		rec.decided, rec.stayed, rec.switched, rec.move, rec.move_name, rec.scores, rec.slot, rec.reason = nil
		rec.checks, rec.check = {}, nil
		last_frame = frame
		if PLAN[rec.done] then rec.queue = plan_keys(PLAN[rec.done]) end
		return
	end
	if rec.history then key = table.concat(rec.history, " ") .. " [turn " .. rec.done .. ": " .. key .. "]" end
	tally[key] = (tally[key] or 0) + 1
	write(string.format("run %2d delay %4d frames_to_decision %4d random2_at_ShouldSwitch 0x%08X checks_entered [%s] => %s%s%s",
		run, delay, frame, rec.rand2 or 0, table.concat(rec.checks, ","), key, rec.scores and ("  scores: " .. rec.scores) or "",
		rec.trace and ("  trace: " .. table.concat(rec.trace, "; ")) or ""))
	if not rec.switched and not rec.move then emu:screenshot(here .. "logs/repeat_timeout_" .. run .. ".png") end
	phase = "load"
end

local function on_should_switch()
	if phase ~= "run" or rec.decided then return end
	rec.rand2 = rec.rand2 or emu:read32(RANDOM2)
	rec.checks, rec.check = {}, "pre-checks"
end
local function on_should_switch_ret()
	if phase ~= "run" or rec.decided then return end
	if emu:readRegister("r4") ~= 0 then rec.switched, rec.reason = true, rec.check
	else rec.stayed = true end
end
local function on_switch_store()
	if phase ~= "run" or rec.decided then return end
	rec.slot = emu:readRegister("r2") & 0xFF
	local id = emu:read16(S.ENEMY_PARTY + rec.slot * 100 + 0x20)
	rec.slot = string.format("%d %s", rec.slot, S.species_name(emu, id))
	rec.decided = true
	finish()
end
-- 0x090C83AC: singles scores final (AI struct = *(gBattleResources 0x02023FF4) + 0x14, score[4] at +4).
local function on_scores()
	if phase ~= "run" or rec.decided or not rec.stayed then return end
	local ai = emu:read32(emu:read32(0x02023FF4) + 0x14)
	local b = emu:read8(0x02023D6B)
	local t = {}
	for i = 0, 3 do
		local id = emu:read16(S.BATTLE_MONS + b * S.BATTLE_MON_SIZE + 0x0C + i * 2)
		if id ~= 0 then t[#t + 1] = string.format("%s %d", S.move_name(emu, id), S.signed8(emu:read8(ai + 4 + i))) end
	end
	rec.scores = table.concat(t, ", ")
	if rec.pred then
		local c, match, total = {}, 0, 0
		for i = 0, 3 do
			local r = rec.pred.moves[i]
			if r then
				local actual = S.signed8(emu:read8(ai + 4 + i))
				local ok = actual == r.score or actual == r.alt
				total = total + 1
				if ok then match = match + 1 end
				c[#c + 1] = string.format("%s %s%s%d%s", r.name, r.alt and (r.score .. "/" .. r.alt) or tostring(r.score),
					ok and "=" or "!=", actual, r.unknown and "?" or "")
			end
		end
		rec.model = string.format("model %d/%d scores [%s] role %s cached-dmg %d your-predicted %s (prio %d) ai-first %s strongest model %s cache %s %s", match, total, table.concat(c, ", "),
			Model.ROLE_NAMES[rec.pred.role] or tostring(rec.pred.role), rec.pred.cached or 0, S.move_name(emu, rec.pred.foe_pred), rec.pred.foe_prio, tostring(rec.pred.ai_first), S.move_name(emu, rec.pred.strongest_model), S.move_name(emu, rec.pred.strongest_cache), rec.pred.dbg or "")
		rec.scores = rec.scores .. " | " .. rec.model
	end
end
local function on_choice_entry()
	if phase ~= "run" or rec.decided then return end
	local b = emu:read8(0x02023BC4)
	local ok, p = pcall(Model.predict, emu, b, b ~ 1, { cache = os.getenv("RR_TEST_MODEL_CACHE") ~= "0" })
	rec.pred = ok and p or nil
	if not ok then rec.model_error = tostring(p) end
end
local function on_move_exit()
	if phase ~= "run" or rec.decided or not rec.stayed then return end
	rec.move = emu:readRegister("r0") & 0xFF
	local b = emu:read8(0x02023D6B)
	if rec.move < 4 then rec.move_name = S.move_name(emu, emu:read16(S.BATTLE_MONS + b * S.BATTLE_MON_SIZE + 0x0C + rec.move * 2)) end
	if rec.pred and rec.move < 4 then
		rec.scores = (rec.scores or "") .. string.format(" | model gave the chosen move %d%%",
			math.floor((rec.pred.odds[rec.move] or 0) * 100 + 0.5))
	elseif rec.model_error then
		rec.scores = (rec.scores or "") .. " | model error: " .. rec.model_error
	end
	rec.pred, rec.model_error = nil, nil
	rec.decided = true
	finish()
end

emu:setBreakpoint(on_should_switch, 0x090D824C)
emu:setBreakpoint(on_should_switch_ret, 0x090D8264)
emu:setBreakpoint(on_switch_store, 0x090C8246)
emu:setBreakpoint(on_move_exit, 0x090C837A)
for spec in (os.getenv("RR_TEST_TRACE") or ""):gmatch("[^,]+") do
	local addr, reg = spec:match("^(%x+):(%w+)$")
	assert(addr, "bad RR_TEST_TRACE entry " .. spec)
	emu:setBreakpoint(function()
		if phase ~= "run" or rec.decided then return end
		local ai = emu:read32(emu:read32(0x02023FF4) + 0x14)
		rec.trace = rec.trace or {}
		local v = emu:readRegister(reg)
		rec.trace[#rec.trace + 1] = string.format("%s %s=%s (%s, script %d)", addr, reg, (reg == "r14" or reg == "lr") and string.format("%08X", v) or tostring(v), S.move_name(emu, emu:read16(ai + 2)), emu:read8(ai + 0x11))
	end, tonumber(addr, 16))
end
emu:setBreakpoint(on_scores, 0x090C83AC)
emu:setBreakpoint(on_choice_entry, 0x090C82C0)
for _, c in ipairs(CHECKS) do
	emu:setBreakpoint(function()
		if phase == "run" and rec.checks and not rec.decided then
			rec.check = c[2]
			rec.checks[#rec.checks + 1] = c[2]
		end
	end, c[1])
end

callbacks:add("frame", function()
	if phase == "done" then return end
	if phase == "load" then
		if run >= RUNS then
			write("== summary over " .. RUNS .. " runs:")
			for k, v in pairs(tally) do write(string.format("  %3d x %s", v, k)) end
			write("== done")
			phase = "done"
			emu:setKeys(0)
			return
		end
		run = run + 1
		delay = (run - 1) * STEP
		frame = 0
		rec = { checks = {} }
		last_frame = 0
		assert(emu:loadStateFile(STATE), "could not load " .. tostring(STATE))
		if SEED_MODE == "random" then emu:write32(RANDOM2, math.random(0, 0xFFFFFFFF)) end
		phase = "run"
		return
	end
	frame = frame + 1
	local keys = 0
	if frame > delay and (frame - delay) % 12 < 3 then keys = 1 << C.GBA_KEY.A end
	if rec.queue and #rec.queue > 0 then
		local q = rec.queue[1]
		emu:setKeys(q[1])
		q[2] = q[2] - 1
		if q[2] <= 0 then table.remove(rec.queue, 1) end
		return
	end
	-- Your active Pokemon fainted: alternate RIGHT and A until it is replaced. In the party menu RIGHT
	-- moves the cursor off the fainted first slot (and does nothing after that), A opens the menu
	-- and sends the Pokemon out.
	local fainted = emu:read16(S.BATTLE_MONS + 0x28) == 0 and emu:read8(S.BATTLERS_COUNT) > 0
	if fainted and frame % 24 >= 12 and frame % 24 < 15 then keys = 1 << C.GBA_KEY.RIGHT end
	emu:setKeys(keys)
	if frame > math.max(delay, last_frame) + MAX_FRAMES then rec.done = DECISIONS; finish() end
end)

write(string.format("== repeat test: state %s, %d runs, delay step %d frames, seed %s", tostring(STATE), RUNS, STEP, tostring(SEED_MODE)))
