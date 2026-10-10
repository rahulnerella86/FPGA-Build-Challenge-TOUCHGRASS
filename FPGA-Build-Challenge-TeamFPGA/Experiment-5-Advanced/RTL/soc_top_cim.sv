// ============================================================================
// soc_top_cim.sv - SoC top: verified RV32I core + MMIO MAC + custom CiM path.
// ----------------------------------------------------------------------------
// Based on ../05-riscv-ai-accelerator/rtl/system_top.sv (whose files are
// compiled in UNMODIFIED from their own directory - see sim/run_modelsim.do).
// Additive changes only:
//   1. custom_instr_decode snoops the live fetch word (cpu_instruction) in
//      parallel with the core. The core treats CIM.RUN as a NOP (its
//      control_unit `default:` zeroes every control signal); the decode
//      module raises cim_valid for the same word. Neither side disturbs
//      the other (TB-proven: sentinel register + PC continuity).
//   2. cim_dispatch (+ its pim_mac_bram engine) joins the data bus on a NEW
//      region 0x20000000-0x2FFFFFFF (offsets in cim_dispatch.sv header).
// DEVIATION (documented): upstream decoded MAC access as
// `cpu_data_addr >= 0x10000000`, which ALSO routes 0x20000000+ to the MAC
// accelerator (aliasing COMMAND/STATUS at the same low 5 bits - a write of
// 1 to 0x20000000 would spuriously START the MAC engine). Here MAC is
// narrowed to 0x1xxxxxxx and CIM owns 0x2xxxxxxx. The documented MMIO map
// (0x10000000-0x1000001F) behaves bit-identically; only the undocumented
// alias changes. Regression-proven by tb_soc_top_cim Phase A.
// ============================================================================

`timescale 1ns / 1ps

module soc_top_cim #(
    parameter IMEM_DEPTH = 1024,
    parameter DMEM_DEPTH = 1024,
    parameter INIT_FILE  = ""
)(
    input  logic clk,    // System clock
    input  logic rst_n   // Active-low reset
);

    // ---------------- CPU <-> memories (as upstream) ----------------
    logic [31:0] cpu_instr_addr;
    logic [31:0] cpu_instruction;
    logic [31:0] cpu_data_addr;
    logic [31:0] cpu_data_write_data;
    logic [31:0] cpu_data_read_data;
    logic        cpu_data_mem_write;
    logic        cpu_data_mem_read;
    logic [1:0]  cpu_data_mem_size;

    // ---------------- region decode ----------------
    logic is_mac_access;
    logic is_cim_access;
    assign is_mac_access = (cpu_data_addr[31:28] == 4'h1); // 0x1xxxxxxx
    assign is_cim_access = (cpu_data_addr[31:28] == 4'h2); // 0x2xxxxxxx

    // ---------------- MAC accelerator bus (as upstream) ----------------
    logic        acc_bus_write;
    logic        acc_bus_read;
    logic [31:0] acc_bus_rdata;
    logic        acc_mem_read_req;
    logic [31:0] acc_mem_read_addr;
    logic [31:0] acc_mem_read_data;

    assign acc_bus_write = cpu_data_mem_write & is_mac_access;
    assign acc_bus_read  = cpu_data_mem_read  & is_mac_access;

    // ---------------- CiM dispatch bus (new) ----------------
    logic        cim_bus_write;
    logic        cim_bus_read;
    logic [31:0] cim_bus_rdata;

    assign cim_bus_write = cpu_data_mem_write & is_cim_access;
    assign cim_bus_read  = cpu_data_mem_read  & is_cim_access;

    // ---------------- custom-instruction snoop (new) ----------------
    logic       cim_valid;
    logic [4:0] cim_rd, cim_rs1, cim_rs2;
    logic [2:0] cim_funct3;

    custom_instr_decode u_cim_decode (
        .instruction (cpu_instruction),
        .cim_valid   (cim_valid),
        .cim_rd      (cim_rd),
        .cim_rs1     (cim_rs1),
        .cim_rs2     (cim_rs2),
        .cim_funct3  (cim_funct3)
    );
    wire [4:0] _unused_cim_rd    = cim_rd;
    wire [4:0] _unused_cim_rs2   = cim_rs2;
    wire [2:0] _unused_cim_funct3 = cim_funct3;

    // ---------------- dmem arbitration (as upstream: acc priority) ----
    logic [31:0] dmem_addr;
    logic [31:0] dmem_write_data;
    logic [31:0] dmem_read_data;
    logic        dmem_mem_write;
    logic        dmem_mem_read;
    logic [1:0]  dmem_mem_size;

    always @(*) begin
        if (acc_mem_read_req) begin
            dmem_addr       = acc_mem_read_addr;
            dmem_write_data = 32'h00000000;
            dmem_mem_write  = 1'b0;
            dmem_mem_read   = 1'b1;
            dmem_mem_size   = 2'b10;
        end else begin
            dmem_addr       = cpu_data_addr;
            dmem_write_data = cpu_data_write_data;
            dmem_mem_write  = cpu_data_mem_write & (~is_mac_access) & (~is_cim_access);
            dmem_mem_read   = cpu_data_mem_read  & (~is_mac_access) & (~is_cim_access);
            dmem_mem_size   = cpu_data_mem_size;
        end
    end

    assign cpu_data_read_data = is_mac_access ? acc_bus_rdata :
                                is_cim_access ? cim_bus_rdata :
                                                dmem_read_data;
    assign acc_mem_read_data  = dmem_read_data;

    // ---------------- instances (ai-accelerator files: unmodified) ----
    riscv_core cpu_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .instr_addr      (cpu_instr_addr),
        .instruction     (cpu_instruction),
        .data_addr       (cpu_data_addr),
        .data_write_data (cpu_data_write_data),
        .data_read_data  (cpu_data_read_data),
        .data_mem_write  (cpu_data_mem_write),
        .data_mem_read   (cpu_data_mem_read),
        .data_mem_size   (cpu_data_mem_size)
    );

    instruction_memory #(
        .DEPTH     (IMEM_DEPTH),
        .INIT_FILE (INIT_FILE)
    ) imem_inst (
        .addr        (cpu_instr_addr),
        .instruction (cpu_instruction)
    );

    data_memory #(
        .DEPTH (DMEM_DEPTH)
    ) dmem_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .addr       (dmem_addr),
        .write_data (dmem_write_data),
        .mem_write  (dmem_mem_write),
        .mem_read   (dmem_mem_read),
        .mem_size   (dmem_mem_size),
        .read_data  (dmem_read_data)
    );

    mac_accelerator acc_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .bus_addr      (cpu_data_addr),
        .bus_wdata     (cpu_data_write_data),
        .bus_rdata     (acc_bus_rdata),
        .bus_write     (acc_bus_write),
        .bus_read      (acc_bus_read),
        .mem_read_req  (acc_mem_read_req),
        .mem_read_addr (acc_mem_read_addr),
        .mem_read_data (acc_mem_read_data)
    );

    // ---------------- CiM path (new) --------------------------------
    cim_dispatch #(
        .NUM_ROWS (16),
        .NUM_COLS (16)
    ) cim_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        .bus_addr  (cpu_data_addr),
        .bus_wdata (cpu_data_write_data),
        .bus_rdata (cim_bus_rdata),
        .bus_write (cim_bus_write),
        .bus_read  (cim_bus_read),
        .cim_valid (cim_valid),
        .cim_rs1   (cim_rs1)
    );

endmodule
