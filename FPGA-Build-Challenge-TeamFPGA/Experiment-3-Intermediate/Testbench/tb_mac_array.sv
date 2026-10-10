`timescale 1ns/1ps
`include "vectors/layer0_params.svh"
// ============================================================================
// tb_mac_array.sv - self-checking testbench for mac_array + nn_accel_top.
//
// WHAT IS VERIFIED (and why):
//  1. mac_unit known-answer: 3x(-7)+5x11 = 34 after the 2-cycle pipeline.
//  2. Full tile from REAL quantized vectors (tb/vectors/*.mem, produced by
//     scripts/quantize_model.py): run nn_accel_top, compare all N_PAR
//     outputs against layer0_y_exp.mem produced independently by
//     scripts/reference_layer.py. Bit-exact or FAIL - no tolerance.
//  3. Back-to-back tiles: re-arm start_i after DONE and check the second
//     tile (guards the S_DONE->S_IDLE accumulator clear).
// (NPAR/KLEN/SHIFT come from layer0_params.svh - single source of truth.)
// ============================================================================
module tb_mac_array;
    localparam int N_PAR = TB_NPAR;
    localparam int K_LEN = TB_KLEN;
    localparam int SHIFT = TB_SHIFT;
    localparam int ACCUM  = 256;
    localparam int OUTW = 16 + $clog2(ACCUM+1);

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    int errors = 0;

    // ---------- DUT 1: single mac_unit known answer ----------
    // All stimulus initialized at declaration: control inputs must NEVER
    // float (x) across reset release - an x en_i poisons prod_q through the
    // ternary and 0+x=x then infects the accumulator forever (found by trace).
    logic clr1 = 1, en1 = 0;
    logic signed [7:0] a1 = 0, b1 = 0;
    logic signed [OUTW-1:0] s1;
    logic v1;
    mac_unit #(.IN_WIDTH(8), .ACCUM(ACCUM)) u_uut (
        .clk_i(clk), .rst_ni(rst_n), .clr_i(clr1), .en_i(en1),
        .a_i(a1), .b_i(b1), .sum_o(s1), .valid_o(v1)
    );

    // ---------- DUT 2: full tile ----------
    logic start = 0, done;
    logic signed [7:0] y [N_PAR];
    nn_accel_top #(
        .N_PAR(N_PAR), .K_LEN(K_LEN), .SHIFT(SHIFT), .ACCUM(ACCUM),
        .ACT_MEM("tb/vectors/layer0_x.mem"),
        .WGT_MEM("tb/vectors/layer0_w.mem"),
        .BIAS_MEM("tb/vectors/layer0_b.mem")
    ) u_top (
        .clk_i(clk), .rst_ni(rst_n), .start_i(start), .done_o(done), .y_o(y)
    );

    logic signed [7:0] exp_mem [N_PAR];
    initial $readmemh("tb/vectors/layer0_y_exp.mem", exp_mem);
    // debug: cycle trace of DUT1 pipeline (temporary, remove after M1 green)
    always @(posedge clk) begin
        if (rst_n && $time < 500)
            $display("M1 t=%0t en=%b clr=%b a=%0d b=%0d | acc=%0d v=%b sum=%0d",
                     $time, en1, clr1, a1, b1, u_uut.acc_q, v1, s1);
    end


    task automatic pulse_start;
        begin
            start = 1; @(posedge clk); start = 0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);
        $display("== tb_mac_array start ==");

        // ---- [M1] mac_unit known answer: acc = 3*(-7) + 5*11 = 34 ----
        // Drive stimulus on NEGEDGE (never race the DUT's posedge sampling),
        // then wait for valid and sample on the following negedge (after the
        // output register has settled).
        clr1 = 1; en1 = 0; a1 = 0; b1 = 0;
        @(negedge clk); clr1 = 0;
        @(negedge clk); a1 = 8'd3;  b1 = -8'd7; en1 = 1;
        @(negedge clk); a1 = 8'd5;  b1 = 8'd11;
        @(negedge clk); en1 = 0; a1 = 0; b1 = 0;
        do @(posedge clk); while (!v1);
        @(negedge clk);
        if (s1 !== 34) begin $error("[M1] got %0d expect 34", s1); errors++; end
        else $display("[M1] mac_unit known-answer OK (34)");

        // ---- [M2] full tile vs independent reference ----
        pulse_start();
        do @(posedge clk); while (!done);
        @(negedge clk);
        for (int g = 0; g < N_PAR; g++) begin
            if (y[g] !== exp_mem[g]) begin
                $error("[M2] lane %0d: got %0d expect %0d", g, y[g], exp_mem[g]);
                errors++;
            end
        end
        if (errors == 0) $display("[M2] full tile bit-exact vs reference");

        // ---- [M3] back-to-back re-arm ----
        repeat (3) @(posedge clk);
        pulse_start();
        do @(posedge clk); while (!done);
        @(negedge clk);
        for (int g = 0; g < N_PAR; g++) begin
            if (y[g] !== exp_mem[g]) begin
                $error("[M3] lane %0d: got %0d expect %0d (2nd tile)", g, y[g], exp_mem[g]);
                errors++;
            end
        end
        if (errors == 0) $display("[M3] back-to-back tile OK");

        if (errors == 0) $display("*** ALL CHECKS PASSED (tb_mac_array) ***");
        else             $display("*** FAILURES: %0d ***", errors);
        $finish;
    end

    initial begin
        #500_000;
        $display("*** WATCHDOG TIMEOUT (tb_mac_array hung) ***");
        $finish;
    end
endmodule
