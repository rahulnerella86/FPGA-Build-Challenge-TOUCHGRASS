// ============================================================================
// mac_unit.sv - parameterized signed MAC with accumulation.
//
// DATAPATH (the standard DSP48E1 MAC idiom):
//     acc_q <= acc_q + a_i * b_i   when en_i
// The multiply operand pair is EXPLICITLY sign-extended to OUT_WIDTH first
// (no width-casts: this tool zero-extends OUT_WIDTH'(x) in some contexts,
// found by TB). Because 8b x 8b signed fits in 16 bits <= OUT_WIDTH, the
// 25-bit-context multiply is exact and maps onto one DSP48E1 slice.
//
// TIMING CONTRACT: after the last en_i cycle, sum_o is FINAL on the next
// cycle. valid_o = v_q[1] rises accordingly (2-cycle pipe on en_i). There
// is no one-cycle-behind product register: the previous version accumulated
// the REGISTERED product, stranding the last en cycle's product (proven by
// tb trace: acc got -21, the fresh 55 was never added -> M1 fail).
//
// RESET: async-assert, sync-deassert. clr_i is a synchronous clear used by
// the tile FSM between tiles.
// ============================================================================
module mac_unit #(
    parameter int IN_WIDTH  = 8,    // activation/weight width (signed)
    parameter int ACCUM     = 64,   // max accumulations before explicit reset
    parameter int OUT_WIDTH = 2*IN_WIDTH + $clog2(ACCUM+1)
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic                  clr_i,       // sync clear of accumulator
    input  logic                  en_i,        // 1: accumulate a*b this cycle
    input  logic signed [IN_WIDTH-1:0] a_i,
    input  logic signed [IN_WIDTH-1:0] b_i,
    output logic signed [OUT_WIDTH-1:0] sum_o, // final 1 cycle after last en_i
    output logic                  valid_o
);
    // explicit sign extension (replication, NOT a width-cast)
    wire signed [OUT_WIDTH-1:0] a_ext =
        {{(OUT_WIDTH-IN_WIDTH){a_i[IN_WIDTH-1]}}, a_i};
    wire signed [OUT_WIDTH-1:0] b_ext =
        {{(OUT_WIDTH-IN_WIDTH){b_i[IN_WIDTH-1]}}, b_i};
    wire signed [OUT_WIDTH-1:0] prod_w = a_ext * b_ext;

    logic signed [OUT_WIDTH-1:0] acc_q;
    logic [1:0] v_q;

    // elaboration-time width sanity
    initial begin
        if (OUT_WIDTH < 2*IN_WIDTH + $clog2(ACCUM+1))
            $error("mac_unit: OUT_WIDTH %0d too small", OUT_WIDTH);
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            acc_q <= '0; v_q <= '0;
        end else if (clr_i) begin
            acc_q <= '0; v_q <= '0;
        end else begin
            // if/else, not a ternary: `acc <= en ? acc + p : '0` widened the
            // multiply to UNSIGNED in this tool (found by tb_signmul trace)
            if (en_i) acc_q <= acc_q + prod_w;
            v_q <= {v_q[0], en_i};
        end
    end

    assign sum_o   = acc_q;
    assign valid_o = v_q[1];
endmodule

