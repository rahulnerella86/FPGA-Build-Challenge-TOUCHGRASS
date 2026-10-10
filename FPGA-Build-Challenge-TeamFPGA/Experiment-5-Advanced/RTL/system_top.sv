// ============================================================================
// system_top.sv - SoC top level for the RV32I AI accelerator (base + MAC/MMIO).
// ============================================================================
// Base system used by 05-riscv-ai-accelerator. The CiM project
// (05-riscv-sram-cim-accelerator) instantiates soc_top_cim.sv instead, which
// reuses these same RTL blocks with an extra cim_dispatch path.

`timescale 1ns / 1ps

module system_top #(
    parameter int    IMEM_DEPTH = 1024,
    parameter int    DMEM_DEPTH = 1024,
    parameter string INIT_FILE  = ""
)(
    input  wire clk,
    input  wire rst_n
);

    // ---------------- CPU <-> memory buses ---------------------------------
    wire [31:0] cpu_instr_addr;
    wire [31:0] cpu_instruction;
    wire [31:0] cpu_data_addr;
    wire [31:0] cpu_data_write_data;
    wire [31:0] cpu_data_read_data;
    wire        cpu_data_mem_write;
    wire        cpu_data_mem_read;
    wire [1:0]  cpu_data_mem_size;

    // ---------------- accelerator (MAC) bus --------------------------------
    wire        acc_bus_write;
    wire        acc_bus_read;
    wire [31:0] acc_bus_rdata;
    wire        acc_mem_read_req;
    wire [31:0] acc_mem_read_addr;
    wire [31:0] acc_mem_read_data;

    // ---------------- region decode ---------------------------------------
    // MAC/MMIO accelerator occupies 0x1xxx_xxxx; everything else is dmem.
    wire is_acc_region;
    assign is_acc_region = (cpu_data_addr[31:28] == 4'h1);

    assign acc_bus_write = cpu_data_mem_write & is_acc_region;
    assign acc_bus_read  = cpu_data_mem_read  & is_acc_region;

    // dmem drives the read data bus for normal loads
    wire [31:0] dmem_read_data;
    assign cpu_data_read_data = is_acc_region ? acc_bus_rdata : dmem_read_data;

    // The accelerator may source operands straight out of dmem
    assign acc_mem_read_data = dmem_read_data;

    // ---------------- instances -------------------------------------------
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
        .addr       (cpu_data_addr),
        .write_data (cpu_data_write_data),
        .mem_write  (cpu_data_mem_write & ~is_acc_region),
        .mem_read   (cpu_data_mem_read  & ~is_acc_region),
        .mem_size   (cpu_data_mem_size),
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

endmodule
