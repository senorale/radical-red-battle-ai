-- Offline test for rr_showdown_export.lua: fakes mGBA's emu/console/callbacks, serves ROM reads
-- from the ROM file and RAM reads from a raw state made by extract_state.py, then prints the export.
-- Usage: lua test_showdown_export.lua <rr.gba> <state.raw> <path to rr_showdown_export.lua>
local rom_path, raw_path, script = arg[1], arg[2], arg[3]
local function slurp(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local rom, raw = slurp(rom_path), slurp(raw_path)
local EWRAM_OFF, IWRAM_OFF = 0x21000, 0x19000 -- see extract_state.py

emu = {
	read8 = function(_, a)
		local region = a >> 24
		if region >= 8 then return rom:byte(a - 0x08000000 + 1) or 0 end
		if region == 2 then return raw:byte(EWRAM_OFF + (a - 0x02000000) + 1) or 0 end
		if region == 3 then return raw:byte(IWRAM_OFF + (a - 0x03000000) + 1) or 0 end
		return 0
	end,
}
-- Like mGBA (GBA bus behavior): a misaligned read returns the aligned value rotated right.
function emu.read16(self, a)
	local b = a & ~1
	local v = self:read8(b) | self:read8(b + 1) << 8
	return a & 1 == 1 and ((v >> 8) | (v << 8)) & 0xFFFF or v
end
function emu.read32(self, a)
	local b = a & ~3
	local v = self:read8(b) | self:read8(b + 1) << 8 | self:read8(b + 2) << 16 | self:read8(b + 3) << 24
	local s = 8 * (a & 3)
	return s > 0 and ((v >> s) | (v << (32 - s))) & 0xFFFFFFFF or v
end
local tabs = {}
console = {
	createBuffer = function(_, title)
		local b = { lines = {} }
		b.clear = function() b.lines = {} end
		b.setSize = function() end
		b.print = function(_, s) b.lines[#b.lines + 1] = s end
		tabs[title] = b
		return b
	end,
	log = function(_, s) print(s) end,
}
callbacks = { add = function() end }

dofile(script)
for _, title in ipairs({ "Showdown Export", "Hidden Powers" }) do
	print("== " .. title)
	print(table.concat(tabs[title].lines))
end
