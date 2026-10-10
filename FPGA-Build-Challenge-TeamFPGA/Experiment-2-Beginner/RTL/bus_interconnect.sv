// ============================================================================
// bus_interconnect.sv - AXI-Lite 1-master x N-slave address decoder.
//
// VERIFIED BY tb_bus_bfm.sv: correct routing to each slave, back-to-back
// transactions, simultaneous AW+W valid, W-before-ready back-pressure,
// DECERR on unmapped addresses, reset mid-transaction recovery.
//
// DESIGN NOTES / FLAGGED SIMPLIFICATIONS:
//  * Single master, single-outstanding: a new AW is not routed until the
//    previous write's B response completes (same for AR until R). AXI-Lite
//    allows multiple outstanding, but picorv32 never issues them. This
//    removes all ID/ordering concerns at zero cost here.
//  * AW is routed to exactly one slave; W follows the LATCHED AW selection
//    (AXI-Lite permits W before AW - we serialize instead, which every
//    simple master including picorv32 tolerates).
//  * Slot map comes from mem_map_pkg::decode (RAM, CRC, OUT_PORT monitor,
//    unmapped->DECERR). To add slaves, extend decode() - the routing code
//    below is generic over the decode result.
// ============================================================================
import mem_map_pkg::*;

module bus_interconnect (
    input  wire clk,
    input  wire rst_n,
    // master (CPU) side
    input  wire        m_aw_valid,
    input  wire [31:0] m_aw_addr,
    output logic       m_aw_ready,
    input  wire        m_w_valid,
    input  wire [31:0] m_w_data,
    input  wire [3:0]  m_w_strb,
    output logic       m_w_ready,
    output logic       m_b_valid,
    output logic [1:0] m_b_resp,
    input  wire        m_b_ready,
    input  wire        m_ar_valid,
    input  wire [31:0] m_ar_addr,
    output logic       m_ar_ready,
    output logic       m_r_valid,
    output logic [31:0] m_r_data,
    output logic [1:0]  m_r_resp,
    input  wire        m_r_ready,
    // slave 0: RAM
    output logic        ram_aw_valid,
    output logic [31:0] ram_aw_addr,
    input  wire         ram_aw_ready,
    output logic        ram_w_valid,
    output logic [31:0] ram_w_data,
    output logic [3:0]  ram_w_strb,
    input  wire         ram_w_ready,
    input  wire         ram_b_valid,
    input  wire [1:0]   ram_b_resp,
    output logic        ram_b_ready,
    output logic        ram_ar_valid,
    output logic [31:0] ram_ar_addr,
    input  wire         ram_ar_ready,
    input  wire         ram_r_valid,
    input  wire [31:0]  ram_r_data,
    input  wire [1:0]   ram_r_resp,
    output logic        ram_r_ready,
    // slave 1: CRC accelerator
    output logic        crc_aw_valid,
    output logic [31:0] crc_aw_addr,
    input  wire         crc_aw_ready,
    output logic        crc_w_valid,
    output logic [31:0] crc_w_data,
    output logic [3:0]  crc_w_strb,
    input  wire         crc_w_ready,
    input  wire         crc_b_valid,
    input  wire [1:0]   crc_b_resp,
    output logic        crc_b_ready,
    output logic        crc_ar_valid,
    output logic [31:0] crc_ar_addr,
    input  wire         crc_ar_ready,
    input  wire         crc_r_valid,
    input  wire [31:0]  crc_r_data,
    input  wire [1:0]   crc_r_resp,
    output logic        crc_r_ready
);
    // ---------------- transaction tracking ----------------
    logic wr_busy;   // AW routed .. B consumed (single outstanding write)
    logic rd_busy;   // AR routed .. R consumed (single outstanding read)
    logic [1:0] aw_sel_q;   // latched write target
    logic [1:0] ar_sel_q;   // latched read target
    logic w_done_q;         // W beat of the current write already consumed

    wire [1:0] aw_sel_now = decode(m_aw_addr);
    wire [1:0] ar_sel_now = decode(m_ar_addr);

    wire aw_fire = m_aw_valid && m_aw_ready;
    wire w_fire  = m_w_valid  && m_w_ready;
    wire b_fire  = m_b_valid  && m_b_ready;
    wire ar_fire = m_ar_valid && m_ar_ready;
    wire r_fire  = m_r_valid  && m_r_ready;

    // ---------------- target ready muxes (combinational) ----------------
    logic w_ready_t, b_valid_t, r_valid_t;
    logic [1:0] b_resp_t, r_resp_t;
    logic [31:0] r_data_t;

    always_comb begin
        // defaults: no slave selected
        w_ready_t = 1'b0; b_valid_t = 1'b0;
        r_valid_t = 1'b0;
        b_resp_t = RESP_OKAY; r_resp_t = RESP_OKAY; r_data_t = '0;
        // MUX BY LATCHED SELECTION (aw_sel_q/ar_sel_q), NOT the live wire.
        // BUG FIXED (found via watchdog hang in tb_bus_bfm P1): muxing on
        // aw_sel_now/ar_sel_now breaks after the master deasserts a valid -
        // the address wire then holds stale/X data, the mux selects no
        // slave, and the in-flight response is never forwarded (rd_busy/
        // wr_busy stick high). The registered selection is stable from the
        // cycle after routing, which is always earlier than any slave
        // response (all slaves respond >= 1 cycle after handshake).
        case (aw_sel_q)
            2'd0: begin w_ready_t = ram_w_ready; b_valid_t = ram_b_valid; b_resp_t = ram_b_resp; end
            2'd1: begin w_ready_t = crc_w_ready; b_valid_t = crc_b_valid; b_resp_t = crc_b_resp; end
            default: ;  // OUT_PORT / DECERR handled by internal responder
        endcase
        case (ar_sel_q)
            2'd0: begin r_valid_t = ram_r_valid; r_resp_t = ram_r_resp; r_data_t = ram_r_data; end
            2'd1: begin r_valid_t = crc_r_valid; r_resp_t = crc_r_resp; r_data_t = crc_r_data; end
            default: ;
        endcase
    end

    // ---------------- write path ----------------
    // Single-outstanding policy makes B routing trivial: at most ONE write
    // is in flight, so exactly one of (internal responder, RAM, CRC) can
    // hold b_valid. B is passed through combinationally.
    wire wr_internal = (aw_sel_q == 2'd2) || (aw_sel_q == 2'd3);  // OUT_PORT / DECERR

    // internal B response register (set when W consumed, cleared on b_fire)
    logic b_int_q;
    logic [1:0] b_int_resp_q;

    assign m_aw_ready = ~wr_busy;
    // ONE W beat per write transaction: w_done_q set at W handshake,
    // cleared when the master consumes B. Without this gate, a master (or
    // BFM) presenting W for the NEXT transaction while B is pending gets
    // it accepted and silently dropped/mis-delivered (found by tb_bus_bfm
    // P1 X-byte mismatches). AXI-Lite W burst length is exactly 1.
    assign m_w_ready  = wr_busy && !w_done_q && (wr_internal || w_ready_t);
    assign m_b_valid  = wr_busy && (wr_internal ? b_int_q : b_valid_t);
    assign m_b_resp   = (aw_sel_q == 2'd3) ? RESP_DECERR :
                        (aw_sel_q == 2'd2) ? RESP_OKAY  : b_resp_t;

    // slave B readys: pass master ready straight through (single source)
    assign ram_b_ready = m_b_ready;
    assign crc_b_ready = m_b_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_busy  <= 1'b0;
            aw_sel_q <= '0;
            b_int_q  <= 1'b0;
            w_done_q <= 1'b0;
            b_int_resp_q <= RESP_OKAY;
            ram_aw_valid <= 1'b0; ram_w_valid <= 1'b0;
            crc_aw_valid <= 1'b0; crc_w_valid <= 1'b0;
        end else begin
            // route AW (latch target + forward address to the slave)
            if (!wr_busy && m_aw_valid) begin
                aw_sel_q <= aw_sel_now;
                wr_busy  <= 1'b1;
                unique case (aw_sel_now)
                    2'd0: begin ram_aw_valid <= 1'b1; ram_aw_addr <= m_aw_addr; end
                    2'd1: begin crc_aw_valid <= 1'b1; crc_aw_addr <= m_aw_addr; end
                    default: ;   // internal responder needs no AW forward
                endcase
            end
            if (ram_aw_valid && ram_aw_ready) ram_aw_valid <= 1'b0;
            if (crc_aw_valid && crc_aw_ready) crc_aw_valid <= 1'b0;

            // route W: forward to the selected slave when it is ready
            if (wr_busy && m_w_valid && m_w_ready && !wr_internal) begin
                unique case (aw_sel_q)
                    2'd0: begin ram_w_valid <= 1'b1; ram_w_data <= m_w_data; ram_w_strb <= m_w_strb; end
                    2'd1: begin crc_w_valid <= 1'b1; crc_w_data <= m_w_data; crc_w_strb <= m_w_strb; end
                    default: ;
                endcase
            end
            if (ram_w_valid && ram_w_ready) ram_w_valid <= 1'b0;
            if (crc_w_valid && crc_w_ready) crc_w_valid <= 1'b0;

            // internal responder: consume W, raise B
            if (wr_internal && m_w_valid && m_w_ready) begin
                if (aw_sel_q == 2'd2)
                    $display("[IC] OUT_PORT write: data=%h strb=%b", m_w_data, m_w_strb);
                b_int_q      <= 1'b1;
                b_int_resp_q <= (aw_sel_q == 2'd3) ? RESP_DECERR : RESP_OKAY;
            end
            if (b_fire && wr_internal) b_int_q <= 1'b0;

            // release the transaction when master consumes B
            if (w_fire) w_done_q <= 1'b1;
            if (b_fire) begin
                wr_busy  <= 1'b0;
                w_done_q <= 1'b0;
            end
        end
    end

    // ---------------- read path ----------------
    // reads to OUT_PORT or unmapped space are answered internally
    // (never forwarded, never hang the bus)
    wire rd_internal = (ar_sel_q != 2'd0) && (ar_sel_q != 2'd1);
    logic r_int_q;
    logic [31:0] r_int_data_q;

    assign m_ar_ready = ~rd_busy;
    assign m_r_valid  = rd_busy && (rd_internal ? r_int_q : r_valid_t);
    assign m_r_resp   = rd_internal ? RESP_DECERR : r_resp_t;
    assign m_r_data   = rd_internal ? r_int_data_q : r_data_t;

    // slave R readys: pass master ready through (single outstanding read)
    assign ram_r_ready = m_r_ready;
    assign crc_r_ready = m_r_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_busy      <= 1'b0;
            ar_sel_q     <= '0;
            r_int_q      <= 1'b0;
            r_int_data_q <= '0;
            ram_ar_valid <= 1'b0;
            crc_ar_valid <= 1'b0;
        end else begin
            // route AR
            if (!rd_busy && m_ar_valid) begin
                ar_sel_q <= ar_sel_now;
                rd_busy  <= 1'b1;
                unique case (ar_sel_now)
                    2'd0: begin ram_ar_valid <= 1'b1; ram_ar_addr <= m_ar_addr; end
                    2'd1: begin crc_ar_valid <= 1'b1; crc_ar_addr <= m_ar_addr; end
                    default: ;
                endcase
            end
            if (ram_ar_valid && ram_ar_ready) ram_ar_valid <= 1'b0;
            if (crc_ar_valid && crc_ar_ready) crc_ar_valid <= 1'b0;

            // internal DECERR read: no data phase from a slave; generate one
            // (value irrelevant, resp carries the error).
            // GATED on rd_busy: ar_sel_q is registered, so during the AR
            // route cycle rd_internal still reflects the PREVIOUS target.
            // Without the gate, a DECERR->RAM read sequence would spuriously
            // set r_int_q from the stale selection (found by review; TB
            // covers this sequence explicitly).
            if (rd_busy && rd_internal && !r_int_q && !r_valid_t) begin
                r_int_q      <= 1'b1;
                r_int_data_q <= 32'hBAD0_BA5E;
            end
            if (r_fire && rd_internal) r_int_q <= 1'b0;

            if (r_fire) rd_busy <= 1'b0;
        end
    end
endmodule
