`timescale 1ns/1ps
// ============================================================================
// nn_accel_top.sv - one INT8 fully-connected layer tile.
//
// Computes N_PAR output neurons over a shared K_LEN activation vector:
//     acc[g] = sum_k W[g][k]*X[k] + B[g] ;  y[g] = sat8(acc[g] >>> SHIFT)
//
// Dataflow (sequential, weight-stationary-by-streaming):
//   IDLE -> RUN (K_LEN cycles; each cycle presents X[k] broadcast plus the
//   per-lane W[g][k] slice) -> DRAIN (2 dead beats for the MAC pipeline) ->
//   DONE (y_o valid, requant+bias applied combinationally).
// Weights/activations/bias live in synchronous BRAMs preloaded from .mem
// files exported by scripts/quantize_model.py; the expected outputs in
// layer0_y_exp.mem come from scripts/reference_layer.py (bit-exact match).
//
// FLAGGED SIMPLIFICATIONS:
//  * No double buffering, no tiling loop: one tile per start_i pulse. The
//    TB (or a future sequencer) re-arms for the next tile.
//  * Bias/ReLU fused as (add + shift + saturate); no separate requant unit.
// ============================================================================
module nn_accel_top #(
    parameter int N_PAR     = 8,    // output neurons per tile (= DSP count)
    parameter int K_LEN     = 16,   // shared input vector length
    parameter int IN_WIDTH  = 8,
    parameter int ACCUM     = 256,
    parameter int OUT_WIDTH = 2*IN_WIDTH + $clog2(ACCUM+1),
    parameter int SHIFT     = 0,    // requant shift (from meta file)
    parameter string ACT_MEM  = "", // K_LEN      INT8 hex bytes
    parameter string WGT_MEM  = "", // N_PAR*K    INT8 hex bytes, row-major
    parameter string BIAS_MEM = ""  // N_PAR      32-bit hex words
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic start_i,     // rising edge starts one tile
    output logic done_o,      // 1-cycle pulse; y_o valid in DONE
    output logic signed [IN_WIDTH-1:0] y_o [N_PAR]
);
    // ---- memories ----
    logic signed [IN_WIDTH-1:0] act_mem [K_LEN];
    logic signed [IN_WIDTH-1:0] wgt_mem [N_PAR*K_LEN];
    logic signed [31:0]         bias_mem [N_PAR];
    initial begin
        if (ACT_MEM  != "") $readmemh(ACT_MEM,  act_mem);
        if (WGT_MEM  != "") $readmemh(WGT_MEM,  wgt_mem);
        if (BIAS_MEM != "") $readmemh(BIAS_MEM, bias_mem);
    end
    // debug: dump loaded memories once + RUN trace (temporary)
    initial begin
        #1;
        $display("TOP act[0..3]=%0d %0d %0d %0d", act_mem[0], act_mem[1], act_mem[2], act_mem[3]);
        $display("TOP wgt lane0 k0..3=%0d %0d %0d %0d bias0=%0d",
                 wgt_mem[0], wgt_mem[1], wgt_mem[2], wgt_mem[3], bias_mem[0]);
    end
    // ---- FSM ----
    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DRAIN, S_DONE} st_t;
    st_t st_q;
    logic [$clog2(K_LEN+1)-1:0] kcnt_q;
    logic [1:0] drain_q;
    logic start_q;

    logic signed [IN_WIDTH-1:0] avec  [N_PAR];
    logic signed [IN_WIDTH-1:0] wvec  [N_PAR];
    logic signed [OUT_WIDTH-1:0] psum [N_PAR];
    logic mac_en, mac_clr;

    genvar gv;
    generate
        for (gv = 0; gv < N_PAR; gv++) begin : GEN_VEC
            assign avec[gv] = act_mem[kcnt_q];
            assign wvec[gv] = wgt_mem[gv*K_LEN + kcnt_q];
        end
    endgenerate

    mac_array #(
        .N_PAR(N_PAR), .IN_WIDTH(IN_WIDTH), .ACCUM(ACCUM), .OUT_WIDTH(OUT_WIDTH)
    ) u_arr (
        .clk_i(clk_i), .rst_ni(rst_ni), .clr_i(mac_clr), .en_i(mac_en),
        .a_i(avec), .b_i(wvec), .sum_o(psum), .valid_o()
    );

    // requant: (psum + bias) >>> SHIFT, saturate to INT8
    function automatic logic signed [IN_WIDTH-1:0] req(
        input logic signed [OUT_WIDTH-1:0] p, input logic signed [31:0] b);
        logic signed [OUT_WIDTH+1:0] t;
        logic signed [OUT_WIDTH+1:0] s;
        begin
            t = OUT_WIDTH'(p) + b;
            s = t >>> SHIFT;
            if (s > 127)       req = 127;
            else if (s < -128) req = -128;
            else               req = IN_WIDTH'(s);
        end
    endfunction

    genvar gy;
    generate
        for (gy = 0; gy < N_PAR; gy++) begin : GEN_Y
            // y_o sampled by the TB on the negedge AFTER done_o rises, so a
            // DONE-registered output is guaranteed settled (the pure-comb
            // form raced the requant chain in the tool, found by M2 trace).
            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) y_o[gy] <= '0;
                else if (st_q == S_DONE) y_o[gy] <= req(psum[gy], bias_mem[gy]);
                else if (st_q == S_IDLE) y_o[gy] <= '0;
            end
        end
    endgenerate

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            st_q <= S_IDLE; kcnt_q <= '0; drain_q <= '0; start_q <= 0;
        end else begin
            start_q <= start_i;
            case (st_q)
                S_IDLE: begin
                    kcnt_q <= '0; drain_q <= '0;
                    if (start_i && !start_q) st_q <= S_RUN;
                end
                S_RUN: begin
                    if (kcnt_q == K_LEN-1) begin st_q <= S_DRAIN; drain_q <= '0; end
                    else kcnt_q <= kcnt_q + 1;
                end
                S_DRAIN: begin
                    // 3 dead beats: prod pipe (1) + add pipe (1) + valid
                    // realign (1). Two beats leave the last product stranded
                    // in prod_q when S_DONE reads psum (found by M2 trace).
                    if (drain_q == 2'd3) st_q <= S_DONE;
                    else drain_q <= drain_q + 1;
                end
                S_DONE: st_q <= S_IDLE;
                default: st_q <= S_IDLE;
            endcase
        end
    end

    assign mac_clr = (st_q == S_IDLE);
    assign mac_en  = (st_q == S_RUN);
    assign done_o  = (st_q == S_DONE);
endmodule
