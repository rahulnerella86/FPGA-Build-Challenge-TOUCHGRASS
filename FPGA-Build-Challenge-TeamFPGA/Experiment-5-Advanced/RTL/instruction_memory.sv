// ============================================================================
// instruction_memory.sv - RV32I instruction memory (infers BRAM).
// ============================================================================

`timescale 1ns / 1ps

module instruction_memory #(
    parameter int DEPTH   = 1024,   // 4KB default (1024 32-bit words)
    parameter string INIT_FILE = ""
)(
    input  wire [31:0] addr,
    output wire [31:0] instruction
);

    localparam int ADDR_WIDTH = $clog2(DEPTH);

    // Memory array
    reg [31:0] mem [0:DEPTH-1];

    // Initialize from file if provided (for firmware loading)
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem, 0, DEPTH-1);
        end
    end

    // Combinational read (aligned to word boundary)
    assign instruction = mem[addr[ADDR_WIDTH-1:2]];  // word-aligned access

endmodule