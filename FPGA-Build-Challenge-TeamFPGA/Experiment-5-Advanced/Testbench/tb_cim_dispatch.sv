// ============================================================================
// tb_cim_dispatch.sv - dispatch/wiring layer test (plumbing AND math path).
// ----------------------------------------------------------------------------
// The CiM MATH underneath is project 04's engine (inherited confidence:
// simulated-then-paused, NOT hardware-validated - see 04 README). What THIS
// bench proves is the DISPATCH layer around it, which is fully verified:
//  T1 loader write/readback through the MMIO window (addrs + data landing)
//  T2 full launch->busy->done->RESULT with golden 272 (row 2: 1..16 x all-2)
//  T3 overlapping launch while busy is ignored + sticky dropped=1; result
//     intact; relaunch clears the flag
//  T4 row-select clamp: rs1=31 on a 16-row engine reads row 15 (golden 32)
//  T5 loader writes arriving mid-run are ignored (result still 272)
//  T6 reset mid-run returns to idle STATUS=0, dropped=0
// Golden dots are recomputed by an independent in-TB loop (no shared code
// with the DUT or project 04). Old-ModelSim-safe syntax throughout.
// PASS: "*** ALL CHECKS PASSED (tb_cim_dispatch) ***".
// ============================================================================
`timescale 1ns/1ps
module tb_cim_dispatch;
    localparam int ROWS = 16;
    localparam int COLS = 16;

    logic clk;
    logic rst_n;
    logic [31:0] bus_addr, bus_wdata, bus_rdata;
    logic bus_write, bus_read;
    logic cim_valid;
    logic [4:0] cim_rs1;

    int errors;

    cim_dispatch #(.NUM_ROWS(ROWS), .NUM_COLS(COLS)) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .bus_addr  (bus_addr),
        .bus_wdata (bus_wdata),
        .bus_rdata (bus_rdata),
        .bus_write (bus_write),
        .bus_read  (bus_read),
        .cim_valid (cim_valid),
        .cim_rs1   (cim_rs1)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ---- independent golden: dot of TB-side arrays ----
    logic signed [7:0] TW [0:ROWS-1][0:COLS-1];
    logic signed [7:0] TA [0:COLS-1];
    function automatic signed [31:0] ref_dot(input int r);
        reg signed [31:0] acc;
        acc = 0;
        for (int c = 0; c < COLS; c = c + 1)
            acc = acc + TW[r][c] * TA[c];
        return acc;
    endfunction

    task automatic bus_w(input [31:0] addr, input [31:0] val);
        bus_addr = addr; bus_wdata = val;
        bus_write = 1; bus_read = 0;
        @(posedge clk); #1;
        bus_write = 0;
    endtask

    task automatic bus_r(input [31:0] addr, output [31:0] val);
        bus_addr = addr;
        bus_write = 0; bus_read = 1;
        #1;
        val = bus_rdata;
        bus_read = 0;
    endtask

    task automatic load_row(input int r);
        int c;
        for (c = 0; c < COLS; c = c + 1) begin
            bus_w(32'h2000_0000, r*COLS+c);          // WADDR
            bus_w(32'h2000_0004, TW[r][c] & 8'hFF);  // WDATA (low byte)
        end
    endtask

    task automatic load_act;
        int c;
        for (c = 0; c < COLS; c = c + 1) begin
            bus_w(32'h2000_0008, c);                // AADDR
            bus_w(32'h2000_000C, TA[c] & 8'hFF);    // ADATA
        end
    endtask

    task automatic launch(input [4:0] row);
        cim_rs1 = row;
        cim_valid = 1;
        @(posedge clk); #1;
        cim_valid = 0;
    endtask

    // wait for done==1 with timeout; returns 1 on success
    task automatic wait_done(output int ok);
        int n;
        logic [31:0] st;
        ok = 0; n = 0;
        while (n < 2000) begin
            bus_r(32'h2000_0010, st);
            if ((st & 32'h2) != 0) begin ok = 1; n = 2000; end
            else begin @(posedge clk); n = n + 1; end
        end
    endtask

    task automatic read_result(output [31:0] val);
        repeat (5) @(posedge clk); // capture latency: CAP+1 settles result_reg
        bus_r(32'h2000_0014, val);
    endtask

    task automatic check_eq(input string tag, input [31:0] got, input [31:0] want);
        if (got !== want) begin
            $display("[FAIL] %0s: got 0x%08h want 0x%08h", tag, got, want);
            errors = errors + 1;
        end else begin
            $display("[PASS] %0s = 0x%08h", tag, got);
        end
    endtask

    initial begin
        int r, c, ok;
        logic [31:0] v, st;
        errors = 0;
        $display("== tb_cim_dispatch start ==");

        rst_n = 0; bus_write = 0; bus_read = 0; cim_valid = 0; cim_rs1 = 0;
        bus_addr = 0; bus_wdata = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // fixed vectors: row2 = 1..16, row15 = all 1s, act = all 2s
        for (r = 0; r < ROWS; r = r + 1)
            for (c = 0; c < COLS; c = c + 1)
                TW[r][c] = 8'sd0;
        for (c = 0; c < COLS; c = c + 1) begin
            TW[2][c] = c + 1;
            TW[15][c] = 8'sd1;
            TA[c] = 8'sd2;
        end

        // ---------- T1: loader readback ----------
        bus_w(32'h2000_0000, 32'd33); bus_r(32'h2000_0000, v);
        check_eq("T1/WADDR", v, 32'd33);
        bus_w(32'h2000_0008, 32'd7);  bus_r(32'h2000_0008, v);
        check_eq("T1/AADDR", v, 32'd7);
        bus_r(32'h2000_0010, st); // idle STATUS must be 0
        check_eq("T1/STATUS-idle", st, 32'd0);
        bus_r(32'h2000_0014, v);  // no run yet -> 0
        check_eq("T1/RESULT-idle", v, 32'd0);

        // ---------- T2: full run, row 2 -> 272 ----------
        load_row(2); load_act();
        launch(5'd2);
        // busy must assert promptly
        @(posedge clk); #1;
        bus_r(32'h2000_0010, st);
        if ((st & 32'h1) == 0) begin
            $display("[FAIL] T2/busy not set after launch (STATUS=0x%h)", st);
            errors = errors + 1;
        end
        wait_done(ok);
        if (!ok) begin $display("[FAIL] T2/done timeout"); errors = errors + 1; end
        read_result(v);
        check_eq("T2/RESULT-row2", v, ref_dot(2)); // 272
        bus_r(32'h2000_0010, st);
        check_eq("T2/STATUS-hold", st, 32'h2);

        // ---------- T3: overlap -> dropped, relaunch clears ----------
        launch(5'd2);                    // accepted (from HOLD)
        @(posedge clk); @(posedge clk);  // now busy (RUN/WAIT)
        launch(5'd2);                    // overlapping -> dropped
        wait_done(ok);
        if (!ok) begin $display("[FAIL] T3/done timeout"); errors = errors + 1; end
        read_result(v);
        check_eq("T3/RESULT-intact", v, ref_dot(2));
        bus_r(32'h2000_0010, st);
        check_eq("T3/STATUS-dropped", st, 32'h6); // busy0 done1 dropped1
        // T3b: consecutive-cycle launches (the real SoC hazard shape: two
        // CIM.RUN words on back-to-back cycles). First accepted from HOLD,
        // second lands while busy -> dropped. Level (not edge) launch
        // discipline is what makes the second word visible at all.
        launch(5'd2);                    // accepted (from HOLD), clears flag
        launch(5'd2);                    // NEXT cycle, still busy -> dropped
        wait_done(ok);
        if (!ok) begin $display("[FAIL] T3b/done timeout"); errors = errors + 1; end
        read_result(v);
        check_eq("T3b/RESULT-intact", v, ref_dot(2));
        bus_r(32'h2000_0010, st);
        check_eq("T3b/STATUS-dropped", st, 32'h6);
        launch(5'd2);                    // clean relaunch clears flag
        wait_done(ok);
        if (!ok) begin $display("[FAIL] T3/relaunch timeout"); errors = errors + 1; end
        read_result(v);
        check_eq("T3/RESULT-relaunch", v, ref_dot(2));
        bus_r(32'h2000_0010, st);
        check_eq("T3/STATUS-cleared", st, 32'h2);

        // ---------- T4: clamp rs1=31 -> row 15 (16 ones x 2 = 32) ----------
        load_row(15);
        launch(5'd31);
        wait_done(ok);
        if (!ok) begin $display("[FAIL] T4/done timeout"); errors = errors + 1; end
        read_result(v);
        check_eq("T4/RESULT-clamped", v, ref_dot(15)); // 32

        // ---------- T5: mid-run loader write ignored ----------
        load_row(2);
        launch(5'd2);
        repeat (4) @(posedge clk);       // deep in WAIT (busy)
        bus_w(32'h2000_0000, 2*COLS+0);  // retarget col 0...
        bus_w(32'h2000_0004, 8'h7F);     // ...to 127 (would corrupt to ~272+125)
        wait_done(ok);
        if (!ok) begin $display("[FAIL] T5/done timeout"); errors = errors + 1; end
        read_result(v);
        check_eq("T5/RESULT-unaffected", v, ref_dot(2)); // still 272

        // ---------- T6: reset mid-run ----------
        load_row(2);
        launch(5'd2);
        repeat (4) @(posedge clk);
        rst_n = 0;
        repeat (2) @(posedge clk);
        bus_r(32'h2000_0010, st);
        if (st !== 32'd0) begin
            $display("[FAIL] T6/STATUS after reset = 0x%h, want 0", st);
            errors = errors + 1;
        end else $display("[PASS] T6/STATUS cleared by reset");
        rst_n = 1;
        repeat (2) @(posedge clk);
        // engine must accept a fresh run after reset (reload: reset kept mem)
        launch(5'd2);
        wait_done(ok);
        if (!ok) begin $display("[FAIL] T6/recover timeout"); errors = errors + 1; end
        read_result(v);
        check_eq("T6/RESULT-recover", v, ref_dot(2));

        if (errors == 0)
            $display("*** ALL CHECKS PASSED (tb_cim_dispatch) ***");
        else begin
            $display("*** FAILURES: %0d ***", errors);
            $fatal(1);
        end
        $finish;
    end

    initial begin
        repeat (300000) @(posedge clk);
        $display("*** WATCHDOG TIMEOUT ***");
        $fatal(1);
    end
endmodule
