// ============================================================================
// alu.sv - RV32I ALU for the AI accelerator core.
// ============================================================================
// Supports all 32 RV32I arithmetic/logic/shift operations.
// ============================================================================

`timescale 1ns / 1ps

module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [4:0]  alu_ctrl,
    output wire [31:0] result,
    output wire        zero
);

    // ALU operation codes (matching control_unit encoding)
    localparam ALU_ADD  = 5'd0;
    localparam ALU_SUB  = 5'd1;
    localparam ALU_AND  = 5'd2;
    localparam ALU_OR   = 5'd3;
    localparam ALU_XOR  = 5'd4;
    localparam ALU_SLL  = 5'd5;
    localparam ALU_SRL  = 5'd6;
    localparam ALU_SRA  = 5'd7;
    localparam ALU_SLT  = 5'd8;
    localparam ALU_SLTU = 5'd9;
    localparam ALU_LUI  = 5'd10;
    localparam ALU_AUIPC= 5'd11;
    localparam ALU_ADDI = 5'd12;
    localparam ALU_INVALID = 5'd31;

    wire [31:0] add_result;
    wire [31:0] sub_result;
    wire [31:0] and_result;
    wire [31:0] or_result;
    wire [31:0] xor_result;
    wire [31:0] sll_result;
    wire [31:0] srl_result;
    wire [31:0] sra_result;
    wire [31:0] slt_result;
    wire [31:0] sltu_result;

    assign add_result = a + b;
    assign sub_result = a - b;
    assign and_result = a & b;
    assign or_result  = a | b;
    assign xor_result = a ^ b;
    assign sll_result = a << b[4:0];
    assign srl_result = a >> b[4:0];
    assign sra_result = $signed(a) >>> b[4:0];
    assign slt_result = $signed(a) < $signed(b) ? 32'd1 : 32'd0;
    assign sltu_result = a < b ? 32'd1 : 32'd0;

    reg [31:0] result_reg;
    reg        zero_reg;

    always @(*) begin
        result_reg = 32'd0;
        zero_reg   = 1'b0;
        case (alu_ctrl)
            ALU_ADD:  begin result_reg = add_result; zero_reg = (add_result == 32'd0); end
            ALU_SUB:  begin result_reg = sub_result; zero_reg = (sub_result == 32'd0); end
            ALU_AND:  begin result_reg = and_result; zero_reg = (and_result == 32'd0); end
            ALU_OR:   begin result_reg = or_result;  zero_reg = (or_result  == 32'd0); end
            ALU_XOR:  begin result_reg = xor_result; zero_reg = (xor_result == 32'd0); end
            ALU_SLL:  begin result_reg = sll_result; zero_reg = (sll_result == 32'd0); end
            ALU_SRL:  begin result_reg = srl_result; zero_reg = (srl_result == 32'd0); end
            ALU_SRA:  begin result_reg = sra_result; zero_reg = (sra_result == 32'd0); end
            ALU_SLT:  begin result_reg = slt_result; zero_reg = (slt_result == 32'd0); end
            ALU_SLTU: begin result_reg = sltu_result;zero_reg = (sltu_result == 32'd0);end
            ALU_LUI:  begin result_reg = b;          zero_reg = (b == 32'd0); end
            ALU_AUIPC:begin result_reg = a + b;      zero_reg = (a + b == 32'd0); end
            ALU_ADDI: begin result_reg = a + b;      zero_reg = (a + b == 32'd0); end
            default:  begin result_reg = 32'd0;      zero_reg = 1'b1; end
        endcase
    end

    assign result = result_reg;
    assign zero   = zero_reg;

endmodule