// ============================================================================
// branch_unit.sv - PC branch calculation for RV32I.
// ============================================================================

`timescale 1ns / 1ps

module branch_unit (
    input  wire [31:0] instr,
    input  wire [31:0] rs1_val,
    input  wire [31:0] rs2_val,
    input  wire [31:0] pc,
    output wire [31:0] branch_target,
    output wire        take_branch,
    output wire        is_branch,
    output wire        is_jal,
    output wire        is_jalr,
    output wire [31:0] jal_target,
    output wire [31:0] jalr_target
);

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];

    // RISC-V B-type immediate: {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}
    wire [31:0] b_imm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};

    // RISC-V J-type immediate: {instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}
    wire [31:0] j_imm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

    // Branch types
    wire is_beq  = (opcode == 7'b1100011) & (funct3 == 3'b000);
    wire is_bne  = (opcode == 7'b1100011) & (funct3 == 3'b001);
    wire is_blt  = (opcode == 7'b1100011) & (funct3 == 3'b100);
    wire is_bge  = (opcode == 7'b1100011) & (funct3 == 3'b101);
    wire is_bltu = (opcode == 7'b1100011) & (funct3 == 3'b110);
    wire is_bgeu = (opcode == 7'b1100011) & (funct3 == 3'b111);

    assign is_branch = (opcode == 7'b1100011);

    // JAL (opcode 1101111)
    wire is_jal_op = (opcode == 7'b1101111);
    assign is_jal = is_jal_op;

    // JALR (opcode 1100111, funct3=000)
    wire is_jalr_op = (opcode == 7'b1100111) & (funct3 == 3'b000);
    assign is_jalr = is_jalr_op;

    // Branch target = PC + B-type immediate
    assign branch_target = pc + b_imm;

    // Branch condition
    wire beq_val  = (rs1_val == rs2_val);
    wire bne_val  = (rs1_val != rs2_val);
    wire blt_val  = $signed(rs1_val) < $signed(rs2_val);
    wire bge_val  = $signed(rs1_val) >= $signed(rs2_val);
    wire bltu_val = rs1_val < rs2_val;
    wire bgeu_val = rs1_val >= rs2_val;

    wire branch_cond = (is_beq  & beq_val)  |
                       (is_bne  & bne_val)  |
                       (is_blt  & blt_val)  |
                       (is_bge  & bge_val)  |
                       (is_bltu & bltu_val) |
                       (is_bgeu & bgeu_val);

    assign take_branch = is_branch & branch_cond;

    // JAL target = PC + J-type immediate
    assign jal_target = pc + j_imm;

    // JALR target = (rs1 + sign_extend(imm[11:0])) & ~1 (aligned)
    wire [31:0] imm11_se = $signed({{21{instr[31]}}, instr[31:20]});
    assign jalr_target = (rs1_val + imm11_se) & 32'hFFFFFFFE;

endmodule