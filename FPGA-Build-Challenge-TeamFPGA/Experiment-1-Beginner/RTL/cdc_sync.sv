// ============================================================================
// cdc_sync.sv - (STAGES)-flop CDC synchronizer for a single bit.
// ----------------------------------------------------------------------------
// Single-bit cross-domain bit: the ring-oscillator output is asynchronous to
// the system clock (clk) at all times. A chain of STAGES registers in the
// destination clock domain is the standard mitigation for metastability; a two-
// stage chain reduces the MTBF to astronomic levels for COARSE random data,
// but should NOT be pushed past 3 stages for Fmax reasons - this is a an RTL-
// level "good enough" answer and the metastability residual is flagged for
// consideration on hardware (see README "Hardware validation checklist").
//
// REQUIRED HARDWARE NOTE: On Xilinx 7-series, mark the two FF cells with
// `(* ASYNC_REG = "TRUE" *)` for the tool to place them adjacently (LUT/FF
// pairing) and to prevent them being merged into a shift chain that bypasses
// the protection.
// ============================================================================
module cdc_sync #(
    parameter int STAGES = 2
)(
    input  wire clk,
    input  wire rst_n,
    input  wire en,         // (unused - kept out: 0 not used)
    input  wire src_i,
    output wire q_o
);
    // If STAGES<2, synthesis will not behave - guard.
    generate
        if (STAGES >= 2) begin : sync_path
            logic [STAGES-1:0] ff;
            (* ASYNC_REG = "TRUE" *) reg [1:0] ff_meta;
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    ff_meta <= 2'b0;
                    ff      <= '0;
                end else begin
                    ff_meta[0] <= src_i;
                    ff_meta[1] <= ff_meta[0];
                    for (int i = 0; i < STAGES-2; i = i + 1)
                        ff[i+1] <= ff[i];
                    ff[0]      <= ff_meta[1];
                end
            end
            assign q_o = ff[STAGES-2];
        end else begin : passthrough
            // If STAGES<2 the user opted out of safety - be loud about it.
            assign q_o = src_i;
        end
    endgenerate
endmodule