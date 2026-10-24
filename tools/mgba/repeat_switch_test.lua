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
-- Prints '== done' at the end; the caller closes mGBA.
--
-- Addresses (RR 4.1, see rr_ai_viewer.lua for the evidence):
--   0x090D824C ShouldSwitch entry, 0x090D8264 its single return (r4 = result), the check-block
--   entries below; 0x090C8246 voluntary switch stored (r2 = party slot); 0x090C837A move choice
--   exit (r0 = move slot); 0x020386D0 Random2 state; 0x02023BC4 gActiveBattler.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
package.path = here .. "?.lua;" .. package.path
local S = require("rr_state")

local STATE = os.getenv("RR_TEST_STATE")
local RUNS = tonumber(os.getenv("RR_TEST_RUNS") or "30")
local OUT = os.getenv("RR_TEST_OUT") or (here .. "logs/repeat.log")
local STEP = tonumber(os.getenv("RR_TEST_DELAY_STEP") or "7")
local MAX_FRAMES = tonumber(os.getenv("RR_TEST_MAX_FRAMES") or "6000")
local SEED_MODE = os.getenv("RR_TEST_SEED")
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

local function finish()
	local key = outcome_key(rec)
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
end
local function on_move_exit()
	if phase ~= "run" or rec.decided or not rec.stayed then return end
	rec.move = emu:readRegister("r0") & 0xFF
	local b = emu:read8(0x02023D6B)
	if rec.move < 4 then rec.move_name = S.move_name(emu, emu:read16(S.BATTLE_MONS + b * S.BATTLE_MON_SIZE + 0x0C + rec.move * 2)) end
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
		rec.trace[#rec.trace + 1] = string.format("%s %s=%d (%s)", addr, reg, emu:readRegister(reg),
			S.move_name(emu, emu:read16(ai + 2)))
	end, tonumber(addr, 16))
end
emu:setBreakpoint(on_scores, 0x090C83AC)
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
		assert(emu:loadStateFile(STATE), "could not load " .. tostring(STATE))
		if SEED_MODE == "random" then emu:write32(RANDOM2, math.random(0, 0xFFFFFFFF)) end
		phase = "run"
		return
	end
	frame = frame + 1
	local keys = 0
	if frame > delay and (frame - delay) % 12 < 3 then keys = 1 << C.GBA_KEY.A end
	emu:setKeys(keys)
	if frame > delay + MAX_FRAMES then finish() end
end)

write(string.format("== repeat test: state %s, %d runs, delay step %d frames, seed %s", tostring(STATE), RUNS, STEP, tostring(SEED_MODE)))
