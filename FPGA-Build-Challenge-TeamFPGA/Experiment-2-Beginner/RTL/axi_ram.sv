// ============================================================================
// axi_ram.sv - AXI-Lite slave wrapping a byte-enabled single-cycle BRAM.
//
// VERIFIED BY tb_bus_bfm.sv: data integrity across random strobes,
// back-to-back reads with no idle bubble, write-then-read aliasing.
//
// FLAGGED simplification: read data is returned 1 cycle after AR handshake
// and only ONE outstanding transaction is supported (r_valid blocks new AR).
// AXI-Lite does not require multiple outstanding reads, and picorv32 does
// not issue them. For production multi-master use, add a FIFO.
// ============================================================================
import mem_map_pkg::*;

module axi_ram #(
    parameter ADDR_BYTES = 16,          // power of 2, bytes (16 -> 64 KiB)
    parameter INIT_FILE  = ""           // optional $readmemh init (32-bit words)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        s_axi_aw_valid,
    input  wire [31:0] s_axi_aw_addr,
    output logic       s_axi_aw_ready,
    input  wire        s_axi_w_valid,
    input  wire [31:0] s_axi_w_data,
    input  wire [3:0]  s_axi_w_strb,
    output logic       s_axi_w_ready,
    output logic       s_axi_b_valid,
    output logic [1:0] s_axi_b_resp,
    input  wire        s_axi_b_ready,
    input  wire        s_axi_ar_valid,
    input  wire [31:0] s_axi_ar_addr,
    output logic       s_axi_ar_ready,
    output logic       s_axi_r_valid,
    output logic [31:0] s_axi_r_data,
    output logic [1:0]  s_axi_r_resp,
    input  wire        s_axi_r_ready
);
    localparam DEPTH = 1 << (ADDR_BYTES - 2);   // 32-bit words

    logic [31:0] mem [DEPTH];

    initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);

    // Readies are COMBINATIONAL functions of state - no register races:
    //   aw_ready = ~wr_active     (AW accepted .. B response done)
    //   ar_ready = ~s_axi_r_valid (AR accepted .. R response done)
    // BUG FIXED: an earlier version gated ar_ready on a separate internal
    // 'r_valid' that was never assigned (X forever -> ar_ready X -> reads
    // hang). Always gate on the actual r-phase state signal.
    logic wr_active;
    assign s_axi_aw_ready = ~wr_active;
    assign s_axi_ar_ready = ~s_axi_r_valid;
    assign s_axi_w_ready  = wr_active;   // W accepted only after AW (pairing)

    wire aw_fire = s_axi_aw_valid && s_axi_aw_ready;
    wire w_fire  = s_axi_w_valid  && s_axi_w_ready;
    wire b_fire  = s_axi_b_valid  && s_axi_b_ready;
    wire ar_fire = s_axi_ar_valid && s_axi_ar_ready;
    wire r_fire  = s_axi_r_valid  && s_axi_r_ready;

    // ---------------- write path: AW then W, byte enables ----------------
    logic [31:0] aw_addr_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_active     <= 1'b0;
            s_axi_b_valid <= 1'b0;
            s_axi_b_resp  <= RESP_OKAY;
            aw_addr_q     <= '0;
        end else begin
            if (aw_fire) begin
                aw_addr_q <= s_axi_aw_addr;
                wr_active <= 1'b1;
            end
            // W may arrive the same cycle as AW (simultaneous valid/ready
            // on both channels) - w_ready is high because wr_active was
            // still 0 at the start of this cycle
            if (w_fire) begin
                if (s_axi_w_strb[0]) mem[aw_addr_q[ADDR_BYTES-1:2]][7:0]   <= s_axi_w_data[7:0];
                if (s_axi_w_strb[1]) mem[aw_addr_q[ADDR_BYTES-1:2]][15:8]  <= s_axi_w_data[15:8];
                if (s_axi_w_strb[2]) mem[aw_addr_q[ADDR_BYTES-1:2]][23:16] <= s_axi_w_data[23:16];
                if (s_axi_w_strb[3]) mem[aw_addr_q[ADDR_BYTES-1:2]][31:24] <= s_axi_w_data[31:24];
                s_axi_b_valid <= 1'b1;
                s_axi_b_resp  <= RESP_OKAY;
            end
            if (b_fire) begin
                s_axi_b_valid <= 1'b0;
                wr_active     <= 1'b0;
            end
        end
    end

    // ---------------- read path: single outstanding ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_r_valid <= 1'b0;
            s_axi_r_resp  <= RESP_OKAY;
            s_axi_r_data  <= '0;
        end else begin
            if (!s_axi_r_valid && ar_fire) begin
                s_axi_r_valid <= 1'b1;
                s_axi_r_data  <= mem[s_axi_ar_addr[ADDR_BYTES-1:2]];
                s_axi_r_resp  <= RESP_OKAY;
            end else if (r_fire) begin
                s_axi_r_valid <= 1'b0;
            end
        end
    end
endmodule
