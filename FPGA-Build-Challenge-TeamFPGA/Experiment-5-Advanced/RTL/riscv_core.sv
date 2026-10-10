// ============================================================================
// riscv_core.sv - Single-cycle RV32I RISC-V core.
// ============================================================================

`timescale 1ns / 1ps

module riscv_core (
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] instr_addr,
    input  wire [31:0] instruction,
    output wire [31:0] data_addr,
    output wire [31:0] data_write_data,
    input  wire [31:0] data_read_data,
    output wire        data_mem_write,
    output wire        data_mem_read,
    output wire [1:0]  data_mem_size
);

    wire [31:0] pc;
    wire [31:0] pc_next;
    wire [31:0] instr;
    wire [31:0] rs1_val, rs2_val;
    wire [31:0] alu_result;
    wire        zero;
    wire        reg_write;
    wire        alu_src_a, alu_src_b;
    wire        mem_to_reg;
    wire        branch, jump, jump_reg;
    wire        mem_read, mem_write;
    wire [4:0]  alu_ctrl;
    wire [1:0]  mem_size;
    wire [31:0] branch_target;
    wire        take_branch;
    wire        is_branch, is_jump, is_jalr;
    wire [31:0] jal_target, jalr_target;

    // PC instance (exposed for testbench hierarchical reference)
    pc pc_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .pc_next  (pc_next),
        .pc_reg   (pc)
    );

    assign instr_addr = pc;
    assign instr      = instruction;

    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd     = instr[11:7];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];

    // Register file instance (exposed for testbench hierarchical reference)
    register_file reg_file_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .reg_write_en (reg_write && rd != 5'd0),
        .read_reg1    (rs1),
        .read_reg2    (rs2),
        .write_reg    (rd),
        .write_data   (mem_to_reg ? data_read_data : alu_result),
        .read_data1   (rs1_val),
        .read_data2   (rs2_val)
    );

    control_unit u_control (
        .instruction  (instr),
        .zero         (zero),
        .reg_write    (reg_write),
        .alu_src_a    (alu_src_a),
        .alu_src_b    (alu_src_b),
        .mem_to_reg   (mem_to_reg),
        .branch       (branch),
        .jump         (jump),
        .jump_reg     (jump_reg),
        .mem_read     (mem_read),
        .mem_write    (mem_write),
        .alu_ctrl     (alu_ctrl),
        .mem_size     (mem_size)
    );

    branch_unit u_branch (
        .instr         (instr),
        .rs1_val       (rs1_val),
        .rs2_val       (rs2_val),
        .pc            (pc),
        .branch_target (branch_target),
        .take_branch   (take_branch),
        .is_branch     (is_branch),
        .is_jal        (is_jump),
        .is_jalr       (is_jalr),
        .jal_target    (jal_target),
        .jalr_target   (jalr_target)
    );

    alu u_alu (
        .a             (alu_src_a ? pc : rs1_val),
        .b             (alu_src_b ? instr[31:12] : rs2_val),
        .alu_ctrl      (alu_ctrl),
        .result        (alu_result),
        .zero          (zero)
    );

    wire [31:0] branch_or_jump_target;
    assign branch_or_jump_target = take_branch ? branch_target :
                                   (is_jump && !is_jalr) ? jal_target :
                                   (is_jalr) ? jalr_target : pc;

    assign pc_next = branch_or_jump_target + 32'd4;

    assign data_addr       = alu_result;
    assign data_write_data = rs2_val;
    assign data_mem_write  = mem_write;
    assign data_mem_read   = mem_read;
    assign data_mem_size   = mem_size;

endmodule