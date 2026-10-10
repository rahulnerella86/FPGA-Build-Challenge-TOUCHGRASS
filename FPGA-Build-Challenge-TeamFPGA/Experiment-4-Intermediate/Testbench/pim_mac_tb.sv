// ============================================================================
// pim_mac_tb.sv - self-checking testbench for pim_mac_bram (Phase-B RTL).
// ----------------------------------------------------------------------------
// INDEPENDENT reference: ref_row() recomputes the dot product from the TB's
// own W[][]/A[] shadow arrays (no shared code with the DUT). The DUT is also
// cross-checked against model/pim_model.py golden vectors when present
// (tb/vectors/*.hex); the file check is OPTIONAL - core phases are
// self-contained so the sim passes with or without a prior python run.
//
//  P1 KNOWN-ANSWER: fixed 4x8 pattern, row0 hard-coded to 92 and row1 to 60
//     (hand-computed below) + full-row ref_row() match. Catches sign/extend,
//     row-major addressing, and accumulation bugs.
//  P2 RANDOM: 30 seeds, $urandom weights/activations, per-row ref match.
//     Catches data-dependent sequencing bugs the fixed pattern misses.
//  P3 CORNERS: zeros / all+127 / all-128 / -128x+127. Catches sign traps
//     ((-128)*(-128) must be +16384, not 0 or -16384) and wrap semantics.
//  P4 RESET MID-COMPUTE: assert rst_n during COMPUTE, require busy/done to
//     clear, then prove the engine recovers and produces correct results.
//  P5 BACK-TO-BACK + READ PORT: two runs without reset (result update), plus
//     r_rd_valid 1-cycle latency protocol check; start-during-busy is ignored.
// PASS: "*** ALL CHECKS PASSED (tb_pim_mac) ***".
// ============================================================================
`timescale 1ns/1ps
module tb_pim_mac;
    localparam int ROWS = 4;
    localparam int COLS = 8;
    localparam int DW   = 8;
    localparam int AW   = 32;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk; // 100 MHz

    logic w_wr_en, a_wr_en, start, busy, done, r_rd_en, r_rd_valid;
    logic [$clog2(ROWS*COLS)-1:0] w_wr_addr;
    logic [DW-1:0]                w_wr_data;
    logic [$clog2(COLS)-1:0]      a_wr_addr;
    logic [DW-1:0]                a_wr_data;
    logic [$clog2(ROWS)-1:0]      r_rd_addr;
    logic [AW-1:0]                r_rd_data;

    int errors = 0;

    pim_mac_bram #(.NUM_ROWS(ROWS), .NUM_COLS(COLS)) dut (
        .clk, .rst_n,
        .w_wr_en, .w_wr_addr, .w_wr_data,
        .a_wr_en, .a_wr_addr, .a_wr_data,
        .start, .busy, .done,
        .r_rd_en, .r_rd_addr, .r_rd_data, .r_rd_valid
    );

    // ---- TB shadow model (independent of DUT) ----
    logic signed [DW-1:0] W [0:ROWS-1][0:COLS-1];
    logic signed [DW-1:0] A [0:COLS-1];

    function automatic signed [AW-1:0] ref_row(input int r);
        reg signed [AW-1:0] acc;
        acc = 0;
        for (int c = 0; c < COLS; c = c + 1)
            acc = acc + W[r][c] * A[c];
        return acc;
    endfunction

    task automatic load_all;
        for (int r = 0; r < ROWS; r = r + 1)
            for (int c = 0; c < COLS; c = c + 1) begin
                w_wr_en = 1; w_wr_addr = r*COLS+c; w_wr_data = W[r][c];
                @(posedge clk);
            end
        w_wr_en = 0;
        for (int c = 0; c < COLS; c = c + 1) begin
            a_wr_en = 1; a_wr_addr = c; a_wr_data = A[c];
            @(posedge clk);
        end
        a_wr_en = 0;
        @(posedge clk);
    endtask

    task automatic run_compute(input int timeout_cyc = 1000);
        int n;
        n = 0;
        start = 1; @(posedge clk); start = 0;
        // RACE FIX: done is combinational on state and still reads 1 (old DONE)
        // in the active region of the start edge (NBA has not applied yet).
        // Without this cycle the while() below exits immediately on stale done
        // and the TB reads the PREVIOUS run's results (found via DUT rowwr
        // timestamps lagging the TB check by exactly one run).
        @(posedge clk);
        while (!done && n < timeout_cyc) begin @(posedge clk); n = n + 1; end
        if (!done) begin $error("TIMEOUT waiting for done"); errors = errors + 1; end
    endtask

    task automatic check_all(input string tag);
        reg signed [AW-1:0] exp;
        reg [AW-1:0] got;
        for (int r = 0; r < ROWS; r = r + 1) begin
            exp = ref_row(r);
            r_rd_en = 1; r_rd_addr = r; @(posedge clk); r_rd_en = 0;
            @(posedge clk);
            if (!r_rd_valid) begin $error("[%0s] row %0d: rd_valid low", tag, r); errors = errors + 1; end
            got = r_rd_data;
            if (got !== exp) begin
                $error("[%0s] row %0d mismatch: got 0x%08h exp 0x%08h", tag, r, got, exp);
                errors = errors + 1;
            end
        end
        $display("[%0s] rows checked vs ref", tag);
    endtask

    initial begin
        $display("== tb_pim_mac start (ROWS=%0d COLS=%0d) ==", ROWS, COLS);
        w_wr_en = 0; a_wr_en = 0; start = 0; r_rd_en = 0;
        rst_n = 0; repeat(3) @(posedge clk); rst_n = 1; repeat(2) @(posedge clk);

        // ---------- P1: known-answer pattern ----------
        // W[r][c] = r*COLS+c-16 -> row0 = -16..-9, row1 = -8..-1, ...
        // A[c] = c-4 -> -4..3.
        // Row0: 64+45+28+13+0-11-20-27 = 92 (hand-computed).
        // Row1: 32+21+12+5+0-3-4-3 = 60 (hand-computed).
        $display("[P1] known-answer pattern");
        for (int r = 0; r < ROWS; r = r + 1)
            for (int c = 0; c < COLS; c = c + 1)
                W[r][c] = r*COLS+c-16;
        for (int c = 0; c < COLS; c = c + 1) A[c] = c-4;
        load_all; run_compute;
        begin
            reg signed [AW-1:0] e0, e1;
            e0 = ref_row(0); e1 = ref_row(1);
            if (e0 !== 92)  begin $error("[P1] TB ref row0=%0d, want 92 (pattern changed?)", e0); errors = errors + 1; end
            if (e1 !== 60)  begin $error("[P1] TB ref row1=%0d, want 60 (pattern changed?)", e1); errors = errors + 1; end
        end
        check_all("P1");

        // ---------- P2: random ----------
        $display("[P2] random x30");
        for (int it = 0; it < 30; it = it + 1) begin
            for (int r = 0; r < ROWS; r = r + 1)
                for (int c = 0; c < COLS; c = c + 1)
                    W[r][c] = ($urandom % 256)-128;
            for (int c = 0; c < COLS; c = c + 1) A[c] = ($urandom % 256)-128;
            load_all; run_compute;
            check_all($sformatf("P2/it%0d", it));
        end

        // ---------- P3: corners ----------
        $display("[P3] corners");
        for (int r = 0; r < ROWS; r = r + 1)
            for (int c = 0; c < COLS; c = c + 1) W[r][c] = 0;
        for (int c = 0; c < COLS; c = c + 1) A[c] = 0;
        load_all; run_compute; check_all("P3/zeros");

        for (int r = 0; r < ROWS; r = r + 1)
            for (int c = 0; c < COLS; c = c + 1) W[r][c] = 127;
        for (int c = 0; c < COLS; c = c + 1) A[c] = 127;
        load_all; run_compute; check_all("P3/max");
        if (ref_row(0) !== COLS*127*127) begin
            $error("[P3] max math: %0d != %0d", ref_row(0), COLS*127*127); errors = errors + 1;
        end

        for (int r = 0; r < ROWS; r = r + 1)
            for (int c = 0; c < COLS; c = c + 1) W[r][c] = -128;
        for (int c = 0; c < COLS; c = c + 1) A[c] = -128;
        load_all; run_compute; check_all("P3/min");
        if (ref_row(0) !== COLS*16384) begin
            $error("[P3] (-128)(-128) math: %0d != %0d", ref_row(0), COLS*16384); errors = errors + 1;
        end

        for (int r = 0; r < ROWS; r = r + 1)
            for (int c = 0; c < COLS; c = c + 1) W[r][c] = -128;
        for (int c = 0; c < COLS; c = c + 1) A[c] = 127;
        load_all; run_compute; check_all("P3/minmax");

        // ---------- P4: reset mid-compute ----------
        $display("[P4] reset mid-compute");
        for (int r = 0; r < ROWS; r = r + 1)
            for (int c = 0; c < COLS; c = c + 1) W[r][c] = ($urandom % 256)-128;
        for (int c = 0; c < COLS; c = c + 1) A[c] = ($urandom % 256)-128;
        load_all;
        start = 1; @(posedge clk); start = 0;
        repeat(5) @(posedge clk);
        rst_n = 0; repeat(2) @(posedge clk);
        if (busy !== 0) begin $error("[P4] busy not low under reset"); errors = errors + 1; end
        if (done !== 0) begin $error("[P4] done not low under reset"); errors = errors + 1; end
        rst_n = 1; repeat(2) @(posedge clk);
        load_all; run_compute; check_all("P4/recover");

        // ---------- P5: back-to-back + read protocol ----------
        $display("[P5] back-to-back + read protocol");
        for (int c = 0; c < COLS; c = c + 1) A[c] = c+1;
        for (int r = 0; r < ROWS; r = r + 1)
            for (int c = 0; c < COLS; c = c + 1) W[r][c] = r+1;
        load_all; run_compute; check_all("P5/run1");
        // second run, no reset: results must update
        for (int r = 0; r < ROWS; r = r + 1)
            for (int c = 0; c < COLS; c = c + 1) W[r][c] = -(r+1);
        load_all; run_compute; check_all("P5/run2");
        // start-during-busy must be ignored (no hang, first run completes)
        load_all;
        start = 1; @(posedge clk); start = 0;
        @(posedge clk); start = 1; @(posedge clk); start = 0; // stray start in COMPUTE
        begin
            int n;
            n = 0;
            while (!done && n < 1000) begin @(posedge clk); n = n + 1; end
            if (!done) begin $error("[P5] hang after stray start"); errors = errors + 1; end
        end
        check_all("P5/stray");

        // ---------- P6 (optional): python golden vectors ----------
        begin
            integer fw, fa, fg, n;
            fw = $fopen("tb/vectors/weights.hex", "r");
            if (!fw) fw = $fopen("../tb/vectors/weights.hex", "r");
            fa = $fopen("tb/vectors/act.hex", "r");
            if (!fa) fa = $fopen("../tb/vectors/act.hex", "r");
            fg = $fopen("tb/vectors/golden.hex", "r");
            if (!fg) fg = $fopen("../tb/vectors/golden.hex", "r");
            if (fw && fa && fg) begin
                integer tmp; reg [AW-1:0] gexp;
                $display("[P6] python golden vectors present - checking");
                for (int r = 0; r < ROWS; r = r + 1)
                    for (int c = 0; c < COLS; c = c + 1) begin
                        n = $fscanf(fw, "%h\n", tmp);
                        W[r][c] = tmp[7:0];
                    end
                for (int c = 0; c < COLS; c = c + 1) begin
                    n = $fscanf(fa, "%h\n", tmp); A[c] = tmp[7:0];
                end
                load_all; run_compute;
                for (int r = 0; r < ROWS; r = r + 1) begin
                    n = $fscanf(fg, "%h\n", gexp);
                    r_rd_en = 1; r_rd_addr = r; @(posedge clk); r_rd_en = 0;
                    @(posedge clk);
                    if (r_rd_data !== gexp) begin
                        $error("[P6] row %0d: DUT 0x%08h != golden 0x%08h", r, r_rd_data, gexp);
                        errors = errors + 1;
                    end
                    if (ref_row(r) !== $signed(gexp)) begin
                        $error("[P6] row %0d: TB ref != golden (model skew)", r); errors = errors + 1;
                    end
                end
                $display("[P6] golden cross-check done");
            end else begin
                $display("[P6] skipped (no tb/vectors/*.hex - run python model/pim_model.py)");
            end
            if (fw) $fclose(fw);
            if (fa) $fclose(fa);
            if (fg) $fclose(fg);
        end

        if (errors == 0) $display("*** ALL CHECKS PASSED (tb_pim_mac) ***");
        else begin $display("*** FAILURES: %0d ***", errors); $fatal(1); end
        $finish;
    end

    // watchdog
    initial begin
        repeat(200000) @(posedge clk);
        $error("WATCHDOG timeout"); $fatal(1);
    end
endmodule
