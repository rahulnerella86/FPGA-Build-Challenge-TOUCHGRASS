// ============================================================================
// entropy_source.sv - parameterized ring-oscillator entropy source (Xilinx 7-series).
// ----------------------------------------------------------------------------
// N_OS independent oscillators each built from OSC_STAGES (odd) inverters with
// the first stage replaced by a NAND(enable): all oscillator outputs are ORed
// onto osc_raw. The composite `osc_raw` crosses into the sampling clock domain
// in cdc_sync.sv - that cross-domain bit carries the entropy.
//
// SYNTHESIS NOTES (read before violating):
//  * These are intentionally-unclocked combinational loops. Vivado defaults to
//    combinational loop handling; keep the rings from being optimized away
//    with the `(* keep *)` marks below and the timing exclusions in the board
//    .xdc (see 01/constraints).
//  * Nothing in this module is clocked; it MUST be gated through cdc_sync
//    before any flop in the sampling clock domain - that is a TB duty.
//
// SIMULATION NOTE: a combinational ring with zero delays in ModelSim spins
// forever. The testbench therefore instantiates trng_top with a parameter
// switch (USE_JITTER_MODEL = 1) that swaps in a clocked behavioral jitter
// model (statistical jitter via $urandom, controlled bias via a PRNG) instead
// of this ring - the ring itself is verified for structure/synthesis only, not
// in the statistical loop. This is the standard, honest way to handle this.
// ============================================================================
module entropy_source #(
    parameter int N_OS       = 4,       // number of oscillators
    parameter int OSC_STAGES = 5        // stages per oscillator - keep odd, >=3
)(
    input  wire enable,     // 1 = oscillators free-running
    output wire osc_raw     // OR of all oscillator outputs
);
    localparam int MIN_STAGES = (OSC_STAGES >= 3) ? OSC_STAGES : 3;
    localparam int NST        = (MIN_STAGES % 2)  ? MIN_STAGES : (MIN_STAGES + 1);

    logic [N_OS-1:0] osc;

    generate
        if (N_OS > 0) begin : g_rogroup
            for (genvar g = 0; g < N_OS; g = g + 1) begin : g_ro
                // Ring: inverter chain + final NAND with enable feedback.
                logic [NST-1:0] ch;
                for (genvar i = 1; i < NST; i = i + 1) begin : g_inv
                    (* keep = "true" *) always_comb ch[i] = ~ch[i-1];
                end
                always_comb ch[0] = ~(enable & ch[NST-1]);
                assign osc[g] = ch[NST-1];
            end
        end
    endgenerate

    assign osc_raw = (N_OS > 0) ? (|osc) : 1'b0;
endmodule