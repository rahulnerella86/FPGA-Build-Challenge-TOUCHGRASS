// ============================================================================
// data_memory.sv - RV32I data memory (infers BRAM on FPGA).
// ============================================================================

`timescale 1ns / 1ps

module data_memory #(
    parameter int DEPTH = 1024  // 4KB default
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    input  wire        mem_write,
    input  wire        mem_read,
    input  wire [1:0]  mem_size,
    output wire [31:0] read_data
);

    localparam int ADDR_WIDTH = $clog2(DEPTH);

    // Memory array (infers block RAM)
    reg [31:0] mem [0:DEPTH-1];

    // Registered read (for BRAM inference)
    reg [31:0] read_reg;

    // Byte enables
    wire [3:0] byte_en = (mem_write && mem_size == 2'b00) ? 4'b0001 << addr[1:0] :
                          (mem_write && mem_size == 2'b01) ? (addr[1] ? 4'b0011 : 4'b1100) :
                          (mem_write) ? 4'b1111 : 4'b0000;

    // Combinational read (for single-cycle core)
    wire [31:0] mem_data = mem[addr[ADDR_WIDTH-1:0]];

    // Read data mux (byte/halfword access)
    wire [31:0] byte_data   = (addr[1:0] == 2'b00) ? {24'd0, mem_data[7:0]} :
                               (addr[1:0] == 2'b01) ? {24'd0, mem_data[15:8]} :
                               (addr[1:0] == 2'b10) ? {24'd0, mem_data[23:16]} :
                               {24'd0, mem_data[31:24]};
    wire [31:0] half_data   = (addr[1] == 1'b0) ? {16'd0, mem_data[15:0]} :
                               {16'd0, mem_data[31:16]};
    wire [31:0] sign_ext_byte = (addr[1:0] == 2'b00) ? {{24{mem_data[7]}}, mem_data[7:0]} :
                                 (addr[1:0] == 2'b01) ? {{24{mem_data[15]}}, mem_data[15:8]} :
                                 (addr[1:0] == 2'b10) ? {{24{mem_data[23]}}, mem_data[23:16]} :
                                 {{24{mem_data[31]}}, mem_data[31:24]};
    wire [31:0] sign_ext_half = (addr[1] == 1'b0) ? {{16{mem_data[15]}}, mem_data[15:0]} :
                                 {{16{mem_data[31]}}, mem_data[31:16]};

    assign read_data = mem_read ? 
                       (mem_size == 2'b00) ? sign_ext_byte :
                       (mem_size == 2'b01) ? sign_ext_half :
                       mem_data : 32'd0;

    // Write logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Optional: clear memory on reset
        end else if (mem_write) begin
            case (mem_size)
                2'b00: begin  // byte
                    if (addr[1:0] == 2'b00) mem[addr[ADDR_WIDTH-1:0]][7:0]   <= write_data[7:0];
                    if (addr[1:0] == 2'b01) mem[addr[ADDR_WIDTH-1:0]][15:8]  <= write_data[7:0];
                    if (addr[1:0] == 2'b10) mem[addr[ADDR_WIDTH-1:0]][23:16] <= write_data[7:0];
                    if (addr[1:0] == 2'b11) mem[addr[ADDR_WIDTH-1:0]][31:24] <= write_data[7:0];
                end
                2'b01: begin  // halfword
                    if (addr[1] == 1'b0)
                        mem[addr[ADDR_WIDTH-1:0]][15:0] <= write_data[15:0];
                    else
                        mem[addr[ADDR_WIDTH-1:0]][31:16] <= write_data[15:0];
                end
                2'b10: begin  // word
                    mem[addr[ADDR_WIDTH-1:0]] <= write_data;
                end
                default: ;
            endcase
        end
    end

endmodule