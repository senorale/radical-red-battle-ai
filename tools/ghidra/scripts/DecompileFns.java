// Decompile Thumb functions in a GBA ROM by address, labeling known symbols first.
// Args: <symbols.txt> <outDir> <depth> <addrHex>...
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
		int depth = Integer.parseInt(args[2]);
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

		DecompInterface di = new DecompInterface();
		di.openProgram(currentProgram);
		Set<Address> done = new HashSet<>();
		Deque<Object[]> queue = new ArrayDeque<>();
		for (int i = 3; i < args.length; i++)
			queue.add(new Object[] { space.getAddress(Long.parseLong(args[i], 16) & ~1L), 0 });

		while (!queue.isEmpty()) {
			Object[] item = queue.poll();
			Address a = (Address) item[0];
			int d = (Integer) item[1];
			if (!done.add(a)) continue;
			if (a.getOffset() < 0x08000000L) continue;
			Map<Address, List<Address>> switches = fixSwitches(a);
			Function f = getFunctionAt(a);
			if (f == null) {
				new CreateFunctionCmd(a).applyTo(currentProgram, monitor);
				f = getFunctionAt(a);
			}
			if (f == null) { println("NOFUNC " + a); continue; }
			if (!switches.isEmpty())
				CreateFunctionCmd.fixupFunctionBody(currentProgram, f, monitor);
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
			println("OK " + a + " " + f.getName());
			if (d < depth) {
				InstructionIterator ii = currentProgram.getListing().getInstructions(f.getBody(), true);
				while (ii.hasNext()) {
					for (Reference ref : ii.next().getReferencesFrom()) {
						Address t = ref.getToAddress();
						if (ref.getReferenceType().isCall() && t.getOffset() >= 0x09000000L && t.getOffset() < 0x0A000000L
							&& (currentProgram.getMemory().getShort(t) & 0xFF87) != 0x4700)
							queue.add(new Object[] { t, d + 1 });
					}
				}
			}
		}
		di.dispose();
	}

	// libgcc Thumb switch helpers (__gnu_thumb1_case_*): uqi, uhi, sqi, shi, si.
	private static final long[] CASE_HELPERS = { 0x090003C4L, 0x090003D6L, 0x090003EAL, 0x090003FCL, 0x09000410L };

	// Replace each "bl case_helper" + inline table with "bx r0; nop" in the in-memory program,
	// disassemble every case target, and return bx address -> case targets for jump-table overrides.
	private Map<Address, List<Address>> fixSwitches(Address entry) throws Exception {
		Map<Address, List<Address>> out = new LinkedHashMap<>();
		Listing listing = currentProgram.getListing();
		Memory mem = currentProgram.getMemory();
		AddressSet seen = new AddressSet();
		Deque<Address> starts = new ArrayDeque<>();
		starts.add(entry);
		for (int iter = 0; iter < 400 && !starts.isEmpty(); iter++) {
			Address s = starts.poll();
			DisassembleCommand cmd = new DisassembleCommand(s, null, true);
			cmd.applyTo(currentProgram, monitor);
			seen.add(cmd.getDisassembledAddressSet());
			seen.add(s);
			// Long branches: "bl X" where X is inside this function and not a prologue -> plain branch.
			InstructionIterator bit = listing.getInstructions(cmd.getDisassembledAddressSet(), true);
			while (bit.hasNext()) {
				Instruction ins = bit.next();
				if (!ins.getMnemonicString().equals("bl") || ins.getFlows().length == 0) continue;
				Address t = ins.getFlows()[0];
				long d = t.getOffset() - entry.getOffset();
				int hw = mem.getShort(t) & 0xFFFF;
				boolean prologue = (hw & 0xFE00) == 0xB400; // push {...}
				boolean stub = (hw & 0xFF87) == 0x4700;    // bx rN
				boolean helper = false;
				for (long h : CASE_HELPERS) if (h == t.getOffset()) helper = true;
				if (d > 0 && d < 0x8000 && !prologue && !stub && !helper && getFunctionAt(t) == null) {
					ins.setFlowOverride(ghidra.program.model.listing.FlowOverride.BRANCH);
					if (listing.getInstructionAt(t) == null) starts.add(t);
				}
			}
			boolean patched = true;
			while (patched) {
				patched = false;
				InstructionIterator it = listing.getInstructions(seen, true);
				while (it.hasNext()) {
					Instruction ins = it.next();
					if (!ins.getMnemonicString().equals("bl") || ins.getFlows().length == 0) continue;
					long t = ins.getFlows()[0].getOffset();
					int kind = -1;
					for (int k = 0; k < CASE_HELPERS.length; k++) if (CASE_HELPERS[k] == t) kind = k;
					if (kind < 0) continue;
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
					seen.add(new AddressSet(bl, bl.add(3)));
					out.put(bl, targets);
					for (Address ta : targets)
						currentProgram.getReferenceManager().addMemoryReference(bl, ta, RefType.COMPUTED_JUMP, SourceType.USER_DEFINED, 0);
					for (Address ta : new LinkedHashSet<>(targets)) starts.add(ta);
					patched = true;
					break;
				}
			}
		}
		return out;
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
	// Add a call-override reference so the decompiler shows the real callee.
	private void fixLongCalls(Function f) throws Exception {
		Listing listing = currentProgram.getListing();
		ReferenceManager rm = currentProgram.getReferenceManager();
		Memory mem = currentProgram.getMemory();
		InstructionIterator it = listing.getInstructions(f.getBody(), true);
		List<Instruction> insns = new ArrayList<>();
		while (it.hasNext()) insns.add(it.next());
		for (int i = 0; i < insns.size(); i++) {
			Instruction ins = insns.get(i);
			if (!ins.getMnemonicString().equals("bl")) continue;
			Address stub = ins.getFlows().length > 0 ? ins.getFlows()[0] : null;
			if (stub == null) continue;
			int hw = mem.getShort(stub) & 0xFFFF;
			if ((hw & 0xFF87) != 0x4700) continue; // bx rN
			int reg = (hw >> 3) & 0xF;
			String regName = "r" + reg;
			for (int j = i - 1; j >= 0 && j >= i - 24; j--) {
				Instruction p = insns.get(j);
				if (p.getMnemonicString().equals("ldr") && p.getNumOperands() >= 2
					&& p.getDefaultOperandRepresentation(0).equals(regName)) {
					Reference[] refs = p.getReferencesFrom();
					if (refs.length == 0) break;
					long target = mem.getInt(refs[0].getToAddress()) & 0xFFFFFFFFL & ~1L;
					if (target < 0x08000000L || target >= 0x0A000000L) break;
					Address t = stub.getAddressSpace().getAddress(target);
					if (getFunctionAt(t) == null) {
						new DisassembleCommand(t, null, true).applyTo(currentProgram, monitor);
						new CreateFunctionCmd(t).applyTo(currentProgram, monitor);
					}
					Reference r = rm.addMemoryReference(ins.getAddress(), t, RefType.CALL_OVERRIDE_UNCONDITIONAL, SourceType.USER_DEFINED, 0);
					rm.setPrimary(r, true);
					break;
				}
			}
		}
	}
}
