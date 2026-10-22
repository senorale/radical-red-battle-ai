// Linear-sweep disassemble a Thumb range and print every instruction.
// Args: <outFile> <startHex> <endHex>
import ghidra.app.script.GhidraScript;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.Reference;
import java.io.*;
import java.math.BigInteger;

public class SweepAsm extends GhidraScript {
	@Override
	public void run() throws Exception {
		String[] a = getScriptArgs();
		AddressSpace sp = currentProgram.getAddressFactory().getDefaultAddressSpace();
		Address romStart = sp.getAddress(0x08000000L);
		Address romEnd = sp.getAddress(0x08000000L + currentProgram.getMemory().getBlock(romStart).getSize() - 1);
		currentProgram.getProgramContext().setValue(currentProgram.getRegister("TMode"), romStart, romEnd, BigInteger.ONE);
		Address start = sp.getAddress(Long.parseLong(a[1], 16)), end = sp.getAddress(Long.parseLong(a[2], 16));
		Listing l = currentProgram.getListing();
		Address cur = start;
		while (cur.compareTo(end) < 0) {
			if (l.getInstructionAt(cur) == null)
				new DisassembleCommand(cur, new AddressSet(cur, end), true).applyTo(currentProgram, monitor);
			Instruction ins = l.getInstructionAt(cur);
			cur = (ins != null) ? ins.getMaxAddress().add(1) : cur.add(2);
		}
		try (PrintWriter pw = new PrintWriter(new FileWriter(a[0]))) {
			InstructionIterator it = l.getInstructions(new AddressSet(start, end), true);
			while (it.hasNext()) {
				Instruction ins = it.next();
				StringBuilder sb = new StringBuilder(ins.getAddress() + "  " + ins);
				for (Reference r : ins.getReferencesFrom())
					if (r.getReferenceType().isData() && currentProgram.getMemory().contains(r.getToAddress()))
						sb.append(String.format("   ; [%s]=%08X", r.getToAddress(), currentProgram.getMemory().getInt(r.getToAddress())));
				pw.println(sb);
			}
		}
	}
}
