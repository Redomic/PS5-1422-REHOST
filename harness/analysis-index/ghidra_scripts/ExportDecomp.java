// Resumable decompilation pass: writes decomp/<addr>.c + appends decomp.jsonl.
// Args: outDir [timeoutSecsPerFunc=90] [maxTotalSecs=0] [minSize=32]
// @category PS5
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.util.HashSet;
import java.util.Set;

public class ExportDecomp extends GhidraScript {

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

    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        String outDir = (a.length > 0) ? a[0] : "/tmp/opencode/idx";
        int perFuncTimeout = (a.length > 1) ? Integer.parseInt(a[1]) : 90;
        long maxTotalSecs  = (a.length > 2) ? Long.parseLong(a[2]) : 0;
        long minSize       = (a.length > 3) ? Long.parseLong(a[3]) : 32;

        File ddir = new File(outDir, "decomp");
        ddir.mkdirs();
        File jsonl = new File(outDir, "decomp.jsonl");

        // resume set
        Set<String> done = new HashSet<>();
        if (jsonl.exists()) {
            BufferedReader br = new BufferedReader(new InputStreamReader(
                new FileInputStream(jsonl), "UTF-8"));
            String line;
            while ((line = br.readLine()) != null) {
                int i = line.indexOf("\"a\":\"");
                if (i >= 0) {
                    int j = line.indexOf('"', i + 5);
                    if (j > 0) done.add(line.substring(i + 5, j));
                }
            }
            br.close();
        }
        println("RESUME skip " + done.size() + " already-decompiled");

        DecompInterface di = new DecompInterface();
        // default decompiler options are adequate
        di.toggleCCode(true);
        di.toggleSyntaxTree(false);
        di.setSimplificationStyle("decompile");
        if (!di.openProgram(currentProgram)) {
            println("ERROR decompiler openProgram failed");
            return;
        }

        BufferedWriter w = new BufferedWriter(new OutputStreamWriter(
            new FileOutputStream(jsonl, true), "UTF-8"), 1 << 20);
        long t0 = System.currentTimeMillis();
        int n = 0, skipped = 0, failed = 0;

        FunctionIterator fit = currentProgram.getFunctionManager().getFunctions(true);
        while (fit.hasNext()) {
            if (monitor.isCancelled()) break;
            Function f = fit.next();
            long sz = f.getBody().getNumAddresses();
            if (sz < minSize) { skipped++; continue; }
            String addr = f.getEntryPoint().toString();
            if (done.contains(addr)) { skipped++; continue; }

            long ft0 = System.currentTimeMillis();
            String c = null, sig = null, err = null;
            try {
                DecompileResults res = di.decompileFunction(f, perFuncTimeout, monitor);
                if (res != null && res.decompileCompleted() && res.getDecompiledFunction() != null) {
                    c = res.getDecompiledFunction().getC();
                    sig = res.getDecompiledFunction().getSignature();
                } else {
                    err = (res == null) ? "null-results"
                        : (res.getErrorMessage() == null ? "incomplete" : res.getErrorMessage());
                }
            } catch (Exception e) {
                err = "exception: " + e.getClass().getSimpleName() + ": " + e.getMessage();
            }
            long ms = System.currentTimeMillis() - ft0;

            if (c != null) {
                try (BufferedWriter cw = new BufferedWriter(new OutputStreamWriter(
                        new FileOutputStream(new File(ddir, addr + ".c")), "UTF-8"))) {
                    cw.write(c);
                }
            } else {
                failed++;
            }
            StringBuilder sb = new StringBuilder(200);
            sb.append("{\"a\":\"").append(addr).append('"');
            sb.append(",\"size\":").append(sz);
            sb.append(",\"ms\":").append(ms);
            sb.append(",\"sig\":").append(sig == null ? "null" : "\"" + esc(sig) + "\"");
            sb.append(",\"err\":").append(err == null ? "null" : "\"" + esc(err) + "\"");
            sb.append(",\"clen\":").append(c == null ? 0 : c.length());
            sb.append('}').append('\n');
            w.write(sb.toString());
            n++;
            if ((n % 500) == 0) {
                w.flush();
                println("decompiled " + n + " failed " + failed + " elapsed "
                        + ((System.currentTimeMillis() - t0) / 1000) + "s");
            }
            if (maxTotalSecs > 0 && ((System.currentTimeMillis() - t0) / 1000) > maxTotalSecs) {
                println("BUDGET-EXHAUSTED after " + n + " functions, next addr " + addr);
                break;
            }
        }
        w.flush();
        w.close();
        di.dispose();
        println("DONE decompiled=" + n + " failed=" + failed + " skipped=" + skipped
                + " elapsed=" + ((System.currentTimeMillis() - t0) / 1000) + "s");
    }
}
