// Disassemble Thumb code at given addresses and print instructions until the function ends.
// Args: <outFile> <addrHex>...
import ghidra.app.script.GhidraScript;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.program.model.address.*;
import ghidra.program.model.lang.Register;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.Reference;
import java.io.*;
import java.math.BigInteger;

public class DumpAsm extends GhidraScript {
	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		AddressSpace space = currentProgram.getAddressFactory().getDefaultAddressSpace();
		Address romStart = space.getAddress(0x08000000L);
		Address romEnd = space.getAddress(0x08000000L + currentProgram.getMemory().getBlock(romStart).getSize() - 1);
		currentProgram.getProgramContext().setValue(currentProgram.getRegister("TMode"), romStart, romEnd, BigInteger.ONE);
		try (PrintWriter pw = new PrintWriter(new FileWriter(args[0]))) {
			for (int i = 1; i < args.length; i++) {
				Address a = space.getAddress(Long.parseLong(args[i], 16) & ~1L);
				new DisassembleCommand(a, null, true).applyTo(currentProgram, monitor);
				new CreateFunctionCmd(a).applyTo(currentProgram, monitor);
				Function f = getFunctionAt(a);
				pw.println("== " + a);
				InstructionIterator it = currentProgram.getListing().getInstructions(f != null ? f.getBody() : new AddressSet(a, a.add(0x200)), true);
				while (it.hasNext()) {
					Instruction ins = it.next();
					StringBuilder sb = new StringBuilder(ins.getAddress() + "  " + ins);
					for (Reference r : ins.getReferencesFrom()) {
						Address t = r.getToAddress();
						if (r.getReferenceType().isData() && currentProgram.getMemory().contains(t))
							sb.append(String.format("   ; [%s]=%08X", t, currentProgram.getMemory().getInt(t)));
					}
					pw.println(sb);
				}
			}
		}
	}
}
