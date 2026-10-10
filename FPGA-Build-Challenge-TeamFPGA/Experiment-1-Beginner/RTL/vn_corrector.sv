// ============================================================================
// vn_corrector.sv - von Neumann (pair-wise) bias corrector.
// ----------------------------------------------------------------------------
// Reads a bit each cycle; every pair of CONSECUTIVE bits is evaluated:
//     01 -> emit 0        10 -> emit 1       00 or 11 -> emit nothing
// This removes static bias IF the raw bitstream is made of independent,
// identically-distributed bits with an arbitrary per-bit bias p. Throughput
// is data-dependent: on unbiased input it averages 1 output bit per 4 input
// bits (2 bits consumed per decision with 50% successes). The strict subset
// is what makes the output provably unbiased (no LFSR whitening needed - an
// LFSR would only be appropriate for decorrelating remaining structure, not
// removing bias).
//
// The pairs here are NON-OVERLAPPING by construction: a 2-state FSM consumes
// exactly one input bit per clock and emits at most one output bit, so pairs
// are always disjoint (bit 0/1 then 2/3 ...). No alignment races are possible.
// ============================================================================
module vn_corrector (
    input  wire clk,
    input  wire rst_n,
    input  wire in_bit,     // one raw bit per cycle (can arrive every cycle)
    output reg  out_valid,  // pulse when out_bit is valid
    output reg  out_bit
);
    // 0 = waiting for first bit of a pair, 1 = have first, evaluating second
    logic       have_first;
    logic [1:0] pair;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            have_first <= 1'b0;
            pair       <= 2'b00;
            out_valid  <= 1'b0;
            out_bit    <= 1'b0;
        end else begin
            if (!have_first) begin
                // consume bit 1 of the pair
                have_first <= 1'b1;
                pair       <= {1'b0, in_bit};
                out_valid  <= 1'b0;
            end else begin
                // we now have both bits: pair = {first, second}
                out_valid <= (pair[0] ^ in_bit) ? 1'b1 : 1'b0;
                out_bit   <= pair[0];        // emit first bit when 10/01
                have_first<= 1'b0;
                pair      <= 2'b00;
            end
        end
    end
endmodule