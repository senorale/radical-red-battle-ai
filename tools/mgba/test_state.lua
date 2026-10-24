-- Offline test for rr_state.lua: reads RAM from an EWRAM dump of a real battle (extract_state.py)
-- and ROM from the real ROM file, then prints the battle state.
-- Usage: lua test_state.lua <rr.gba> <ewram.bin>
local here = arg[0]:match("(.*/)") or "./"
package.path = here .. "?.lua;" .. package.path
local S = require("rr_state")

local function load(path) local f = assert(io.open(path, "rb")); local d = f:read("a"); f:close(); return d end
local rom, ewram = load(arg[1]), load(arg[2])

local mem = {
	read8 = function(_, a)
		if a >= 0x08000000 then return rom:byte(a - 0x08000000 + 1) end
		if a >= 0x02000000 and a < 0x02040000 then return ewram:byte(a - 0x02000000 + 1) end
		error(string.format("read outside EWRAM/ROM: 0x%08X", a))
	end,
}
function mem.read16(self, a) return self:read8(a) | self:read8(a + 1) << 8 end
function mem.read32(self, a) return self:read16(a) | self:read16(a + 2) << 16 end

print(table.concat(S.format(mem, S.read_battle(mem)), "\n"))
