// ============================================================================
// crc32_accel.sv - CRC-32 (Ethernet, reflected, poly 0xEDB88320) accelerator
// with an AXI-Lite slave register interface.
//
// WHAT IS VERIFIED (tb_bus_bfm.sv):
//   * Golden known-answer: feeding "123456789" must produce 0xCBF43926
//     (published constant, tool-independent).
//   * wstrb handling: only strobed bytes are folded into the CRC.
//   * Write back-pressure: w_ready held low during the ~36-cycle computation;
//     the AXI write response is issued only AFTER processing completes.
//   * Reads of RESULT/STATUS never hang.
//
// CONFIDENCE: HIGH - conventional xor-shift CRC, golden-constant checkable.
// FLAGGED tradeoff: bitwise folding (8 cycles/byte) instead of a 256-entry
// LUT table (1 cycle/byte). Tableless = provably identical algorithm, tiny;
// swap a table in later - the register interface does not change.
//
// DATA MODEL: crc_q holds the RUNNING pre-inversion register. The standard
// CRC-32 final inversion (~crc) is applied at RESULT read time. This is a
// deliberate choice: a message spread across MULTIPLE DATA writes (e.g.
// "1234","5678","9") must not have ~crc applied between writes, or the
// running state is corrupted. Cross-checked against Python in
// tools/crc_ref.py (exact 0xCBF43926 match).
// ============================================================================
import mem_map_pkg::*;

module crc32_accel (
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
    input  wire        s_axi_r_ready,
    output wire        crc_busy,
    output wire        crc_done
);
    localparam logic [31:0] CRC_POLY = 32'hEDB8_8320;
    localparam logic [31:0] CRC_INIT = 32'hFFFF_FFFF;

    // ---------------- CRC datapath ----------------
    logic        crc_reset;     // CRC <= CRC_INIT
    logic        crc_load;      // CRC <= CRC ^ byte
    logic        crc_step;      // one xor-shift iteration
    logic [7:0]  crc_byte;
    logic [31:0] crc_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)          crc_q <= CRC_INIT;
        else if (crc_reset)  crc_q <= CRC_INIT;
        else if (crc_load)   crc_q <= crc_q ^ {24'b0, crc_byte};
        else if (crc_step)   crc_q <= crc_q[0] ? ((crc_q >> 1) ^ CRC_POLY)
                                               : (crc_q >> 1);
    end

    // ---------------- write channel FSM ----------------
    localparam W_IDLE  = 3'd0;  // waiting for AW (AW and W are serialized)
    localparam W_WAITW = 3'd1;  // AW accepted, waiting for W
    localparam W_PROC  = 3'd2;  // CRC engine folding bytes
    localparam W_RESP  = 3'd3;  // bvalid asserted
    localparam W_DRESET= 3'd4;  // executing CTRL reset (1 cycle)
    logic [2:0]  wstate;
    logic [1:0]  aw_sel;        // latched register offset [3:2]
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic [1:0]  byte_idx;
    logic [3:0]  bit_idx;       // 0 = load, 1..8 = shift steps
    logic        proc_active;

    assign proc_active = (wstate == W_PROC);
    assign crc_busy    = proc_active;
    assign crc_done    = ~proc_active;
    assign crc_reset   = (wstate == W_DRESET);
    assign crc_load    = (wstate == W_PROC) && (bit_idx == 0) && wstrb_q[byte_idx];
    assign crc_step    = (wstate == W_PROC) && (bit_idx != 0);
    assign crc_byte    = wdata_q >> (8 * byte_idx);

    wire aw_fire = s_axi_aw_valid && s_axi_aw_ready;
    wire w_fire  = s_axi_w_valid  && s_axi_w_ready;
    wire b_fire  = s_axi_b_valid  && s_axi_b_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wstate <= W_IDLE; aw_sel <= '0; wdata_q <= '0; wstrb_q <= '0;
            byte_idx <= '0; bit_idx <= '0;
            s_axi_aw_ready <= 1'b0; s_axi_w_ready <= 1'b0;
            s_axi_b_valid <= 1'b0;  s_axi_b_resp <= RESP_OKAY;
        end else begin
            case (wstate)
                W_IDLE: begin
                    s_axi_aw_ready <= 1'b1;
                    if (aw_fire) begin
                        aw_sel         <= s_axi_aw_addr[3:2];
                        s_axi_aw_ready <= 1'b0;
                        wstate         <= W_WAITW;
                    end
                end
                W_WAITW: begin
                    s_axi_w_ready <= 1'b1;
                    if (w_fire) begin
                        s_axi_w_ready <= 1'b0;
                        wdata_q <= s_axi_w_data;
                        wstrb_q <= s_axi_w_strb;
                        if (aw_sel == CRC_DATA[3:2] && |s_axi_w_strb) begin
                            byte_idx <= 2'd0;
                            bit_idx  <= 4'd0;
                            wstate   <= W_PROC;
                        end else if (aw_sel == CRC_CTRL[3:2]) begin
                            wstate <= W_DRESET;   // any write resets CRC
                        end else begin
                            wstate <= W_RESP;
                        end
                    end
                end
                W_DRESET: wstate <= W_RESP;
                W_PROC: begin
                    if (bit_idx == 4'd8) begin
                        bit_idx <= 4'd0;
                        if (byte_idx == 2'd3) wstate <= W_RESP;
                        else                  byte_idx <= byte_idx + 1;
                    end else begin
                        bit_idx <= bit_idx + 1;
                    end
                end
                W_RESP: begin
                    s_axi_b_valid <= 1'b1;
                    s_axi_b_resp  <= RESP_OKAY;
                    if (b_fire) begin
                        s_axi_b_valid <= 1'b0;
                        wstate        <= W_IDLE;
                    end
                end
                default: wstate <= W_IDLE;
            endcase
            // skip a non-strobed byte in one cycle (no CRC operation);
            // placed outside the case so it overrides the W_PROC state.
            // BUG FIXED (two rounds, both found by the golden '123456789'
            // -> 0xCBF43926 check in tb_bus_bfm P6):
            //  1. the case advanced bit_idx to 1 on the skip cycle, so the
            //     next strobed byte began at bit_idx=1 (shift) instead of 0
            //     (load) - wrong shift count.
            //  2. the original guard excluded byte_idx==3, so an UNSTROBED
            //     byte 3 fell through to the normal bit_idx 1..8 cycling,
            //     applying 8 spurious shifts of the running CRC.
            if (wstate == W_PROC && bit_idx == 4'd0 && !wstrb_q[byte_idx]) begin
                bit_idx <= 4'd0;   // stay in load phase
                if (byte_idx == 2'd3) wstate <= W_RESP;
                else                  byte_idx <= byte_idx + 1;
            end
        end
    end

    // ---------------- read channel FSM ----------------
    logic [1:0] r_sel_q;
    wire ar_fire = s_axi_ar_valid && s_axi_ar_ready;
    wire r_fire  = s_axi_r_valid  && s_axi_r_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_ar_ready <= 1'b0;
            s_axi_r_valid  <= 1'b0;
            s_axi_r_resp   <= RESP_OKAY;
            s_axi_r_data   <= '0;
            r_sel_q        <= '0;
        end else begin
            if (!s_axi_r_valid) begin
                s_axi_ar_ready <= 1'b1;
                if (ar_fire) begin
                    s_axi_ar_ready <= 1'b0;
                    r_sel_q        <= s_axi_ar_addr[3:2];
                    s_axi_r_valid  <= 1'b1;
                    case (s_axi_ar_addr[3:2])
                        // crc_q holds the RUNNING pre-inversion register.
                        // The standard CRC-32 final inversion (~crc) is
                        // applied HERE at read time: a message spread over
                        // multiple DATA writes must not be flipped between
                        // writes. Verified by P6/P7 and tools/crc_ref.py.
                        CRC_RESULT[3:2]: s_axi_r_data <= ~crc_q;
                        CRC_STATUS[3:2]: s_axi_r_data <= {30'b0, ~proc_active, proc_active};
                        default:         s_axi_r_data <= 32'hDEAD_C0DE;
                    endcase
                end
            end else if (r_fire) begin
                s_axi_r_valid <= 1'b0;
            end
        end
    end
endmodule
