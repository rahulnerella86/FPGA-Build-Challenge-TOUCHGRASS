// ============================================================================
// mac_array.sv - N_PAR parallel dot-product lanes, SEQUENTIAL dataflow.
//
// WHY SEQUENTIAL (not systolic): each DSP48E1 holds one full MAC (mult +
// post-adder, 3 stages). Systolic would need a DSP per (row x col) cell.
// DSP budget math (Basys3 XC7A35T = 90 DSP48E1, Nexys A7 XC7A100T = 240):
//   N_PAR=8  -> 8 DSP (9% Basys3)     N_PAR=32 -> 32 DSP (36% Basys3)
//   N_PAR=16 -> 16 DSP (18% Basys3)   N_PAR=64 -> 64 DSP (71% Basys3, risky)
// Default N_PAR=8: single DSP column region, trivially closes timing at
// 100 MHz on both boards. Raise to 16/32 only after Vivado says utilization
// is clean (see README fallback table).
//
// Each lane holds its own weight (loaded once per tile), streams K
// activations, accumulates internally, and presents one partial sum per
// lane. The TOP, not this array, handles tiling/reduction.
// valid_o = AND of lane valids (all lanes share the same en/weight timing).
// ============================================================================
module mac_array #(
    parameter int N_PAR     = 8,   // parallel lanes (= DSP count)
    parameter int IN_WIDTH  = 8,
    parameter int ACCUM     = 64,
    parameter int OUT_WIDTH = 2*IN_WIDTH + $clog2(ACCUM+1)
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic clr_i,                       // clears all lanes
    input  logic en_i,                        // step all lanes
    input  logic signed [IN_WIDTH-1:0] a_i [N_PAR],  // per-lane activation
    input  logic signed [IN_WIDTH-1:0] b_i [N_PAR],  // per-lane weight
    output logic signed [OUT_WIDTH-1:0] sum_o [N_PAR],
    output logic valid_o
);
    logic [N_PAR-1:0] lane_v;

    genvar g;
    generate
        for (g = 0; g < N_PAR; g++) begin : GEN_LANE
            mac_unit #(
                .IN_WIDTH (IN_WIDTH),
                .ACCUM    (ACCUM),
                .OUT_WIDTH(OUT_WIDTH)
            ) u_mac (
                .clk_i  (clk_i),
                .rst_ni (rst_ni),
                .clr_i  (clr_i),
                .en_i   (en_i),
                .a_i    (a_i[g]),
                .b_i    (b_i[g]),
                .sum_o  (sum_o[g]),
                .valid_o(lane_v[g])
            );
        end
    endgenerate

    assign valid_o = &lane_v;
endmodule
