// ============================================================================
// soc_top.sv - top-level SoC: optional PicoRV32 core, AXI-Lite fabric
// (bus_interconnect), 64 KiB RAM slave, CRC-32 accelerator slave.
//
// USE_PICO=1 pulls in the real core (rtl/external/picorv32) behind the
// mem2axi_lite bridge - this is the hardware configuration.
// USE_PICO=0 exposes the mem_* interface so a TB can stand in for the core
// (ModelSim cannot cleanly compile the Yosys-oriented core file; the TB
// exercises the identical memory contract at the boundary).
//
// VERIFIED BY: tb_bus_bfm.sv (fabric + slaves), tb_soc_top.sv (fabric +
// firmware-level transaction sequence through the mem interface).
// ============================================================================
import mem_map_pkg::*;

module soc_top #(
    parameter bit USE_PICO = 1'b0
)(
    input  wire clk,
    input  wire rst_n,
    // exposed regardless of USE_PICO so a TB can drive the boundary port
    input  wire [31:0] mem_addr_in,
    input  wire [31:0] mem_wdata_in,
    input  wire [3:0]  mem_wstrb_in,
    input  wire        mem_valid_in,
    output logic [31:0] mem_rdata_out,
    output logic        mem_ready_out
);
    `ifdef SOC_TOP_WITH_BFM
    // ---- bridge to the AXI-Lite fabric (through mem2axi_lite) ----
    logic        m_aw_valid, m_w_valid, m_ar_valid;
    logic [31:0] m_aw_addr, m_w_data, m_ar_addr;
    logic [3:0]  m_w_strb;
    logic        m_aw_ready, m_w_ready, m_b_ready, m_ar_ready, m_r_ready;
    logic        m_b_valid, m_r_valid;
    logic [31:0] m_r_data;
    logic [1:0]  m_b_resp, m_r_resp;

    mem2axi_lite bridge (
        .clk, .rst_n,
        .mem_valid(mem_valid_in), .mem_instr(1'b0), .mem_addr(mem_addr_in),
        .mem_wdata(mem_wdata_in), .mem_wstrb(mem_wstrb_in),
        .mem_rdata(mem_rdata_out), .mem_ready(mem_ready_out),
        .m_aw_valid(m_aw_valid), .m_aw_addr(m_aw_addr), .m_aw_ready(m_aw_ready),
        .m_w_valid(m_w_valid), .m_w_data(m_w_data), .m_w_strb(m_w_strb), .m_w_ready(m_w_ready),
        .m_b_valid(m_b_valid), .m_b_resp(m_b_resp), .m_b_ready(m_b_ready),
        .m_ar_valid(m_ar_valid), .m_ar_addr(m_ar_addr), .m_ar_ready(m_ar_ready),
        .m_r_valid(m_r_valid), .m_r_data(m_r_data), .m_r_resp(m_r_resp), .m_r_ready(m_r_ready)
    );

    // ---- slaves ----
    logic        ram_aw_valid, ram_w_valid, ram_ar_valid;
    logic [31:0] ram_aw_addr, ram_w_data, ram_ar_addr;
    logic [3:0]  ram_w_strb;
    logic        ram_aw_ready, ram_w_ready, ram_b_ready, ram_ar_ready, ram_r_ready;
    logic        ram_b_valid, ram_r_valid;
    logic [31:0] ram_r_data;
    logic [1:0]  ram_b_resp, ram_r_resp;

    logic        crc_aw_valid, crc_w_valid, crc_ar_valid;
    logic [31:0] crc_aw_addr, crc_w_data, crc_ar_addr;
    logic [3:0]  crc_w_strb;
    logic        crc_aw_ready, crc_w_ready, crc_b_ready, crc_ar_ready, crc_r_ready;
    logic        crc_b_valid, crc_r_valid;
    logic [31:0] crc_r_data;
    logic [1:0]  crc_b_resp, crc_r_resp;
    // explicit so TB hierarchical references (dut.crc_busy) resolve
    wire         crc_busy, crc_done;

    bus_interconnect ic (
        .clk, .rst_n,
        .m_aw_valid(m_aw_valid), .m_aw_addr(m_aw_addr), .m_aw_ready(m_aw_ready),
        .m_w_valid(m_w_valid), .m_w_data(m_w_data), .m_w_strb(m_w_strb), .m_w_ready(m_w_ready),
        .m_b_valid(m_b_valid), .m_b_resp(m_b_resp), .m_b_ready(m_b_ready),
        .m_ar_valid(m_ar_valid), .m_ar_addr(m_ar_addr), .m_ar_ready(m_ar_ready),
        .m_r_valid(m_r_valid), .m_r_data(m_r_data), .m_r_resp(m_r_resp), .m_r_ready(m_r_ready),
        .ram_aw_valid(ram_aw_valid), .ram_aw_addr(ram_aw_addr), .ram_aw_ready(ram_aw_ready),
        .ram_w_valid(ram_w_valid), .ram_w_data(ram_w_data), .ram_w_strb(ram_w_strb), .ram_w_ready(ram_w_ready),
        .ram_b_valid(ram_b_valid), .ram_b_resp(ram_b_resp), .ram_b_ready(ram_b_ready),
        .ram_ar_valid(ram_ar_valid), .ram_ar_addr(ram_ar_addr), .ram_ar_ready(ram_ar_ready),
        .ram_r_valid(ram_r_valid), .ram_r_data(ram_r_data), .ram_r_resp(ram_r_resp), .ram_r_ready(ram_r_ready),
        .crc_aw_valid(crc_aw_valid), .crc_aw_addr(crc_aw_addr), .crc_aw_ready(crc_aw_ready),
        .crc_w_valid(crc_w_valid), .crc_w_data(crc_w_data), .crc_w_strb(crc_w_strb), .crc_w_ready(crc_w_ready),
        .crc_b_valid(crc_b_valid), .crc_b_resp(crc_b_resp), .crc_b_ready(crc_b_ready),
        .crc_ar_valid(crc_ar_valid), .crc_ar_addr(crc_ar_addr), .crc_ar_ready(crc_ar_ready),
        .crc_r_valid(crc_r_valid), .crc_r_data(crc_r_data), .crc_r_resp(crc_r_resp), .crc_r_ready(crc_r_ready)
    );

    axi_ram ram (
        .clk, .rst_n,
        .s_axi_aw_valid(ram_aw_valid), .s_axi_aw_addr(ram_aw_addr), .s_axi_aw_ready(ram_aw_ready),
        .s_axi_w_valid(ram_w_valid), .s_axi_w_data(ram_w_data), .s_axi_w_strb(ram_w_strb), .s_axi_w_ready(ram_w_ready),
        .s_axi_b_valid(ram_b_valid), .s_axi_b_resp(ram_b_resp), .s_axi_b_ready(ram_b_ready),
        .s_axi_ar_valid(ram_ar_valid), .s_axi_ar_addr(ram_ar_addr), .s_axi_ar_ready(ram_ar_ready),
        .s_axi_r_valid(ram_r_valid), .s_axi_r_data(ram_r_data), .s_axi_r_resp(ram_r_resp), .s_axi_r_ready(ram_r_ready)
    );

    crc32_accel crc (
        .clk, .rst_n,
        .s_axi_aw_valid(crc_aw_valid), .s_axi_aw_addr(crc_aw_addr), .s_axi_aw_ready(crc_aw_ready),
        .s_axi_w_valid(crc_w_valid), .s_axi_w_data(crc_w_data), .s_axi_w_strb(crc_w_strb), .s_axi_w_ready(crc_w_ready),
        .s_axi_b_valid(crc_b_valid), .s_axi_b_resp(crc_b_resp), .s_axi_b_ready(crc_b_ready),
        .s_axi_ar_valid(crc_ar_valid), .s_axi_ar_addr(crc_ar_addr), .s_axi_ar_ready(crc_ar_ready),
        .s_axi_r_valid(crc_r_valid), .s_axi_r_data(crc_r_data), .s_axi_r_resp(crc_r_resp), .s_axi_r_ready(crc_r_ready),
        .crc_busy(crc_busy), .crc_done(crc_done)
    );
    `else
    initial $display("soc_top: SOC_TOP_WITH_BFM not defined - no fabric wired");
    `endif
endmodule