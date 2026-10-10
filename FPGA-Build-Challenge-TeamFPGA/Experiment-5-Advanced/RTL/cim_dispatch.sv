// ============================================================================
// cim_dispatch.sv - dispatch/wiring layer: custom instruction -> CiM RTL.
// ----------------------------------------------------------------------------
// Owns one pim_mac_bram instance (referenced from
// ../../04-sram-pim-cnn/rtl/pim_mac_bram.sv at compile time - NOT copied;
// see sim/run_modelsim.do) and exposes three services on one MMIO window
// (CIM_BASE, default 0x20000000):
//
//   1. LOADER (offsets 0x00/0x04 WADDR/WDATA, 0x08/0x0C AADDR/ADATA):
//      firmware stages INT8 weights/activations into the CiM memories
//      through plain stores. Honored in D_IDLE/D_HOLD only; writes that
//      arrive mid-run are IGNORED (documented, TB-proven).
//   2. LAUNCH (cim_valid rising edge + cim_rs1 row select): starts a full
//      matrix run and latches which result row is presented. Accepted in
//      D_IDLE/D_HOLD; a launch arriving while busy is IGNORED and sets a
//      sticky CIM_DROPPED flag (there is no core stall port on the
//      single-cycle base core, so overlapping issue cannot backpressure -
//      software must poll STATUS; see README hazard section).
//   3. STATUS/RESULT (offsets 0x10/0x14, read-only): STATUS = {29'b0,
//      dropped, done, busy}; RESULT = rmem[selected row], captured into
//      result_reg (2 cycles after pim done: 1 sync-read + 1 capture;
//      firmware polls done first, so this is always settled).
//
// Row select is clamped to NUM_ROWS-1 (rs1=31 on a 16-row engine reads
// row 15, TB-proven). RESULT of an unwritten row is whatever pim holds
// (X in sim until loaded) - firmware loads every row it reads.
//
// Synthesizable as-is (no hierarchical references, single driver per reg).
// ============================================================================
module cim_dispatch #(
    parameter int NUM_ROWS = 16,
    parameter int NUM_COLS = 16,
    parameter logic [31:0] CIM_BASE = 32'h2000_0000
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- CPU MMIO bus (word accesses, offsets below; base stripped by SoC)
    input  wire [31:0] bus_addr,    // full byte address (we decode [5:2])
    input  wire [31:0] bus_wdata,
    output logic [31:0] bus_rdata,  // combinational (single-cycle core)
    input  wire        bus_write,
    input  wire        bus_read,

    // ---- custom-instruction launch (level during the execute cycle)
    input  wire       cim_valid,    // from custom_instr_decode
    input  wire [4:0] cim_rs1       // result-row select
);
    localparam int WDEPTH = NUM_ROWS*NUM_COLS;

    // ---------------- dispatch FSM ----------------
    localparam logic [2:0] D_IDLE = 3'd0,  // loader live, no result yet
                           D_RUN  = 3'd1,  // start pulse to pim (1 cycle)
                           D_WAIT = 3'd2,  // pim running
                           D_CAP  = 3'd3,  // sync-read selected row (1 cycle)
                           D_HOLD = 3'd4;  // result valid, loader live again
    logic [2:0] d_state;

    // Launch discipline is LEVEL-based, deliberately (TB-proven): the
    // single-cycle base core presents each fetched word for exactly one
    // cycle and PC always advances, so cim_valid==1 in an accepting state
    // means exactly one launch. An earlier revision used rising-edge
    // detection, which WRONGLY merged two back-to-back CIM.RUN words (two
    // consecutive valid cycles) into one launch and swallowed the second
    // without even setting dropped. With level discipline, a second word
    // arriving while busy correctly records dropped=1.
    wire cim_launch;
    assign cim_launch = cim_valid;

    // ---------------- loader + result regs ----------------
    logic [$clog2(WDEPTH)-1:0] waddr_q;
    logic [$clog2(NUM_COLS)-1:0] aaddr_q;
    logic [$clog2(NUM_ROWS)-1:0] sel_q;
    logic [31:0] result_reg;
    logic        dropped_q;

    wire loader_live;
    assign loader_live = (d_state == D_IDLE) || (d_state == D_HOLD);

    wire [$clog2(NUM_ROWS)-1:0] sel_clamped;
    assign sel_clamped = (cim_rs1 < NUM_ROWS) ? cim_rs1[$clog2(NUM_ROWS)-1:0]
                                              : NUM_ROWS-1;

    // ---------------- pim control ----------------
    wire pim_start;
    wire pim_busy;
    wire pim_done;
    wire pim_r_valid;
    wire [31:0] pim_r_data;
    logic pim_r_en;

    assign pim_start = (d_state == D_RUN);

    // ---------------- MMIO ----------------
    wire [3:0] reg_off;
    assign reg_off = bus_addr[5:2]; // 0x00..0x14

    // STATUS bit0=busy, bit1=done, bit2=dropped(sticky). busy covers
    // D_RUN/D_WAIT/D_CAP; D_IDLE (never run) reads 0/0; D_HOLD reads 0/1.
    wire stat_busy;
    wire stat_done;
    assign stat_busy = (d_state == D_RUN) || (d_state == D_WAIT) || (d_state == D_CAP);
    assign stat_done = (d_state == D_HOLD);

    // pim load enables (loader-live gating = ignore-during-busy rule)
    wire w_load;
    wire a_load;
    assign w_load = bus_write && loader_live && (reg_off == 4'h1);
    assign a_load = bus_write && loader_live && (reg_off == 4'h3);

    always @(*) begin
        if (bus_read) begin
            case (reg_off)
                4'h0:    bus_rdata = { {(32-$clog2(WDEPTH)){1'b0}}, waddr_q };
                4'h2:    bus_rdata = { {(32-$clog2(NUM_COLS)){1'b0}}, aaddr_q };
                4'h4:    bus_rdata = {29'b0, dropped_q, stat_done, stat_busy};
                4'h5:    bus_rdata = result_reg;
                default: bus_rdata = 32'h0000_0000;
            endcase
        end else begin
            bus_rdata = 32'h0000_0000;
        end
    end

    // ---------------- main FSM ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d_state     <= D_IDLE;
            waddr_q     <= '0;
            aaddr_q     <= '0;
            sel_q       <= '0;
            result_reg  <= '0;
            dropped_q   <= 1'b0;
            pim_r_en    <= 1'b0;
        end else begin
            pim_r_en    <= 1'b0;

            // loader writes (ignored mid-run by loader_live gating above)
            if (bus_write && loader_live) begin
                case (reg_off)
                    4'h0: waddr_q <= bus_wdata[$clog2(WDEPTH)-1:0];
                    4'h2: aaddr_q <= bus_wdata[$clog2(NUM_COLS)-1:0];
                    default: ;
                endcase
            end

            case (d_state)
                D_IDLE: begin
                    if (cim_launch) begin
                        sel_q     <= sel_clamped;
                        dropped_q <= 1'b0;
                        d_state   <= D_RUN;
                    end
                end
                D_RUN: begin
                    // A second CIM.RUN word can already be live HERE (the
                    // very next cycle after accept: the core never stalls).
                    // TB-proven: without this arm the consecutive-launch
                    // hazard is swallowed silently (no drop flag).
                    if (cim_launch)
                        dropped_q <= 1'b1;
                    d_state <= D_WAIT; // pim_start pulsed this cycle
                end
                D_WAIT: begin
                    if (pim_done)
                        d_state <= D_CAP;
                    // overlapping launch while the engine is busy: ignore + flag
                    if (cim_launch)
                        dropped_q <= 1'b1;
                end
                D_CAP: begin
                    pim_r_en <= 1'b1;
                    if (cim_launch)
                        dropped_q <= 1'b1;
                    d_state <= D_HOLD;
                end
                D_HOLD: begin
                    // pim rdata (selected row) settled from the CAP read
                    result_reg <= pim_r_data;
                    if (cim_launch) begin
                        sel_q     <= sel_clamped;
                        dropped_q <= 1'b0;
                        d_state   <= D_RUN;
                    end
                end
                default: d_state <= D_IDLE;
            endcase
        end
    end

    // ---------------- CiM engine (project 04, by reference - never forked) --
    pim_mac_bram #(
        .NUM_ROWS (NUM_ROWS),
        .NUM_COLS (NUM_COLS)
    ) u_pim (
        .clk       (clk),
        .rst_n     (rst_n),
        .w_wr_en   (w_load),
        .w_wr_addr (waddr_q),
        .w_wr_data (bus_wdata[7:0]),
        .a_wr_en   (a_load),
        .a_wr_addr (aaddr_q),
        .a_wr_data (bus_wdata[7:0]),
        .start     (pim_start),
        .busy      (pim_busy),
        .done      (pim_done),
        .r_rd_en   (pim_r_en),
        .r_rd_addr (sel_q),
        .r_rd_data (pim_r_data),
        .r_rd_valid(pim_r_valid)
    );
    wire _unused_pim_busy  = pim_busy;
    wire _unused_pim_valid = pim_r_valid;

endmodule
