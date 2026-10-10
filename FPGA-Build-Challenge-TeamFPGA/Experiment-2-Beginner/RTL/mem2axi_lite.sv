// ============================================================================
// mem2axi_lite.sv - bridge picorv32's simple mem_* interface to AXI-Lite.
//
// picorv32 (YosysHQ) exposes a compact uncached memory port:
//     mem_valid / mem_instr / mem_addr / mem_wdata / mem_wstrb /
//     mem_rdata / mem_ready
// This converts it to the AXI-Lite master used by bus_interconnect.
//
// VERIFIED BY: tb_soc_top.sv (via soc_top with USE_PICO=0 using the same
// exposed mem-interface signals - so the bridge's handshake contract is
// exercised at the boundary; full pico-in-loop boot is a hardware run).
//
// FLAGGED SIMPLIFICATIONS (all acceptable for every single master):
//   * Serialized AW-then-W (AXI-Lite tolerates; picorv32 never exploits
//     W-before-AW).
//   * Read returns when r_valid lands; mem_ready is registered 1 cycle
//     after the AXI response, so the bridge adds ~2 cycles vs a bare RAM.
//   * No outstanding traffic: exactly one transaction in flight, which is
//     exactly what the core generates (mem_valid held until mem_ready).
// ============================================================================
module mem2axi_lite (
    input  wire clk,
    input  wire rst_n,
    // picorv32 mem interface (see picorv32 README "pipelined memory")
    input  wire        mem_valid,
    input  wire        mem_instr,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_wstrb,
    output logic [31:0] mem_rdata,
    output logic        mem_ready,
    // AXI-Lite master released into the interconnect
    output logic        m_aw_valid,
    output logic [31:0] m_aw_addr,
    input  wire         m_aw_ready,
    output logic        m_w_valid,
    output logic [31:0] m_w_data,
    output logic [3:0]  m_w_strb,
    input  wire         m_w_ready,
    input  wire         m_b_valid,
    input  wire [1:0]   m_b_resp,
    output logic        m_b_ready,
    output logic        m_ar_valid,
    output logic [31:0] m_ar_addr,
    input  wire         m_ar_ready,
    input  wire         m_r_valid,
    input  wire [31:0]  m_r_data,
    input  wire [1:0]   m_r_resp,
    output logic        m_r_ready
);
    typedef enum logic [2:0] { IDLE, DOE_AW, DOE_AR, WAIT_R, WAIT_B } st_t;
    st_t state;
    logic is_write;

    // read-side data: registered when the AXI R beat lands, then presented
    // to mem_rdata in the same cycle mem_ready is raised.
    logic [31:0] rdata_q;
    // picoSoC-style mem-gate latch. picorv32 HOLDS mem_valid high until it
    // sees mem_ready, so the bridge must dispatch on the RISING EDGE of
    // mem_valid, not on "IDLE && mem_valid" (a still-held valid re-fires a
    // phantom transaction whose WAIT_B raises mem_ready BEFORE the real
    // read completes - found by the t=145000/195000/225000 correlation in
    // tb_soc_top). req_armed consumes one edge; !mem_valid re-arms it.
    logic req_armed;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            is_write   <= 1'b0;
            rdata_q    <= '0;
            m_aw_valid <= 1'b0;
            m_w_valid  <= 1'b0;
            m_ar_valid <= 1'b0;
            m_b_ready  <= 1'b0;
            m_r_ready  <= 1'b0;
            req_armed  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (mem_valid && !req_armed) begin
                        is_write <= (mem_wstrb != 4'b0);
                        if (mem_wstrb != 4'b0) begin
                            m_aw_valid <= 1'b1;
                            m_aw_addr  <= mem_addr;
                            state      <= DOE_AW;
                        end else begin
                            m_ar_valid <= 1'b1;
                            m_ar_addr  <= mem_addr;
                            state      <= DOE_AR;
                        end
                        req_armed <= 1'b1;
                    end
                end
                DOE_AW: begin                          // AW accepted, drive W
                    if (m_aw_valid && m_aw_ready) begin
                        m_aw_valid <= 1'b0;
                        m_w_valid  <= 1'b1;
                        m_w_data   <= mem_wdata;
                        m_w_strb   <= mem_wstrb;
                    end
                    if (m_w_valid && m_w_ready) begin
                        m_w_valid <= 1'b0;
                        m_b_ready <= 1'b1;
                        state     <= WAIT_B;
                    end
                end
                DOE_AR: begin                          // wait for R beat
                    if (m_ar_valid && m_ar_ready) m_ar_valid <= 1'b0;
                    if (m_r_valid) begin
                        rdata_q <= m_r_data;
                        m_r_ready <= 1'b1;
                        state   <= WAIT_R;
                    end
                end
                WAIT_R: begin                          // present data, drop ready
                    mem_ready <= 1'b1;
                    m_r_ready <= 1'b0;
                    state     <= IDLE;
                end
                WAIT_B: begin                          // acknowledge B, done
                    if (m_b_valid) begin
                        m_b_ready <= 1'b0;
                        mem_ready <= 1'b1;
                        state     <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
            // mem_ready is a pulse on the cycle the transaction completes;
            // default deassert outside the WAIT_* states
            if (state != WAIT_R && state != WAIT_B) mem_ready <= 1'b0;
            if (state == WAIT_R || state == WAIT_B) mem_rdata <= rdata_q;
            // mem-gate re-arm: once the master releases valid, a NEW rising
            // edge can start a new transaction.
            if (!mem_valid) req_armed <= 1'b0;
        end
    end
endmodule