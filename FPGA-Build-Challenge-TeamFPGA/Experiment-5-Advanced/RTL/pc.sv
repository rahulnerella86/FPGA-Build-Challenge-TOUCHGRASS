// ============================================================================
// pc.sv - Program counter with PC+4 and branch/jump support.
// ============================================================================

`timescale 1ns / 1ps

module pc (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] pc_next,
    output reg  [31:0] pc_reg
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_reg <= 32'd0;
        else
            pc_reg <= pc_next;
    end

endmodule