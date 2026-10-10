// ============================================================================
// register_file.sv - RV32I 32x32 register file.
// ============================================================================

`timescale 1ns / 1ps

module register_file #(
    parameter int NUM_REGS = 32
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        reg_write_en,
    input  wire [4:0]  read_reg1,
    input  wire [4:0]  read_reg2,
    input  wire [4:0]  write_reg,
    input  wire [31:0] write_data,
    output wire [31:0] read_data1,
    output wire [31:0] read_data2
);

    // Register array (infers flip-flops, could use BRAM for 32x32)
    reg [31:0] regs [0:NUM_REGS-1];

    // Read ports (combinational); x0 is hardwired to zero
    assign read_data1 = (read_reg1 == 5'd0) ? 32'd0 : regs[read_reg1];
    assign read_data2 = (read_reg2 == 5'd0) ? 32'd0 : regs[read_reg2];

    // Write port
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            integer i;
            for (i = 0; i < NUM_REGS; i = i + 1) begin
                regs[i] <= 32'd0;
            end
        end else if (reg_write_en && write_reg != 5'd0) begin
            regs[write_reg] <= write_data;
        end
    end

endmodule