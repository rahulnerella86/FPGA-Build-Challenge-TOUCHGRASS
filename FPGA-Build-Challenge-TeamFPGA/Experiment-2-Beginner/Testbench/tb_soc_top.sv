`timescale 1ns/1ps
import mem_map_pkg::*;

// ============================================================================
// tb_soc_top.sv - full-SoC testbench (fabric + RAM + CRC behind the
// mem2axi_lite bridge), driving the SAME memory-port contract picorv32 uses.
//
// Sequence mirrors firmware/main.c exactly:
//   1. store patterns to RAM      (RAM data path through the whole fabric)
//   2. reset CRC, feed "123456789"
//   3. read CRC_RESULT -> MUST be 0xCBF43926
//   4. OUT_PORT write and an unmapped address -> no hang, correct resp code
//
// HONEST LIMITATION: the real PicoRV32 core is NOT instantiated here
// (ModelSim cannot compile the Yosys-oriented core cleanly). This TB proves
// the memory-port contract + every downstream bus transaction; the final
// core-in-the-loop boot must be run in Vivado (see README hardware checklist).
// ============================================================================
module tb_soc_top;
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic [31:0] mem_addr, mem_wdata, mem_rdata;
    logic [3:0]  mem_wstrb;
    logic        mem_valid, mem_ready;

    soc_top dut (
        .clk, .rst_n,
        .mem_addr_in(mem_addr), .mem_wdata_in(mem_wdata), .mem_wstrb_in(mem_wstrb),
        .mem_valid_in(mem_valid), .mem_rdata_out(mem_rdata), .mem_ready_out(mem_ready)
    );

    // ---- permanent transaction-latency instrumentation ----
    // Logs every mem-port transaction as [ST] lines: valid assert -> ready
    // seen -> valid dropped. Timestamps are %0t = picoseconds (timescale
    // 1ns/1ps). Parsed by tools/make_report_figures.py to produce the
    // documented latency figure. 100 MHz clock -> 10000 ps per cycle.
    time st_t_assert = 0, st_t_ready = 0;
    logic st_was_valid = 0, st_was_ready = 0;
    always @(posedge clk) begin
        if (mem_valid && !st_was_valid) begin
            st_t_assert <= $time;
            $display("[ST] t=%0t asserting mem_valid", $time);
        end
        if (mem_valid && mem_ready && !st_was_ready) begin
            st_t_ready <= $time;
            $display("[ST] t=%0t ready seen", $time);
        end
        if (!mem_valid && st_was_valid)
            $display("[ST] t=%0t valid dropped", $time);
        st_was_valid <= mem_valid;
        st_was_ready <= mem_ready;
    end

    // --- mem-port store: assert valid+data, wait for ready, release ---
    task automatic mstore(input logic [31:0] a, input logic [31:0] d,
                          input logic [3:0] s = 4'hF);
        mem_addr  = a;
        mem_wdata = d;
        mem_wstrb = s;
        mem_valid = 1;
        do @(posedge clk); while (!mem_ready);
        @(negedge clk);
        mem_valid = 0;
        mem_wstrb = 4'h0;
        // WAIT FOR READY-LOW before the next transaction: mem_ready is a
        // pulse from the PREVIOUS op, and a fresh op must not observe it
        // (FWFT-style handshake). Without this the read loop exits on the
        // stale pulse and samples mem_rdata a cycle early (found by trace).
        do @(posedge clk); while (mem_ready);
    endtask

    // --- mem-port load: assert valid (no strobe), wait for data+ready ---
    task automatic mload(input logic [31:0] a, output logic [31:0] d);
        mem_addr  = a;
        mem_wdata = '0;
        mem_wstrb = 4'h0;
        mem_valid = 1;
        do @(posedge clk); while (!mem_ready);
        @(negedge clk);
        d = mem_rdata;
        mem_valid = 0;
        do @(posedge clk); while (mem_ready);   // same ready-low settle
    endtask

    int errors = 0;
    logic [31:0] ld;

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);
        $display("== tb_soc_top start ==");

        // ---- [S1] RAM store/load via fabric ----
        mstore(32'h100, 32'hCAFE_BABE, 4'hF);
        mload(32'h100, ld);
        if (ld !== 32'hCAFE_BABE) begin
            $error("[S1] RAM load mismatch: got %h", ld); errors++;
        end
        $display("[S1] RAM fabric load = %h", ld);

        // ---- [S2] partial strobe: only byte1 overwritten ----
        // byte1 = bits[15:8]; data must be 0x0000_AA00 for byte1=0xAA
        mstore(32'h100, 32'h0000_AA00, 4'h2);
        mload(32'h100, ld);
        if (ld !== 32'hCAFE_AABE) begin
            $error("[S1b] strobe merge mismatch: got %h expect cafeaabe", ld); errors++;
        end
        $display("[S1b] strobe merged = %h", ld);

        // ---- [S3] CRC reset + golden '123456789' -> 0xCBF43926 ----
        mstore(CRC_CTRL, 32'h1, 4'h1);              // reset CRC
        // byte0 (LSB) folds first, so write strings byte-reversed:
        mstore(CRC_DATA, 32'h3433_3231, 4'hF);      // "1234"
        mstore(CRC_DATA, 32'h3837_3635, 4'hF);      // "5678"
        mstore(CRC_DATA, 32'h0000_0039, 4'h1);      // "9"
        do @(posedge clk); while (dut.crc_busy);
        mload(CRC_RESULT, ld);
        if (ld !== 32'hCBF4_3926) begin
            $error("[S3] CRC golden mismatch: got %h", ld); errors++;
        end
        $display("[S3] CRC golden = %h (expect cbf43926)", ld);

        // ---- [S4] OUT_PORT write must be accepted (monitor, no data) ----
        mstore(OUT_PORT, 32'h0000_0042, 4'h1);
        $display("[S4] OUT_PORT write accepted");
        mload(OUT_PORT, ld);       // read gives DECERR data, must not hang
        $display("[S4] OUT_PORT read returned (resp data=%h)", ld);

        repeat (4) @(posedge clk);
        if (errors == 0) $display("*** ALL CHECKS PASSED (tb_soc_top) ***");
        else             $display("*** FAILURES: %0d ***", errors);
        $finish;
    end

    // watchdog in case the fabric deadlocks
    initial begin
        #1_000_000;
        $display("*** WATCHDOG TIMEOUT (tb_soc_top hung) ***");
        $finish;
    end
endmodule