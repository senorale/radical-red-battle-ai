-- Offline test for rr_ai_viewer.lua: fakes mGBA's emu/console/callbacks, serves ROM reads from
-- the real ROM file and RAM reads from a small fake battle, then fires the breakpoints.
-- Usage: lua test_viewer.lua <rr.gba> <path to rr_ai_viewer.lua>
local rom_path, viewer = arg[1], arg[2]
local f = assert(io.open(rom_path, "rb")); local rom = f:read("a"); f:close()

local ram, regs, bps = {}, { r0 = 0 }, {}
local function w8(a, v) ram[a] = v & 0xFF end
local function w16(a, v) w8(a, v); w8(a + 1, v >> 8) end
local function w32(a, v) w16(a, v); w16(a + 2, v >> 16) end

emu = {
	read8 = function(_, a)
		if a >= 0x08000000 then return rom:byte(a - 0x08000000 + 1) end
		return ram[a] or 0
	end,
	readRegister = function(_, r) return regs[r] end,
	currentFrame = function() return 1234 end,
	setBreakpoint = function(_, fn, a) bps[a] = fn end,
}
function emu.read16(self, a) return self:read8(a) | self:read8(a + 1) << 8 end
function emu.read32(self, a) return self:read16(a) | self:read16(a + 2) << 16 end
local out = {}
console = { createBuffer = function() return { clear = function() out = {} end, print = function(_, s) out[#out + 1] = s end } end }
callbacks = { add = function() end }

dofile(viewer)

-- Fake doubles turn: foe left (battler 1, Charizard #6) scores its moves vs your left (0, Venusaur #3)
-- and your right (2, Pikachu #25), then picks slot 1 against battler 2.
local mons, ai = 0x02023BE4, 0x02031000
w32(0x02023FF4, 0x02030000); w32(0x02030000 + 0x14, ai)
w16(mons + 0 * 0x58, 3); w16(mons + 1 * 0x58, 6); w16(mons + 2 * 0x58, 25)
local moves = { 53, 403, 89, 182 } -- Flamethrower, Air Slash, Earthquake, Protect (vanilla IDs)
for i = 0, 3 do w16(mons + 1 * 0x58 + 0x0C + i * 2, moves[i + 1]) end
w8(0x02023D6B, 1)

local function score(target, s) w8(0x02023D6C, target); for i = 0, 3 do w8(ai + 4 + i, s[i + 1] & 0xFF) end end
score(0, { 112, 100, 100, 92 }); bps[0x090C875C]()
score(2, { 100, 115, 100, 92 }); bps[0x090C875C]()
w8(0x02023D6C, 2); regs.r0 = 1; bps[0x090C837A]()

-- Fake switch: foe left (battler 1, party slot 0) switches to slot 2 picked by the scorer, then a
-- post-KO replacement picks slot 1. Party: Charizard, Blastoise #9, Raichu #26.
local nbs, enemy = 0x02032000, 0x0202402C
w32(0x02023FE8, 0x02033000); w32(0x0203E038, nbs)
w8(0x02023BC4, 1); w16(0x02023BCE + 2, 0)
for i, sp in ipairs({ 6, 9, 26 }) do w16(enemy + (i - 1) * 100 + 0x20, sp); w16(enemy + (i - 1) * 100 + 0x56, 50 + i) end
local scores, flags = { 0, -1, 33 }, { 0, 0x80, 0x41 }
for i = 1, 3 do w16(nbs + 0x860 + 0xC + (i - 1) * 2, scores[i] & 0xFFFF); w8(nbs + 0x878 + 6 + (i - 1), flags[i]) end
regs.r3 = 6; bps[0x090C80DE]()
regs.r2 = 2; bps[0x090C8246]()
regs.r4 = 1; bps[0x09068B20]()

print(table.concat(out))
