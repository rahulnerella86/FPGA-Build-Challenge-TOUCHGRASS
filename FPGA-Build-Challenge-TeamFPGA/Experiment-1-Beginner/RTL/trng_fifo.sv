// ============================================================================
// trng_fifo.sv - parameterized synchronous AXI-Stream FIFO for TRNG words.
// ----------------------------------------------------------------------------
// Occupancy is derived COMBINATIONALLY from the two pointers (cnt = wr-rd),
// so tvalid/full are exact every cycle: reads and writes self-gate, no
// register-count race, no duplicate or ghost reads. Writes that arrive while
// FULL are dropped (backpressure contract: a FULL consumer holds tready low).
//
// AXI-Stream read side: tvalid/tready/tdata. tdata is combinational
// (FWFT-style) - the testbench samples tvalid one cycle ahead (tv_prev) to
// avoid same-edge write/read races, mirroring how a real consumer must
// handle FWFT.
//
// FLAGGED SHORTCUT: registered (non-BRAM) storage - fine for small DEPTH;
// for much deeper FIFOs switch to BRAM inference (Vivado does this
// automatically when the array crosses its memory threshold) - verify in
// the utilization report.
// ============================================================================
module trng_fifo #(
    parameter int DATA_WIDTH = 16,
    parameter int DEPTH      = 16
)(
    input  wire clk,
    input  wire rst_n,

    // write side (from the bit packer)
    input  wire                wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,

    // read side (AXI-Stream sink)
    output wire                tvalid,
    input  wire                tready,
    output wire [DATA_WIDTH-1:0] tdata,
    output wire                full,
    output wire                empty,
    output wire                overflow  // pulses when a write is DROPPED (full)
);
    localparam int A = $clog2(DEPTH);

    logic [DATA_WIDTH-1:0] mem [DEPTH];
    logic [A:0] wr_ptr, rd_ptr;
    logic [A:0] cnt;
    reg drop_ev;
    // debug counters (TB scoreboard reference - no synthesis impact, stripped
    // by tools? NO: they are real regs; keep them, they are tiny and useful)
    logic [15:0] dbg_wr_cnt, dbg_rd_cnt;

    assign cnt   = wr_ptr - rd_ptr;        // exact occupancy (wide pointers)
    assign full  = (cnt == DEPTH);
    assign empty = (cnt == 0);
    assign tvalid = !empty;
    assign overflow = drop_ev;
    // low A bits of the pointer index the DEPTH physical cells (circular)
    assign tdata  = mem[rd_ptr[A-1:0]];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= 0;
            rd_ptr     <= 0;
            drop_ev    <= 1'b0;
            dbg_wr_cnt <= '0;
            dbg_rd_cnt <= '0;
        end else begin
            drop_ev <= 1'b0;
            if (wr_en && !full) begin
                mem[wr_ptr[A-1:0]] <= wr_data;
                wr_ptr            <= wr_ptr + 1;
                dbg_wr_cnt        <= dbg_wr_cnt + 1;
            end else if (wr_en && full) begin
                drop_ev <= 1'b1;   // FLAGGED: drop-on-overflow policy, made visible
            end
            if (tvalid && tready) begin
                rd_ptr     <= rd_ptr + 1;
                dbg_rd_cnt <= dbg_rd_cnt + 1;
            end
        end
    end
endmodule