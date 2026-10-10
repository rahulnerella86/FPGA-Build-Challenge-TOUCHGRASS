// ============================================================================
// mac_accelerator.sv - MAC/MMIO accelerator for the AI accelerator SoC.
// ============================================================================
// Provides MAC (multiply-accumulate) operations via MMIO at 0x1xxxxxxx.
// Registers:
//   Offset 0x00: COMMAND (write 1 to start)
//   Offset 0x04: STATUS  (bit0=busy, bit1=done)
//   Offset 0x08: OP_A    (input A)
//   Offset 0x0C: OP_B    (input B)
//   Offset 0x10: RESULT  (output)
// ============================================================================

`timescale 1ns / 1ps

module mac_accelerator (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] bus_addr,
    input  wire [31:0] bus_wdata,
    output wire [31:0] bus_rdata,
    input  wire        bus_write,
    input  wire        bus_read,
    output wire        mem_read_req,
    output wire [31:0] mem_read_addr,
    input  wire [31:0] mem_read_data
);

    // MMIO offsets
    localparam int OFFSET_COMMAND = 8'h00;
    localparam int OFFSET_STATUS  = 8'h04;
    localparam int OFFSET_OP_A    = 8'h08;
    localparam int OFFSET_OP_B    = 8'h0C;
    localparam int OFFSET_RESULT  = 8'h10;

    // Decode offset from bus_addr (bits [7:0])
    wire [7:0] offset = bus_addr[7:0];

    // Internal access check (same as soc_top_cim: 0x1xxxxxxx)
    wire is_mac_access_internal = (bus_addr[31:28] == 4'h1);

    // Control FSM
    localparam S_IDLE  = 2'd0;
    localparam S_BUSY  = 2'd1;
    localparam S_DONE  = 2'd2;

    reg [1:0] state;
    reg       busy;
    reg       done;
    reg       start_pulse;
    reg [31:0] op_a;
    reg [31:0] op_b;
    reg [31:0] result;
    reg        command_reg;

    // Start command detection
    wire start_cmd = (bus_write && is_mac_access_internal && offset == OFFSET_COMMAND && bus_wdata == 32'd1);

    // Status register
    assign bus_rdata = (bus_read && is_mac_access_internal) ? 
        (offset == OFFSET_STATUS  ? {29'd0, done, busy, 2'd0} :
         offset == OFFSET_RESULT  ? result :
         offset == OFFSET_OP_A    ? op_a :
         offset == OFFSET_OP_B    ? op_b :
         offset == OFFSET_COMMAND ? 32'd0 :
         32'd0) : 32'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            busy        <= 1'b0;
            done        <= 1'b0;
            op_a        <= 32'd0;
            op_b        <= 32'd0;
            result      <= 32'd0;
            command_reg <= 1'b0;
        end else begin
            // Load operands on write
            if (bus_write && is_mac_access_internal) begin
                if (offset == OFFSET_OP_A) op_a <= bus_wdata;
                if (offset == OFFSET_OP_B) op_b <= bus_wdata;
            end

            case (state)
                S_IDLE: begin
                    if (start_cmd) begin
                        state  <= S_BUSY;
                        busy   <= 1'b1;
                        done   <= 1'b0;
                        result <= op_a * op_b;
                    end
                end
                S_BUSY: begin
                    state <= S_DONE;
                    busy  <= 1'b0;
                    done  <= 1'b1;
                end
                S_DONE: begin
                    if (bus_write && is_mac_access_internal && 
                        offset == OFFSET_COMMAND && bus_wdata == 32'd0) begin
                        state  <= S_IDLE;
                        done   <= 1'b0;
                    end
                end
            endcase
        end
    end

    assign mem_read_req  = 1'b0;
    assign mem_read_addr = 32'd0;

endmodule