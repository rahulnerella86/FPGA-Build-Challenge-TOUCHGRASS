// ============================================================================
// mem_map_pkg.sv - Project 2 memory map, all addresses as named parameters.
// NO magic numbers anywhere else - every module imports this package.
// ============================================================================
package mem_map_pkg;

    // ---- AXI-Lite response codes ----
    typedef logic [1:0] resp_t;
    localparam resp_t RESP_OKAY   = 2'b00;
    localparam resp_t RESP_EXOKAY = 2'b01;
    localparam resp_t RESP_SLVERR = 2'b10;
    localparam resp_t RESP_DECERR = 2'b11;

    // ---- Region 0: data RAM (AXI-Lite BRAM slave) ----
    localparam logic [31:0] RAM_BASE = 32'h0000_0000;
    localparam logic [31:0] RAM_SPAN = 32'h0001_0000;   // 64 KiB

    // ---- Region 1: CRC-32 accelerator registers ----
    localparam logic [31:0] CRC_BASE   = 32'h1000_0000;
    localparam logic [31:0] CRC_DATA   = 32'h1000_0000; // W: push strobed bytes into CRC
    localparam logic [31:0] CRC_CTRL   = 32'h1000_0004; // W: ANY write resets CRC to init
    localparam logic [31:0] CRC_RESULT = 32'h1000_0008; // R: current CRC value
    localparam logic [31:0] CRC_STATUS = 32'h1000_000C; // R: bit0=busy, bit1=done

    // ---- Region 2: debug output port (TB monitor / future LED bridge) ----
    localparam logic [31:0] OUT_PORT = 32'h8000_0000;

    // ---- Address decode helper: returns 2-bit slave id ----
    // 0 = RAM, 1 = CRC, 2 = OUT_PORT, 3 = decode error
    function automatic logic [1:0] decode(logic [31:0] addr);
        if (addr >= RAM_BASE && addr < RAM_BASE + RAM_SPAN)       return 2'd0;
        else if (addr >= CRC_BASE && addr < CRC_BASE + 32'h1000)  return 2'd1;
        else if (addr == OUT_PORT)                                return 2'd2;
        else                                                      return 2'd3;
    endfunction

endpackage
