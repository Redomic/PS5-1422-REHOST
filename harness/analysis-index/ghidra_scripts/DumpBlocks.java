// Dump memory blocks and program metadata
// @category PS5
import ghidra.app.script.GhidraScript;
import ghidra.program.model.mem.MemoryBlock;

public class DumpBlocks extends GhidraScript {
    @Override
    public void run() throws Exception {
        println("IMAGEBASE " + currentProgram.getImageBase());
        println("LANG      " + currentProgram.getLanguageID());
        println("COMPILER  " + currentProgram.getCompilerSpec().getCompilerSpecID());
        println("FMT       " + currentProgram.getExecutableFormat());
        for (MemoryBlock b : currentProgram.getMemory().getBlocks()) {
            println(String.format("BLOCK %-24s %s - %s size=%#x r=%b w=%b x=%b init=%b",
                b.getName(), b.getStart(), b.getEnd(), b.getSize(),
                b.isRead(), b.isWrite(), b.isExecute(), b.isInitialized()));
        }
    }
}
