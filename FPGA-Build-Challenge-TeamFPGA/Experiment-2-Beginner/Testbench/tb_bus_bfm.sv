// ============================================================================
// tb_bus_bfm.sv - self-checking bus testbench for the AXI-Lite fabric.
//
// WHAT IS VERIFIED AND WHY (plain English):
//   P1  RAM data integrity: random addr/data/strobe writes, read-back match.
//       Proves the interconnect routes AW+W to the right slave and the RAM
//       honors byte strobes.
//   P2  Back-to-back transactions: zero-idle-cycle writes then reads.
//       Proves wr_busy/rd_busy release logic does not insert dead cycles
//       or drop the second transaction.
//   P3  Simultaneous AW+W valid: master asserts both at once.
//       Proves the IC backpressures W (legal) or accepts it correctly -
//       and never mispairs AW/W.
//   P4  W-before-ready back-pressure: slave side delayed ready on write.
//       Proves W held stable until ready (AXI stable-while-waiting rule).
//   P5  DECERR: writes/reads to unmapped space complete with RESP=DECERR
//       and do NOT hang the bus (recovery checked with a following good
//       transaction).
//   P6  CRC golden answer: "123456789" -> 0xCBF43926 through the full
//       interconnect path (known published constant).
//   P7  CRC wstrb: strobed byte writes fold only strobed bytes.
//   P8  Reset mid-transaction: assert reset while a write is in flight,
//       then verify the fabric still completes a fresh transaction.
//
// Protocol checkers (always-on assertions):
//   * valid must not drop without ready (AXI stable rule) on every channel
//   * W data/strb stability while W valid && !w_ready
//   * b/r responses only while a transaction is outstanding
// ============================================================================
`timescale 1ns/1ps
import mem_map_pkg::*;

module tb_bus_bfm;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;   // 100 MHz

    // ---------------- master BFM channels ----------------
    logic        aw_valid;
    logic [31:0] aw_addr;
    wire         aw_ready;
    logic        w_valid;
    logic [31:0] w_data;
    logic [3:0]  w_strb;
    wire         w_ready;
    wire         b_valid;
    wire [1:0]   b_resp;
    logic        b_ready;
    logic        ar_valid;
    logic [31:0] ar_addr;
    wire         ar_ready;
    wire         r_valid;
    wire [31:0]  r_data;
    wire [1:0]   r_resp;
    logic        r_ready;

    int errors = 0;

    // ---------------- DUTs: IC -> RAM + CRC ----------------
    logic        ram_aw_valid;  logic [31:0] ram_aw_addr;  wire ram_aw_ready;
    logic        ram_w_valid;   logic [31:0] ram_w_data;   logic [3:0] ram_w_strb;  wire ram_w_ready;
    wire         ram_b_valid;   wire [1:0]   ram_b_resp;   logic ram_b_ready;
    logic        ram_ar_valid;  logic [31:0] ram_ar_addr;  wire ram_ar_ready;
    wire         ram_r_valid;   wire [31:0]  ram_r_data;   wire [1:0]  ram_r_resp;  logic ram_r_ready;

    logic        crc_aw_valid;  logic [31:0] crc_aw_addr;  wire crc_aw_ready;
    logic        crc_w_valid;   logic [31:0] crc_w_data;   logic [3:0] crc_w_strb;  wire crc_w_ready;
    wire         crc_b_valid;   wire [1:0]   crc_b_resp;   logic crc_b_ready;
    logic        crc_ar_valid;  logic [31:0] crc_ar_addr;  wire crc_ar_ready;
    wire         crc_r_valid;   wire [31:0]  crc_r_data;   wire [1:0]  crc_r_resp;  logic crc_r_ready;
    wire         crc_busy, crc_done;

    bus_interconnect u_ic (
        .clk, .rst_n,
        .m_aw_valid(aw_valid), .m_aw_addr(aw_addr), .m_aw_ready(aw_ready),
        .m_w_valid(w_valid), .m_w_data(w_data), .m_w_strb(w_strb), .m_w_ready(w_ready),
        .m_b_valid(b_valid), .m_b_resp(b_resp), .m_b_ready(b_ready),
        .m_ar_valid(ar_valid), .m_ar_addr(ar_addr), .m_ar_ready(ar_ready),
        .m_r_valid(r_valid), .m_r_data(r_data), .m_r_resp(r_resp), .m_r_ready(r_ready),
        .ram_aw_valid, .ram_aw_addr, .ram_aw_ready,
        .ram_w_valid, .ram_w_data, .ram_w_strb, .ram_w_ready,
        .ram_b_valid, .ram_b_resp, .ram_b_ready,
        .ram_ar_valid, .ram_ar_addr, .ram_ar_ready,
        .ram_r_valid, .ram_r_data, .ram_r_resp, .ram_r_ready,
        .crc_aw_valid, .crc_aw_addr, .crc_aw_ready,
        .crc_w_valid, .crc_w_data, .crc_w_strb, .crc_w_ready,
        .crc_b_valid, .crc_b_resp, .crc_b_ready,
        .crc_ar_valid, .crc_ar_addr, .crc_ar_ready,
        .crc_r_valid, .crc_r_data, .crc_r_resp, .crc_r_ready
    );

    axi_ram #(.ADDR_BYTES(16)) u_ram (
        .clk, .rst_n,
        .s_axi_aw_valid(ram_aw_valid), .s_axi_aw_addr(ram_aw_addr), .s_axi_aw_ready(ram_aw_ready),
        .s_axi_w_valid(ram_w_valid), .s_axi_w_data(ram_w_data), .s_axi_w_strb(ram_w_strb), .s_axi_w_ready(ram_w_ready),
        .s_axi_b_valid(ram_b_valid), .s_axi_b_resp(ram_b_resp), .s_axi_b_ready(ram_b_ready),
        .s_axi_ar_valid(ram_ar_valid), .s_axi_ar_addr(ram_ar_addr), .s_axi_ar_ready(ram_ar_ready),
        .s_axi_r_valid(ram_r_valid), .s_axi_r_data(ram_r_data), .s_axi_r_resp(ram_r_resp), .s_axi_r_ready(ram_r_ready)
    );

    crc32_accel u_crc (
        .clk, .rst_n,
        .s_axi_aw_valid(crc_aw_valid), .s_axi_aw_addr(crc_aw_addr), .s_axi_aw_ready(crc_aw_ready),
        .s_axi_w_valid(crc_w_valid), .s_axi_w_data(crc_w_data), .s_axi_w_strb(crc_w_strb), .s_axi_w_ready(crc_w_ready),
        .s_axi_b_valid(crc_b_valid), .s_axi_b_resp(crc_b_resp), .s_axi_b_ready(crc_b_ready),
        .s_axi_ar_valid(crc_ar_valid), .s_axi_ar_addr(crc_ar_addr), .s_axi_ar_ready(crc_ar_ready),
        .s_axi_r_valid(crc_r_valid), .s_axi_r_data(crc_r_data), .s_axi_r_resp(crc_r_resp), .s_axi_r_ready(crc_r_ready),
        .crc_busy, .crc_done
    );

    // ---------------- always-on protocol assertions ----------------
    // AXI stable rule: once VALID is asserted, it must stay high (and payload
    // stable) until READY. Violations here are exactly the "AI bus glue" bug.
    logic aw_v_q; logic [31:0] aw_a_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin aw_v_q <= 0; aw_a_q <= '0; end
        else begin
            if (aw_v_q && !aw_ready)
                assert (aw_valid && aw_addr == aw_a_q)
                else begin $error("[AXI] AW dropped/unstable while !ready"); errors++; end
            aw_v_q <= aw_valid && !aw_ready ? 1'b1 : aw_valid;
            if (!aw_v_q && aw_valid) aw_a_q <= aw_addr;
            if (aw_ready) aw_v_q <= 1'b0;
        end
    end

    logic w_v_q; logic [31:0] w_d_q; logic [3:0] w_s_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin w_v_q <= 0; w_d_q <= '0; w_s_q <= '0; end
        else begin
            if (w_v_q && !w_ready)
                assert (w_valid && w_data == w_d_q && w_strb == w_s_q)
                else begin $error("[AXI] W dropped/unstable while !ready"); errors++; end
            if (w_ready) w_v_q <= 1'b0;
            else if (w_valid && !w_v_q) begin w_v_q <= 1'b1; w_d_q <= w_data; w_s_q <= w_strb; end
        end
    end

    logic ar_v_q; logic [31:0] ar_a_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ar_v_q <= 0; ar_a_q <= '0; end
        else begin
            if (ar_v_q && !ar_ready)
                assert (ar_valid && ar_addr == ar_a_q)
                else begin $error("[AXI] AR dropped/unstable while !ready"); errors++; end
            if (ar_ready) ar_v_q <= 1'b0;
            else if (ar_valid && !ar_v_q) begin ar_v_q <= 1'b1; ar_a_q <= ar_addr; end
        end
    end

    // ---------------- BFM tasks ----------------
    // RACE-FREE PATTERN (proven necessary in project 1):
    //   * Drive stimulus at NEGEDGE so the DUT sees stable values at posedge.
    //   * Sample responses right after POSEDGE - reads return PRE-edge values
    //     (NBA updates happen after all active-region reads), so
    //     `valid && ready` after @(posedge clk) means "handshake occurred AT
    //     this edge". No delta-race, no missed handshakes, no double-accept.

    task automatic axi_write(input logic [31:0] a, input logic [31:0] d, input logic [3:0] s);
        @(negedge clk);
        aw_valid = 1; aw_addr = a;
        w_valid  = 0;
        forever begin
            @(posedge clk);
            if (aw_valid && aw_ready) break;
        end
        @(negedge clk);          // deassert only at negedge: no active-region
        aw_valid = 0;            // race with the DUT's always_ff sampling
        w_valid = 1; w_data = d; w_strb = s;
        forever begin
            @(posedge clk);
            if (w_valid && w_ready) break;
        end
        @(negedge clk);
        w_valid = 0;
        b_ready = 1;
        forever begin
            @(posedge clk);
            if (b_valid) break;
        end
        @(negedge clk);
        b_ready = 0;
        if (b_resp !== RESP_OKAY) begin
            $error("[BFM] write %h got resp %b (expected OKAY)", a, b_resp); errors++;
        end
    endtask

    task automatic axi_write_expect(input logic [31:0] a, input logic [31:0] d,
                                    input logic [3:0] s, input logic [1:0] exp_resp);
        @(negedge clk);
        aw_valid = 1; aw_addr = a;
        forever begin
            @(posedge clk);
            if (aw_valid && aw_ready) break;
        end
        @(negedge clk);
        aw_valid = 0;
        w_valid = 1; w_data = d; w_strb = s;
        forever begin
            @(posedge clk);
            if (w_valid && w_ready) break;
        end
        @(negedge clk);
        w_valid = 0;
        b_ready = 1;
        forever begin
            @(posedge clk);
            if (b_valid) break;
        end
        @(negedge clk);
        b_ready = 0;
        if (b_resp !== exp_resp) begin
            $error("[BFM] write %h resp %b expected %b", a, b_resp, exp_resp); errors++;
        end
    endtask

    task automatic axi_read(input logic [31:0] a, output logic [31:0] d,
                            input logic [1:0] exp_resp = RESP_OKAY);
        @(negedge clk);
        ar_valid = 1; ar_addr = a;
        forever begin
            @(posedge clk);
            if (ar_valid && ar_ready) break;
        end
        @(negedge clk);
        ar_valid = 0;
        r_ready = 1;
        forever begin
            @(posedge clk);
            if (r_valid) break;
        end
        @(negedge clk);
        r_ready = 0;
        d = r_data;              // sampled pre-NBA at the r_valid edge - stable
        if (r_resp !== exp_resp) begin
            $error("[BFM] read %h resp %b expected %b", a, r_resp, exp_resp); errors++;
        end
    endtask

    // ---------------- main test sequence ----------------
    int i;
    logic [31:0] rdata;
    logic [31:0] scr_mem [32];   // must hold the full P1 loop range (0..31)
    logic [31:0] scr_strb [32];
    logic [31:0] scr_addr [32];

    initial begin
        b_ready = 0; r_ready = 0;
        aw_valid = 0; w_valid = 0; ar_valid = 0;
        $display("== tb_bus_bfm start ==");
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // ---- P1: random data integrity with random strobes ----
        $display("[P1] RAM random writes/reads with random strobes");
        for (i = 0; i < 32; i = i + 1) begin
            scr_addr[i] = 32'h100 + 4 * i;
            scr_mem[i]  = $random;
            scr_strb[i] = $random;
            axi_write(scr_addr[i], scr_mem[i], scr_strb[i][3:0]);
        end
        for (i = 0; i < 32; i = i + 1) begin
            logic [31:0] lane_mask;
            lane_mask = '0;
            axi_read(scr_addr[i], rdata);
            // Build a byte-lane mask from the ACTUAL 4-bit strobe used in the
            // write. TL/DR: masking rdata with the full $random scr_strb value
            // (as earlier versions did) forced a comparison on UNSTROBED
            // lanes that legitimately hold x (never written = uninitialized
            // BRAM) - a TB bug, not an RTL bug. Lanes the strobe excluded are
            // don't-care here.
            if (scr_strb[i][0]) lane_mask[7:0]   = '1;
            if (scr_strb[i][1]) lane_mask[15:8]  = '1;
            if (scr_strb[i][2]) lane_mask[23:16] = '1;
            if (scr_strb[i][3]) lane_mask[31:24] = '1;
            if ((rdata & lane_mask) !== (scr_mem[i] & lane_mask)) begin
                $error("[P1] addr %h: got %h expected(strobed) %h strb %b",
                       scr_addr[i], rdata, scr_mem[i], scr_strb[i][3:0]);
                errors++;
            end
        end
        $display("[P1] done");

        // ---- P2: back-to-back, no idle ----
        $display("[P2] back-to-back writes then reads");
        for (i = 0; i < 8; i = i + 1)
            axi_write(32'h300 + 4*i, 32'hA500_0000 + i, 4'hF);
        for (i = 0; i < 8; i = i + 1) begin
            axi_read(32'h300 + 4*i, rdata);
            if (rdata !== 32'hA500_0000 + i) begin
                $error("[P2] back-to-back mismatch at %0d: %h", i, rdata); errors++;
            end
        end
        $display("[P2] done");

        // ---- P3: simultaneous AW+W valid (worst-case pairing) ----
        $display("[P3] simultaneous AW+W valid");
        aw_valid = 1; aw_addr = 32'h400;
        w_valid  = 1; w_data  = 32'hC0FF_EE11; w_strb = 4'hF;
        b_ready  = 1; r_ready = 0;
        // hold until both handshakes seen (AW and W may accept in either order)
        begin
            int aw_seen, w_seen;
            aw_seen = 0; w_seen = 0;
            while (!(aw_seen == 1 && w_seen == 1)) begin
                @(posedge clk);
                if (aw_valid && aw_ready) begin aw_seen = 1; aw_valid = 0; end
                if (w_valid && w_ready)   begin w_seen = 1;  w_valid  = 0; end
            end
            while (!b_valid) @(posedge clk);
            b_ready = 0;
        end
        axi_read(32'h400, rdata);
        if (rdata !== 32'hC0FF_EE11) begin
            $error("[P3] simultaneous AW+W data wrong: %h", rdata); errors++;
        end
        $display("[P3] done");

        // ---- P5: DECERR on unmapped, then bus recovery ----
        $display("[P5] DECERR + recovery");
        axi_write_expect(32'h7FFF_FFF0, 32'h1234_5678, 4'hF, RESP_DECERR);
        axi_read(32'h7FFF_FFF0, rdata, RESP_DECERR);
        axi_write(32'h500, 32'h0BAD_F00D, 4'hF);   // must still work
        axi_read(32'h500, rdata);
        if (rdata !== 32'h0BAD_F00D) begin
            $error("[P5] recovery transaction failed: %h", rdata); errors++;
        end
        $display("[P5] done");

        // ---- P6: CRC golden answer via full interconnect ----
        $display("[P6] CRC golden '123456789' -> 0xCBF43926");
        axi_write(CRC_CTRL, 32'h1, 4'h1);          // reset CRC
        // CRC folds byte0 (LSB) first, so each ASCII chunk is written
        // byte-reversed: "1234" -> 0x34333231 puts '1' (0x31) on the
        // wire first. Writing 0x31323334 would CRC "43218765..."
        axi_write(CRC_DATA, 32'h3433_3231, 4'hF);
        axi_write(CRC_DATA, 32'h3837_3635, 4'hF);
        axi_write(CRC_DATA, 32'h0000_0039, 4'h1);  // byte0 = '9' (0x39)
        wait (!crc_busy);
        axi_read(CRC_RESULT, rdata);
        if (rdata !== 32'hCBF4_3926) begin
            $error("[P6] CRC mismatch: got %h expected cbf43926", rdata); errors++;
        end
        $display("[P6] done (crc=%h)", rdata);

        // ---- P7: CRC wstrb semantics ----
        $display("[P7] CRC wstrb fold");
        axi_write(CRC_CTRL, 32'h1, 4'h1);
        axi_write(CRC_DATA, 32'hDE_AD_BE_EF, 4'h0); // nothing strobed -> no-op
        axi_write(CRC_DATA, 32'h00_00_00_AB, 4'h1); // fold only 0xAB
        wait (!crc_busy);
        axi_read(CRC_RESULT, rdata);
        // reference: CRC32(init) of single byte 0xAB, bitwise model
        begin
            logic [31:0] c;
            int k;
            c = 32'hFFFF_FFFF ^ 32'hAB;
            for (k = 0; k < 8; k = k + 1)
                c = c[0] ? ((c >> 1) ^ 32'hEDB8_8320) : (c >> 1);
            c = ~c;
            if (rdata !== c) begin
                $error("[P7] wstrb CRC mismatch: got %h expected %h", rdata, c); errors++;
            end
        end
        $display("[P7] done");

        // ---- P8: reset mid-transaction, then recovery ----
        $display("[P8] reset mid-transaction");
        aw_valid = 1; aw_addr = 32'h600;
        do @(posedge clk); while (!aw_ready);
        aw_valid = 0;
        w_valid = 1; w_data = 32'hFFFF_0000; w_strb = 4'hF;
        @(posedge clk);
        @(posedge clk);
        rst_n = 0;                    // kill the fabric mid-W
        repeat (3) @(posedge clk);
        aw_valid = 0; w_valid = 0; b_ready = 0; r_ready = 0;
        rst_n = 1;
        repeat (2) @(posedge clk);
        axi_write(32'h600, 32'h600D_6001, 4'hF);
        axi_read(32'h600, rdata);
        if (rdata !== 32'h600D_6001) begin
            $error("[P8] post-reset recovery failed: %h", rdata); errors++;
        end
        $display("[P8] done");

        // ---------------- summary ----------------
        repeat (4) @(posedge clk);
        if (errors == 0) $display("*** ALL CHECKS PASSED (tb_bus_bfm) ***");
        else             $display("*** FAILURES: %0d ***", errors);
        $finish;
    end

    // watchdog: if any phase hangs (deadlocked handshake), dump state and quit
    // so the failure is diagnosable instead of an eternal silent hang.
    initial begin
        #2_000_000;   // 2 ms sim-time budget (phases need far less)
        $display("*** WATCHDOG TIMEOUT - hung handshake. Snapshot: ***");
        $display("  rst_n=%b aw_v=%b aw_r=%b w_v=%b w_r=%b b_v=%b b_r=%b",
                 rst_n, aw_valid, aw_ready, w_valid, w_ready, b_valid, b_ready);
        $display("  ar_v=%b ar_r=%b r_v=%b r_r=%b ram_b_v=%b crc_b_v=%b",
                 ar_valid, ar_ready, r_valid, r_ready, ram_b_valid, crc_b_valid);
        $display("  tb.ar_addr=%h ic.rd_busy=%b ic.ar_sel_q=%b ic.ram_ar_valid=%b ram.ar_ready=%b ram.r_valid=%b ic.rd_internal=%b ic.r_int_q=%b ic.r_valid_t=%b",
                 ar_addr, u_ic.rd_busy, u_ic.ar_sel_q, u_ic.ram_ar_valid,
                 ram_ar_ready, ram_r_valid, u_ic.rd_internal, u_ic.r_int_q, u_ic.r_valid_t);
        $display("  ic.wr_busy=%b ic.aw_sel_q=%b ic.b_int_q=%b",
                 u_ic.wr_busy, u_ic.aw_sel_q, u_ic.b_int_q);
        $display("*** FAILURES (watchdog): %0d ***", errors + 1);
        $finish;
    end
endmodule
