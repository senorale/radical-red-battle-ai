// Decompile Thumb functions in a GBA ROM by address, labeling known symbols first.
// Args: <symbols.txt> <outDir> <depth> <addrHex>...
//   or: <symbols.txt> <outDir> range <startHex> <endHex>
// Range mode decompiles every function found in [start, end) and writes <outDir>/index.tsv.
// It resumes: functions that already have an output file are skipped.
import ghidra.app.script.GhidraScript;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.*;
import ghidra.program.model.lang.Register;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.symbol.*;
import java.io.*;
import java.math.BigInteger;
import java.nio.file.*;
import java.util.*;

public class DecompileFns extends GhidraScript {
	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		String symPath = args[0];
		File outDir = new File(args[1]);
		boolean range = args[2].equals("range");
		int depth = range ? Integer.MAX_VALUE : Integer.parseInt(args[2]);
		long rangeStart = range ? Long.parseLong(args[3], 16) : 0x09000000L;
		long rangeEnd = range ? Long.parseLong(args[4], 16) : 0x0A000000L;
		outDir.mkdirs();

		AddressSpace space = currentProgram.getAddressFactory().getDefaultAddressSpace();
		Register tmode = currentProgram.getRegister("TMode");
		ProgramContext ctx = currentProgram.getProgramContext();
		Address romStart = space.getAddress(0x08000000L);
		Address romEnd = space.getAddress(0x08000000L + currentProgram.getMemory().getBlock(romStart).getSize() - 1);
		ctx.setValue(tmode, romStart, romEnd, BigInteger.ONE);
		currentProgram.getMemory().getBlock(romStart).setWrite(false);

		SymbolTable st = currentProgram.getSymbolTable();
		for (String line : Files.readAllLines(Paths.get(symPath))) {
			String[] p = line.trim().split("\\s+");
			if (p.length < 2) continue;
			Address a = space.getAddress(Long.parseLong(p[1], 16));
			try { st.createLabel(a, p[0], SourceType.USER_DEFINED).setPrimary(); } catch (Exception e) { }
		}

		indexBlCallers(romStart);

		DecompInterface di = new DecompInterface();
		di.openProgram(currentProgram);
		Set<Address> done = new HashSet<>();
		Deque<Object[]> queue = new ArrayDeque<>();
		Map<Long, String> seedSource = new HashMap<>();
		Set<Long> existing = new HashSet<>();
		PrintWriter index = null;
		if (range) {
			for (Map.Entry<Long, String> e : findEntries(romStart, rangeStart, rangeEnd, symPath).entrySet()) {
				seedSource.put(e.getKey(), e.getValue());
				knownEntries.add(e.getKey());
				queue.add(new Object[] { space.getAddress(e.getKey()), 0 });
			}
			File[] prior = outDir.listFiles();
			if (prior != null)
				for (File pf : prior)
					if (pf.getName().matches("[0-9A-F]{8}_.*\\.c")) existing.add(Long.parseLong(pf.getName().substring(0, 8), 16));
			File idx = new File(outDir, "index.tsv");
			boolean fresh = !idx.exists();
			index = new PrintWriter(new FileWriter(idx, true), true);
			if (fresh) index.println("addr\tname\tbytes\tstatus\tswitches\tfound_by\tend");
			println("SEEDS " + seedSource.size() + " (already done: " + existing.size() + ")");
		} else {
			for (int i = 3; i < args.length; i++)
				queue.add(new Object[] { space.getAddress(Long.parseLong(args[i], 16) & ~1L), 0 });
		}

		int count = 0;
		while (!queue.isEmpty()) {
			Object[] item = queue.poll();
			Address a = (Address) item[0];
			int d = (Integer) item[1];
			if (!done.add(a)) continue;
			if (a.getOffset() < 0x08000000L) continue;
			if (range && existing.contains(a.getOffset())) continue;
			if (monitor.isCancelled()) break;
			String found = seedSource.getOrDefault(a.getOffset(), "callee");
			if (range) knownEntries.add(a.getOffset());
			fixSwitches(a);
			Function f = getFunctionAt(a);
			if (f == null) {
				new CreateFunctionCmd(a).applyTo(currentProgram, monitor);
				f = getFunctionAt(a);
			}
			if (f == null) {
				println("NOFUNC " + a);
				if (index != null) index.println(String.format("%08X\t\t0\tNOFUNC\t0\t%s\t", a.getOffset(), found));
				continue;
			}
			// A switch may have been patched while an earlier function's pass followed calls into
			// this one, so attach every patched switch that lies in this function's body.
			Map<Address, List<Address>> switches = ownSwitches(f);
			if (!switches.isEmpty()) {
				CreateFunctionCmd.fixupFunctionBody(currentProgram, f, monitor);
				switches = ownSwitches(f);
			}
			for (Map.Entry<Address, List<Address>> e : switches.entrySet()) {
				try {
					new ghidra.program.model.pcode.JumpTable(e.getKey(), new ArrayList<>(e.getValue()), true, 0).writeOverride(f);
				} catch (Exception ex) { println("SWITCHFAIL " + e.getKey() + " " + ex.getMessage()); }
			}
			if (!switches.isEmpty())
				CreateFunctionCmd.fixupFunctionBody(currentProgram, f, monitor);
			fixLongCalls(f);
			DecompileResults r = di.decompileFunction(f, 120, monitor);
			String c = r.decompileCompleted() ? r.getDecompiledFunction().getC() : ("// FAILED " + r.getErrorMessage());
			String name = f.getName().replaceAll("[^A-Za-z0-9_]", "_");
			Files.write(Paths.get(outDir.getPath(), String.format("%08X_%s.c", a.getOffset(), name)), c.getBytes());
			count++;
			println((r.decompileCompleted() ? "OK " : "FAILED ") + a + " " + f.getName() + (range ? " [" + count + "]" : ""));
			if (index != null)
				index.println(String.format("%08X\t%s\t%d\t%s\t%d\t%s\t%08X", a.getOffset(), f.getName(), f.getBody().getNumAddresses(),
					r.decompileCompleted() ? "OK" : "FAILED", switches.size(), found, f.getBody().getMaxAddress().getOffset()));
			if (d < depth) {
				InstructionIterator ii = currentProgram.getListing().getInstructions(f.getBody(), true);
				while (ii.hasNext()) {
					for (Reference ref : ii.next().getReferencesFrom()) {
						Address t = ref.getToAddress();
						if (ref.getReferenceType().isCall() && t.getOffset() >= rangeStart && t.getOffset() < rangeEnd
							&& !f.getBody().contains(t) // long branch inside this function
							&& (currentProgram.getMemory().getShort(t) & 0xFF87) != 0x4700)
							queue.add(new Object[] { t, d + 1 });
					}
				}
			}
		}
		di.dispose();
		if (index != null) index.close();
		println("DONE " + count + " decompiled this run");
	}

	// Function entries in [start, end): "bl" targets, code pointers anywhere in the ROM, and symbols.
	// "bl" targets need a push prologue, unless the call comes from inside the range and is far away
	// (near ones may be long branches inside a function). Pointers need a push prologue, since data
	// words often look like pointers. Leaf functions without a push are found later as callees.
	private Map<Long, String> findEntries(Address romStart, long start, long end, String symPath) throws Exception {
		Memory mem = currentProgram.getMemory();
		int size = (int) mem.getBlock(romStart).getSize();
		byte[] rom = new byte[size];
		mem.getBytes(romStart, rom);
		Map<Long, String> out = new TreeMap<>();
		for (long a = 0x08000000L; a + 4 <= 0x08000000L + size; a += 2) {
			int h1 = hw(rom, a), h2 = hw(rom, a + 2);
			if ((h1 & 0xF800) != 0xF000 || (h2 & 0xF800) != 0xF800) continue;
			int hi = h1 & 0x7FF;
			if ((hi & 0x400) != 0) hi -= 0x800;
			long t = a + 4 + ((long) hi << 12) + ((h2 & 0x7FF) << 1);
			if (t < start || t >= end) continue;
			int th = hw(rom, t);
			if ((th & 0xFF87) == 0x4700) continue; // bx rN stub
			boolean inside = a >= start && a < end;
			if (startsWithPush(rom, t) || (inside && Math.abs(t - a) >= 0x8000)) out.putIfAbsent(t, "bl");
		}
		for (int off = 0; off + 4 <= size; off += 4) {
			long v = (rom[off] & 0xFFL) | (rom[off + 1] & 0xFFL) << 8 | (rom[off + 2] & 0xFFL) << 16 | (rom[off + 3] & 0xFFL) << 24;
			if ((v & 1) == 0) continue;
			long t = v & ~1L;
			if (t >= start && t < end && startsWithPush(rom, t)) out.putIfAbsent(t, "pointer");
		}
		// symbols.txt kinds (make_symbols.py): hook and routineptr targets are code that may not
		// start with a push; repoint and datascan are data tables; aitable holds the AIScript_*
		// functions plus the table itself; ld names both, so it needs a push or a call/pointer.
		for (String line : Files.readAllLines(Paths.get(symPath))) {
			String[] p = line.trim().split("\\s+");
			if (p.length < 3) continue;
			long a = Long.parseLong(p[1], 16) & ~1L;
			if (a < start || a >= end) continue;
			String kind = p[2];
			boolean code = kind.equals("hook") || kind.equals("routineptr")
				|| (kind.equals("aitable") && p[0].startsWith("AIScript_"))
				|| (kind.equals("ld") && (out.containsKey(a) || startsWithPush(rom, a)));
			if (code) out.put(a, "symbol");
		}
		return out;
	}

	// A push {...} within the first three instructions: GCC sometimes schedules a load or move
	// before the push (0x0907797C, 0x0906CC5C, 0x090961CC). Only those forms may come first, which
	// keeps pointer-like data words from passing: mov rN,#imm; ldr rN,[pc,#]; ldr/ldrb/ldrh rN,[rM,#];
	// mov with a high register.
	private static boolean startsWithPush(byte[] rom, long t) {
		for (int i = 0; i < 3; i++) {
			int h = hw(rom, t + 2L * i);
			if ((h & 0xFE00) == 0xB400) return true;
			int f = h & 0xF800;
			if (f != 0x2000 && f != 0x4800 && f != 0x6800 && f != 0x7800 && f != 0x8800 && (h & 0xFF00) != 0x4600)
				return false;
		}
		return false;
	}

	private static int hw(byte[] rom, long addr) {
		int o = (int) (addr - 0x08000000L);
		if (o < 0 || o + 1 >= rom.length) return 0;
		return (rom[o] & 0xFF) | (rom[o + 1] & 0xFF) << 8;
	}

	// Every switch patched so far (bx address -> case targets), whichever pass patched it.
	private final Map<Address, List<Address>> patchedSwitches = new HashMap<>();

	// Every "bl" in the ROM, target -> call sites (raw bytes, so data that looks like bl is included).
	private final Map<Long, List<Long>> blCallers = new HashMap<>();

	private void indexBlCallers(Address romStart) throws Exception {
		int size = (int) currentProgram.getMemory().getBlock(romStart).getSize();
		byte[] rom = new byte[size];
		currentProgram.getMemory().getBytes(romStart, rom);
		for (long a = 0x08000000L; a + 4 <= 0x08000000L + size; a += 2) {
			int h1 = hw(rom, a), h2 = hw(rom, a + 2);
			if ((h1 & 0xF800) != 0xF000 || (h2 & 0xF800) != 0xF800) continue;
			int hi = h1 & 0x7FF;
			if ((hi & 0x400) != 0) hi -= 0x800;
			long t = a + 4 + ((long) hi << 12) + ((h2 & 0x7FF) << 1);
			blCallers.computeIfAbsent(t, k -> new ArrayList<>()).add(a);
		}
	}

	// Known function entries (range-mode seeds plus functions created so far).
	private final TreeSet<Long> knownEntries = new TreeSet<>();

	// A long-branch label is only reached from inside its own function. A bl from before the entry,
	// or from past another known entry, means the target is a function: 0x0906F284 (56 callers),
	// 0x090DEA90 (8 instructions before its push; also called from 0x090D914C). Without known
	// entries (address mode), a bl more than 64KB past the entry counts as outside.
	private boolean calledFromOutside(Address t, Address entry) {
		List<Long> sites = blCallers.get(t.getOffset());
		if (sites == null) return false;
		long e = entry.getOffset();
		for (long s : sites) {
			if (s < e) return true;
			Long owner = knownEntries.floor(s);
			if (owner != null && owner > e) return true;
			if (knownEntries.isEmpty() && s >= e + 0x10000L) return true;
		}
		return false;
	}

	private Map<Address, List<Address>> ownSwitches(Function f) {
		Map<Address, List<Address>> own = new TreeMap<>();
		for (Map.Entry<Address, List<Address>> e : patchedSwitches.entrySet())
			if (f.getBody().contains(e.getKey())) own.put(e.getKey(), e.getValue());
		return own;
	}

	// libgcc Thumb switch helpers (__gnu_thumb1_case_*): uqi, uhi, sqi, shi, si.
	private static final long[] CASE_HELPERS = { 0x090003C4L, 0x090003D6L, 0x090003EAL, 0x090003FCL, 0x09000410L };

	// Walk the function's own control flow from its entry (existing and new instructions alike, so
	// the result does not depend on what earlier functions already disassembled). Along the way:
	// long branches ("bl X" to a label inside this function) become plain branches, and each
	// "bl case_helper" + inline table becomes "bx r0; nop" in the in-memory program with its case
	// targets. Returns bx address -> case targets for jump-table overrides.
	private Map<Address, List<Address>> fixSwitches(Address entry) throws Exception {
		Map<Address, List<Address>> out = new LinkedHashMap<>();
		Listing listing = currentProgram.getListing();
		Memory mem = currentProgram.getMemory();
		for (int iter = 0; iter < 400; iter++) {
			boolean patched = false, branched = false;
			InstructionIterator it = listing.getInstructions(walkFlow(entry), true);
			while (it.hasNext()) {
				Instruction ins = it.next();
				if (!ins.getMnemonicString().equals("bl") || ins.getFlows().length == 0) continue;
				long t = ins.getFlows()[0].getOffset();
				int kind = -1;
				for (int k = 0; k < CASE_HELPERS.length; k++) if (CASE_HELPERS[k] == t) kind = k;
				if (kind < 0) {
					if (ins.getFlowOverride() == ghidra.program.model.listing.FlowOverride.BRANCH) continue;
					long d = t - entry.getOffset();
					int hw = mem.getShort(ins.getFlows()[0]) & 0xFFFF;
					boolean prologue = pushBeforeFlow(ins.getFlows()[0]); // push {...}, maybe after setup code
					boolean stub = (hw & 0xFF87) == 0x4700;    // bx rN
					if (d > 0 && d < 0x8000 && !prologue && !stub && !returnsViaLr(ins.getFlows()[0])
						&& !calledFromOutside(ins.getFlows()[0], entry)
						&& getFunctionAt(ins.getFlows()[0]) == null) {
						ins.setFlowOverride(ghidra.program.model.listing.FlowOverride.BRANCH);
						branched = true;
					}
					continue;
				}
				Address bl = ins.getAddress();
				int n = caseCount(ins);
				long lr = bl.getOffset() + 4;
				List<Address> targets = new ArrayList<>();
				long tableEnd;
				if (kind == 4) {
					long base = (lr + 3) & ~3L;
					for (int i = 0; i < n; i++) targets.add(bl.getNewAddress((base + mem.getInt(bl.getNewAddress(base + 4L * i))) & ~1L));
					tableEnd = base + 4L * n;
				} else {
					int w = (kind == 1 || kind == 3) ? 2 : 1;
					for (int i = 0; i < n; i++) {
						Address ea = bl.getNewAddress(lr + (long) w * i);
						long v = (w == 1) ? (kind == 2 ? mem.getByte(ea) : mem.getByte(ea) & 0xFF)
							: (kind == 3 ? mem.getShort(ea) : mem.getShort(ea) & 0xFFFF);
						targets.add(bl.getNewAddress(lr + 2 * v));
					}
					tableEnd = lr + (long) w * n;
				}
				clearListing(bl, bl.getNewAddress(Math.max(tableEnd, bl.getOffset() + 4) - 1));
				mem.setBytes(bl, new byte[] { 0x00, 0x47, (byte) 0xC0, 0x46 }); // bx r0; nop
				new DisassembleCommand(new AddressSet(bl, bl.add(1)), null, true).applyTo(currentProgram, monitor);
				out.put(bl, targets);
				patchedSwitches.put(bl, targets);
				for (Address ta : targets)
					currentProgram.getReferenceManager().addMemoryReference(bl, ta, RefType.COMPUTED_JUMP, SourceType.USER_DEFINED, 0);
				patched = true;
				break; // bytes changed; walk again
			}
			if (!patched && !branched) break;
		}
		return out;
	}

	// True if a push {...} comes within the first 9 instructions at t with no branch, return, pop or
	// ldm/stm before it. Used only on bl targets inside walked code (not on data), where GCC may
	// schedule up to 8 setup instructions before the push (0x090DEA90). No label in
	// AIScript_Negatives/Positives passes this; labels never push again.
	private boolean pushBeforeFlow(Address t) throws Exception {
		Memory mem = currentProgram.getMemory();
		for (int i = 0; i < 9; i++) {
			int h = mem.getShort(t.add(2L * i)) & 0xFFFF;
			if ((h & 0xFE00) == 0xB400) return true;
			if ((h & 0xF000) == 0xD000 || (h & 0xF800) == 0xE000 || (h & 0xF800) == 0xF000 || (h & 0xF000) == 0xC000
				|| (h & 0xFF00) == 0x4700 || (h & 0xFE00) == 0xBC00 || ((h & 0xFF00) == 0x4600 && (h & 0x87) == 0x87))
				return false; // b<cond>, b, bl, ldm/stm, bx, pop, mov pc
		}
		return false;
	}

	// True if code at t reaches "bx lr" before any other return, following unconditional "b".
	// A long-branch target belongs to a function that saved lr and returns via pop, so this marks
	// a leaf function called with bl (e.g. 0x09074CC4 from 0x0906CFCE), not a label.
	private boolean returnsViaLr(Address t) throws Exception {
		Memory mem = currentProgram.getMemory();
		Address a = t;
		for (int i = 0; i < 256; i++) {
			int h = mem.getShort(a) & 0xFFFF;
			if (h == 0x4770) return true;                       // bx lr
			if ((h & 0xFF00) == 0xBD00 || (h & 0xFF87) == 0x4700) return false; // pop {..pc}, bx rN
			if ((h & 0xF800) == 0xE000) {                       // b label
				int off = h & 0x7FF;
				if ((off & 0x400) != 0) off -= 0x800;
				a = a.add(4 + 2L * off);
				continue;
			}
			if ((h & 0xF800) == 0xF000) a = a.add(2);           // bl: skip its second half
			a = a.add(2);
		}
		return false;
	}

	// Addresses of the instructions reachable from entry without following calls: fall-through,
	// branches (including bl overridden to a branch) and patched switch targets. Missing code is
	// disassembled on the way.
	private AddressSet walkFlow(Address entry) {
		Listing listing = currentProgram.getListing();
		AddressSet body = new AddressSet();
		Deque<Address> work = new ArrayDeque<>();
		work.add(entry);
		while (!work.isEmpty()) {
			Address a = work.poll();
			while (a != null && !body.contains(a)) {
				Instruction ins = listing.getInstructionAt(a);
				if (ins == null) {
					new DisassembleCommand(a, null, true).applyTo(currentProgram, monitor);
					ins = listing.getInstructionAt(a);
					if (ins == null) break;
				}
				body.add(new AddressSet(ins.getMinAddress(), ins.getMaxAddress()));
				if (!ins.getFlowType().isCall())
					for (Address t : ins.getFlows()) work.add(t);
				for (Reference r : ins.getReferencesFrom())
					if (r.getReferenceType() == RefType.COMPUTED_JUMP) work.add(r.getToAddress());
				a = ins.getFallThrough();
			}
		}
		return body;
	}

	// Case count from the bounds check "cmp rN, #K" before the helper call (K+1 entries).
	private int caseCount(Instruction bl) {
		Instruction p = bl.getPrevious();
		for (int i = 0; i < 8 && p != null; i++, p = p.getPrevious()) {
			if (p.getMnemonicString().equals("cmp") && p.getNumOperands() == 2) {
				Object[] o = p.getOpObjects(1);
				if (o.length == 1 && o[0] instanceof ghidra.program.model.scalar.Scalar)
					return (int) ((ghidra.program.model.scalar.Scalar) o[0]).getUnsignedValue() + 1;
			}
		}
		return 1;
	}

	// CFRU long calls: "ldr rN, =target; bl stub" where stub is "bx rN".
	// Add a call-override reference so the decompiler shows the real callee. rN is found by
	// tracking pc-relative loads forward along the function's control flow: the load can be far
	// before the call and kept in a saved register (FlagGet in r7, 0x090BD80C -> 0x090BD8AC), and
	// the nearest load by address can belong to another path (0x0909A39A vs the call at 0x0909A3AA).
	// Only an odd (Thumb) value counts; an even one is a data pointer.
	private static final java.util.regex.Pattern SP_SLOT = java.util.regex.Pattern.compile("\\[sp(?:,#(0x[0-9a-f]+))?\\]");

	private void fixLongCalls(Function f) throws Exception {
		Listing listing = currentProgram.getListing();
		ReferenceManager rm = currentProgram.getReferenceManager();
		Memory mem = currentProgram.getMemory();
		AddressSetView body = f.getBody();
		Set<Address> seen = new HashSet<>();
		Deque<Object[]> work = new ArrayDeque<>();
		work.add(new Object[] { f.getEntryPoint(), new HashMap<String, Long>() });
		while (!work.isEmpty()) {
			Object[] item = work.pop();
			Address a = (Address) item[0];
			@SuppressWarnings("unchecked")
			Map<String, Long> regs = (Map<String, Long>) item[1];
			while (a != null && body.contains(a) && seen.add(a)) {
				Instruction ins = listing.getInstructionAt(a);
				if (ins == null) break;
				String m = ins.getMnemonicString();
				if (m.equals("bl") && ins.getFlows().length > 0) {
					Address stub = ins.getFlows()[0];
					int hw = mem.getShort(stub) & 0xFFFF;
					if ((hw & 0xFF87) == 0x4700) { // bx rN
						Long value = regs.get("r" + ((hw >> 3) & 0xF));
						if (value != null && (value & 1) == 1 && value - 1 >= 0x08000000L && value - 1 < 0x0A000000L) {
							Address t = stub.getAddressSpace().getAddress(value - 1);
							if (getFunctionAt(t) == null) {
								new DisassembleCommand(t, null, true).applyTo(currentProgram, monitor);
								new CreateFunctionCmd(t).applyTo(currentProgram, monitor);
							}
							Reference r = rm.addMemoryReference(ins.getAddress(), t, RefType.CALL_OVERRIDE_UNCONDITIONAL, SourceType.USER_DEFINED, 0);
							rm.setPrimary(r, true);
						}
					}
				}
				if (ins.getFlowType().isCall())
					for (String r : new String[] { "r0", "r1", "r2", "r3", "r12" }) regs.remove(r);
				for (Object o : ins.getResultObjects())
					if (o instanceof Register) regs.remove(((Register) o).getName());
				String op1 = ins.getNumOperands() >= 2 ? ins.getDefaultOperandRepresentation(1) : "";
				String op0 = ins.getNumOperands() >= 1 ? ins.getDefaultOperandRepresentation(0) : "";
				java.util.regex.Matcher slot = SP_SLOT.matcher(op1);
				if (m.equals("ldr") && ins.getReferencesFrom().length > 0 && op1.startsWith("[0x")) {
					Address lit = ins.getReferencesFrom()[0].getToAddress();
					regs.put(op0, mem.getInt(lit) & 0xFFFFFFFFL);
				} else if (m.equals("ldr") && slot.matches() && regs.containsKey("sp+" + slot.group(1))) {
					regs.put(op0, regs.get("sp+" + slot.group(1))); // function pointer kept on the stack
				} else if (m.equals("str") && slot.matches()) {
					if (regs.containsKey(op0)) regs.put("sp+" + slot.group(1), regs.get(op0));
					else regs.remove("sp+" + slot.group(1));
				}
				if ((m.equals("add") || m.equals("sub")) && op0.equals("sp"))
					regs.keySet().removeIf(k -> k.startsWith("sp+"));
				if (!ins.getFlowType().isCall())
					for (Address t : ins.getFlows()) work.push(new Object[] { t, new HashMap<>(regs) });
				for (Reference r : ins.getReferencesFrom())
					if (r.getReferenceType() == RefType.COMPUTED_JUMP) work.push(new Object[] { r.getToAddress(), new HashMap<>(regs) });
				a = ins.getFallThrough();
			}
		}
	}
}
