// ============================================================================
// trng_top.sv - TRNG top: entropy source + CDC + von Neumann + packer + FIFO.
// ----------------------------------------------------------------------------
// Data path:
//   entropy_source (ring oscillators; synthesizable - USE_RING=1 in hardware)
//     -> cdc_sync (2-FF, cross-clock-domain)
//     -> vn_corrector (pair-wise von Neumann, removes static bias)
//     -> bit packer (WORD_BITS per word)
//     -> trng_fifo -> AXI-Stream output (tvalid/tready/tdata)
//
// USE_RING=1 : the ring oscillator source is compiled in (hardware; the TB
//              does NOT compile this path - combinational rings do not
//              simulate deterministically, see entropy_source.sv).
// USE_RING=0 : `ent_override_i` is used as the raw entropy bit (TB jitter
//              model). This is a flagged test mode; hardware ties USE_RING=1.
//
// FLAGGED SHORTCUTS: (1) 2-FF sync - naive, fine here, harden for production;
// (2) FIFO read is combinational (tdata = mem[rd_ptr]);
// (3) vN assumes inter-bit independence (valid for jittered sampling).
// ============================================================================
module trng_top #(
    parameter int         N_OS       = 4,
    parameter int         OSC_STAGES = 5,
    parameter int         WORD_BITS  = 16,
    parameter int         FIFO_DEPTH = 16,
    parameter bit         USE_RING   = 1'b1
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  enable_i,         // 1 = generate
    input  wire                  ent_override_i,   // USE_RING=0 raw bit source

    // AXI-Stream readout
    output wire                  tvalid,
    output wire [WORD_BITS-1:0]  tdata,
    input  wire                  tready,

    // debug (TB): correcor output pulses + packed-write pulses
    output wire                  d_vn_valid,
    output wire                  d_vn_bit,
    output wire                  d_overflow   // 1 = a packed word was DROPPED (FIFO full)
);
    // ---------------- raw entropy select ----------------
    logic osc_bit, raw_bit;
    generate
        if (USE_RING) begin : g_real
            entropy_source #(.N_OS(N_OS), .OSC_STAGES(OSC_STAGES)) u_ent (
                .enable (enable_i),
                .osc_raw(osc_bit)
            );
            assign raw_bit = osc_bit;
        end else begin : g_model
            assign raw_bit = ent_override_i;
        end
    endgenerate

    // ---------------- CDC synchronizer ----------------
    logic synced_bit;
    cdc_sync #(.STAGES(2)) u_sync (
        .clk  (clk),
        .rst_n(rst_n),
        .en   (enable_i),
        .src_i(raw_bit),
        .q_o  (synced_bit)
    );

    // ---------------- von Neumann corrector ----------------
    logic vn_valid, vn_bit;
    vn_corrector u_vn (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_bit   (synced_bit),
        .out_valid(vn_valid),
        .out_bit  (vn_bit)
    );
    assign d_vn_valid = vn_valid;
    assign d_vn_bit   = vn_bit;

    // ---------------- packer ----------------
    logic [WORD_BITS-1:0] sh;
    logic [$clog2(WORD_BITS)-1:0] nbits;
    logic wren;
    logic [WORD_BITS-1:0] wdat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sh    <= '0;
            nbits <= '0;
            wren  <= 1'b0;
            wdat  <= '0;
        end else begin
            wren <= 1'b0;
            if (vn_valid) begin
                sh <= {sh[WORD_BITS-2:0], vn_bit};
                if (nbits == WORD_BITS-1) begin
                    wren  <= 1'b1;
                    // first-collected bit becomes MSB (self-consistent order)
                    wdat  <= {sh[WORD_BITS-2:0], vn_bit};
                    nbits <= '0;
                end else begin
                    nbits <= nbits + 1;
                end
            end
        end
    end

    // ---------------- FIFO (AXI-Stream) ----------------
    logic tvalid_i, full_i, empty_i;
    trng_fifo #(.DATA_WIDTH(WORD_BITS), .DEPTH(FIFO_DEPTH)) u_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (wren),
        .wr_data (wdat),
        .tvalid  (tvalid_i),
        .tready  (tready),
        .tdata   (tdata),
        .full    (full_i),
        .empty   (empty_i),
        .overflow(d_overflow)
    );
    assign tvalid = tvalid_i;

    // structural visibility for FB harnesses
    wire _unused_full  = full_i;
    wire _unused_empty = empty_i;
endmodule