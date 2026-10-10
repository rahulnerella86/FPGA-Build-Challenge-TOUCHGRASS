// ============================================================================
// control_unit.sv - RV32I instruction decoder / control logic for AI accel.
// ============================================================================

`timescale 1ns / 1ps

module control_unit (
    input  wire [31:0] instruction,
    input  wire        zero,
    output wire        reg_write,
    output wire        alu_src_a,
    output wire        alu_src_b,
    output wire        mem_to_reg,
    output wire        branch,
    output wire        jump,
    output wire        jump_reg,
    output wire        mem_read,
    output wire        mem_write,
    output wire [4:0]  alu_ctrl,
    output wire [1:0]  mem_size
);

    wire [6:0] opcode  = instruction[6:0];
    wire [2:0] funct3  = instruction[14:12];
    wire [6:0] funct7  = instruction[31:25];

    // Instruction types
    wire is_r_type  = (opcode == 7'b0110011);
    wire is_i_load  = (opcode == 7'b0000011);
    wire is_i_type = (opcode == 7'b0010011) & ~((instruction[14:12] == 3'b000) & (instruction[31:7] == 0));
    wire is_s_type = (opcode == 7'b0100011);
    wire is_b_type = (opcode == 7'b1100011);
    wire is_u_type = (opcode == 7'b0110111) | (opcode == 7'b0010111);
    wire is_j_type = (opcode == 7'b1101111);

    // Register write
    assign reg_write = is_r_type | is_i_type | is_i_load | is_u_type | is_j_type |
                       ((opcode == 7'b1100111) & (funct3 == 3'b000)); // JALR

    // ALU sources
    assign alu_src_a = (opcode == 7'b0010111);  // AUIPC: PC + imm
    assign alu_src_b = is_i_type | is_i_load | is_s_type | is_u_type | is_j_type |
                       ((opcode == 7'b1100111) & (funct3 == 3'b000));

    // Memory
    assign mem_to_reg = is_i_load;
    assign mem_read   = is_i_load;
    assign mem_write  = is_s_type;

    // Branch/Jump
    assign branch   = is_b_type;
    assign jump     = is_j_type | ((opcode == 7'b1100111) & (funct3 == 3'b000));
    assign jump_reg = (opcode == 7'b1100111) & (funct3 == 3'b000);

    // ALU control
    localparam ALU_ADD=0, ALU_SUB=1, ALU_AND=2, ALU_OR=3, ALU_XOR=4;
    localparam ALU_SLL=5, ALU_SRL=6, ALU_SRA=7, ALU_SLT=8, ALU_SLTU=9;
    localparam ALU_LUI=10, ALU_AUIPC=11, ALU_ADDI=12, ALU_SLLI=13;
    localparam ALU_SRLI=14, ALU_SRAI=15, ALU_RESERVED=31;

    reg [4:0] alu_ctrl_reg;
    reg [1:0] mem_size_reg;

    always @(*) begin
        alu_ctrl_reg = ALU_RESERVED;
        mem_size_reg = 2'b10;

        case (opcode)
            7'b0110011: begin  // R-type
                case (funct3)
                    3'b000: alu_ctrl_reg = funct7[5] ? ALU_SUB : ALU_ADD;
                    3'b111: alu_ctrl_reg = ALU_AND;
                    3'b110: alu_ctrl_reg = ALU_OR;
                    3'b100: alu_ctrl_reg = ALU_XOR;
                    3'b001: alu_ctrl_reg = ALU_SLL;
                    3'b101: alu_ctrl_reg = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b010: alu_ctrl_reg = ALU_SLT;
                    3'b011: alu_ctrl_reg = ALU_SLTU;
                endcase
            end
            7'b0010011, 7'b0000011: begin  // I-type (load/ALU)
                case (funct3)
                    3'b000: alu_ctrl_reg = ALU_ADD;   // ADDI / LB / LBU
                    3'b001: alu_ctrl_reg = ALU_SLL;   // SLLI / LH / LHU
                    3'b010: alu_ctrl_reg = ALU_SLT;   // SLTI / LW
                    3'b011: alu_ctrl_reg = ALU_SLTU;  // SLTIU
                    3'b100: alu_ctrl_reg = ALU_XOR;   // XORI
                    3'b101: alu_ctrl_reg = ALU_SRL;   // SRLI / SRAI
                    3'b110: alu_ctrl_reg = ALU_OR;    // ORI
                    3'b111: alu_ctrl_reg = ALU_AND;   // ANDI
                endcase
                if (funct7[5] & funct3 == 3'b101) alu_ctrl_reg = ALU_SRA;  // SRAI
            end
            7'b0100011: begin  // S-type
                case (funct3)
                    3'b000: alu_ctrl_reg = ALU_ADD;   // SB
                    3'b001: alu_ctrl_reg = ALU_ADD;   // SH
                    3'b010: alu_ctrl_reg = ALU_ADD;   // SW
                endcase
            end
            7'b0110111: alu_ctrl_reg = ALU_LUI;      // LUI
            7'b0010111: alu_ctrl_reg = ALU_AUIPC;    // AUIPC
            default:    alu_ctrl_reg = ALU_RESERVED;  // NOP / custom
        endcase

        // Memory size
        if (opcode == 7'b0000011) begin  // load
            case (funct3)
                3'b000: mem_size_reg = 2'b00;  // byte (LB/LBU)
                3'b001: mem_size_reg = 2'b01;  // halfword (LH/LHU)
                3'b010: mem_size_reg = 2'b10;  // word (LW)
            endcase
        end else if (opcode == 7'b0100011) begin  // store
            case (funct3)
                3'b000: mem_size_reg = 2'b00;  // SB
                3'b001: mem_size_reg = 2'b01;  // SH
                3'b010: mem_size_reg = 2'b10;  // SW
            endcase
        end
    end

    assign alu_ctrl = alu_ctrl_reg;
    assign mem_size = mem_size_reg;

endmodule