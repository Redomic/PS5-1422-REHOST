// Export function metadata, all references, and defined strings to JSONL/TSV.
// Fast pass: no decompilation. Run with -process -noanalysis -postScript.
// @category PS5
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Data;
import ghidra.program.model.data.DataType;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.symbol.RefType;
import ghidra.program.model.symbol.Reference;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class ExportMeta extends GhidraScript {

    static String esc(String s) {
        StringBuilder b = new StringBuilder(s.length() + 16);
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"':  b.append("\\\""); break;
                case '\\': b.append("\\\\"); break;
                case '\n': b.append("\\n"); break;
                case '\r': b.append("\\r"); break;
                case '\t': b.append("\\t"); break;
                default:
                    if (c < 0x20 || c > 0x7e) b.append(String.format("\\u%04x", (int) c));
                    else b.append(c);
            }
        }
        return b.toString();
    }

    /** coarse class: call | jump | data-read | data-write | data-address | other */
    static String classify(RefType rt) {
        if (rt == null) return "other";
        if (rt.isCall()) return "call";
        if (rt.isJump()) return "jump";
        if (rt.isWrite()) return "data-write";
        if (rt.isRead()) return "data-read";
        if (rt.isData()) return "data-address";
        return "other";
    }

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        String outDir = (args.length > 0) ? args[0] : "/tmp/opencode/idx";
        new File(outDir).mkdirs();

        long t0 = System.currentTimeMillis();

        // ---- functions ----
        BufferedWriter fw = new BufferedWriter(new OutputStreamWriter(
            new FileOutputStream(new File(outDir, "functions_meta.jsonl")), "UTF-8"));
        int nFuncs = 0;
        FunctionIterator fit = currentProgram.getFunctionManager().getFunctions(true);
        while (fit.hasNext()) {
            Function f = fit.next();
            StringBuilder sb = new StringBuilder(320);
            sb.append("{\"addr\":\"").append(f.getEntryPoint()).append('"');
            sb.append(",\"name\":\"").append(esc(f.getName())).append('"');
            sb.append(",\"size\":").append(f.getBody().getNumAddresses());
            sb.append(",\"sig\":\"").append(esc(f.getPrototypeString(false, false))).append('"');
            sb.append(",\"ret\":\"").append(esc(f.getReturnType().getName())).append('"');
            sb.append(",\"nparams\":").append(f.getParameterCount());
            sb.append(",\"thunk\":").append(f.isThunk());
            sb.append(",\"noreturn\":").append(f.hasNoReturn());
            sb.append('}').append('\n');
            fw.write(sb.toString());
            nFuncs++;
            if ((nFuncs % 20000) == 0) println("functions " + nFuncs);
        }
        fw.close();
        println("FUNCS " + nFuncs + " in " + (System.currentTimeMillis() - t0) + "ms");

        // ---- references (every instruction, every outgoing ref) ----
        // xrefs.tsv sorted later by python; here keep discovery order.
        BufferedWriter xw = new BufferedWriter(new OutputStreamWriter(
            new FileOutputStream(new File(outDir, "xrefs.tsv")), "UTF-8"), 1 << 20);
        int nRefs = 0, nIns = 0;
        long t1 = System.currentTimeMillis();
        InstructionIterator ii = currentProgram.getListing().getInstructions(true);
        while (ii.hasNext()) {
            Instruction ins = ii.next();
            nIns++;
            Reference[] refs = ins.getReferencesFrom();
            if (refs == null) continue;
            for (Reference r : refs) {
                RefType rt = r.getReferenceType();
                if (rt == null) continue;
                if (rt.isFlow() && !rt.isJump() && !rt.isCall()) continue; // drop fallthrough
                String cls = classify(rt);
                boolean ind = rt.isIndirect();
                String kind = ind ? ("indirect-" + cls) : cls;
                xw.write(r.getFromAddress().toString());
                xw.write('\t');
                xw.write(r.getToAddress().toString());
                xw.write('\t');
                xw.write(kind);
                xw.write('\t');
                xw.write(rt.getName());
                xw.write('\n');
                nRefs++;
            }
            if ((nIns % 1000000) == 0) println("instructions " + nIns + " refs " + nRefs);
            if (monitor.isCancelled()) break;
        }
        xw.close();
        println("REFS " + nRefs + " from " + nIns + " instructions in "
                + (System.currentTimeMillis() - t1) + "ms");

        // ---- strings ----
        BufferedWriter sw = new BufferedWriter(new OutputStreamWriter(
            new FileOutputStream(new File(outDir, "strings.jsonl")), "UTF-8"));
        int nStr = 0;
        DataIterator dit = currentProgram.getListing().getDefinedData(true);
        while (dit.hasNext()) {
            Data d = dit.next();
            DataType dt = d.getDataType();
            if (dt == null) continue;
            String tn = dt.getName().toLowerCase();
            if (!tn.contains("string") && !tn.contains("unicode")) continue;
            Object v = d.getValue();
            if (!(v instanceof String)) continue;
            String s = ((String) v);
            int end = s.length();
            while (end > 0 && s.charAt(end - 1) == '\0') end--;
            s = s.substring(0, end);
            if (s.length() < 4) continue;
            if (s.length() > 4000) s = s.substring(0, 4000);
            Function owner = getFunctionContaining(d.getAddress());
            StringBuilder sb = new StringBuilder(160);
            sb.append("{\"addr\":\"").append(d.getAddress()).append('"');
            sb.append(",\"len\":").append(d.getLength());
            sb.append(",\"type\":\"").append(esc(dt.getName())).append('"');
            sb.append(",\"func\":").append(owner == null ? "null"
                    : "\"" + owner.getEntryPoint() + "\"");
            sb.append(",\"s\":\"").append(esc(s)).append('"');
            sb.append('}').append('\n');
            sw.write(sb.toString());
            nStr++;
        }
        sw.close();
        println("STRINGS " + nStr);
        println("DONE total " + (System.currentTimeMillis() - t0) + "ms");
    }
}
