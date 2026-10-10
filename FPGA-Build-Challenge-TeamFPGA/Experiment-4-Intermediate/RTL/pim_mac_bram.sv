// ============================================================================
// pim_mac_bram.sv - honest BRAM-based PIM approximation (Phase B).
// ----------------------------------------------------------------------------
// WHAT IT IS: a digital, synthesizable stand-in for an SRAM compute-in-memory
// macro. A real analog CiM macro computes dot products inside the bitcell
// array; an FPGA has no such primitive, so this block stores the INT8 weight
// matrix in a synchronous 1R1W BRAM and streams one weight per cycle into a
// shared INT8*INT8->INT32 MAC. Functionally it is a row-wise matvec engine:
//     result[r] = sum_c( weight[r][c] * activ[c] )  (mod 2**32, two's compl.)
// which is exactly what model/pim_model.py computes (bit-accurate golden).
//
// HONESTY: this is a silicon-APPROXIMATION, not a CiM circuit. It proves the
// dataflow/arithmetic/sequencing the CiM block in project 05 will expose,
// not analog behavior (no bitline, no ADC, no variation). Labeled, not faked.
//
// MICROARCHITECTURE (parameterized, 1 MAC/cycle):
//   wmem: ROWS*COLS x INT8 synchronous BRAM (write port for load, sync read
//         with 1-cycle latency -> infers Block RAM in Vivado).
//   amem: COLS x INT8 activation regs (small, distributed; async read ok).
//   rmem: ROWS x INT32 result regs.
//   FSM: IDLE -> COMPUTE -> DONE. COMPUTE issues one weight read per cycle,
//        consumes it one cycle later (pipe_valid), accumulates per row, and
//        writes rmem at each row boundary. DONE sticks until next start.
//   Result read port is synchronous (1-cycle latency, BRAM-like).
//
// FLAGGED SHORTCUTS: (1) 1 MAC/cycle is slow - a production engine would use
//   ROWS parallel MACs or a tree; interface is unchanged if you do. (2) No
//   requantize/scale (see project 03 for that); raw INT32 out. (3) Weight and
//   activation loads are raw ports - project 05 wraps this with an AXI/PCPI
//   front end instead of exposing them directly.
// VERIFIED BY: tb/pim_mac_tb.sv (known-answer, random, corners, reset, B2B).
// ============================================================================
module pim_mac_bram #(
    parameter int NUM_ROWS = 16,
    parameter int NUM_COLS = 16,
    parameter int DATA_W   = 8,
    parameter int ACC_W    = 32
)(
    input  wire                          clk,
    input  wire                          rst_n,

    // ---- weight load port (synchronous write) ----
    input  wire                          w_wr_en,
    input  wire [$clog2(NUM_ROWS*NUM_COLS)-1:0] w_wr_addr,
    input  wire [DATA_W-1:0]             w_wr_data,

    // ---- activation load port (synchronous write) ----
    input  wire                          a_wr_en,
    input  wire [$clog2(NUM_COLS)-1:0]   a_wr_addr,
    input  wire [DATA_W-1:0]             a_wr_data,

    // ---- control ----
    input  wire                          start,   // pulse in IDLE/DONE
    output wire                          busy,
    output wire                          done,    // sticks until next start

    // ---- result read port (synchronous, 1-cycle latency) ----
    input  wire                          r_rd_en,
    input  wire [$clog2(NUM_ROWS)-1:0]   r_rd_addr,
    output logic [ACC_W-1:0]             r_rd_data,
    output logic                         r_rd_valid
);
    localparam int WDEPTH = NUM_ROWS*NUM_COLS;

    // ---------------- memories ----------------
    logic signed [DATA_W-1:0] wmem [0:WDEPTH-1];
    logic signed [DATA_W-1:0] amem [0:NUM_COLS-1];
    logic signed [ACC_W-1:0]  rmem [0:NUM_ROWS-1];

    // ---------------- FSM ----------------
    localparam logic [1:0] S_IDLE = 2'd0, S_COMP = 2'd1, S_DONE = 2'd2;
    logic [1:0] state, state_q;

    // issue side (addresses presented to wmem)
    // NOTE: issue_cnt is one bit wider than the address so it can hold the
    // terminal value WDEPTH (a $clog2(WDEPTH)-bit counter wraps 31->0 and the
    // engine never terminates - found by TB TIMEOUT, fixed here).
    logic [$clog2(WDEPTH):0]         issue_cnt;   // 0..WDEPTH
    logic [$clog2(WDEPTH)-1:0]   rd_addr_r;
    logic [$clog2(NUM_COLS)-1:0] col_issue;   // issue_cnt % COLS
    logic                        issuing;

    // consume side (data emerging from wmem one cycle later)
    logic signed [DATA_W-1:0]    w_data_q;
    logic [$clog2(NUM_COLS)-1:0] col_d;
    logic                        pipe_vld;
    logic [$clog2(WDEPTH):0]     cons_cnt;    // 0..WDEPTH
    logic signed [ACC_W-1:0]     acc;

    // consume-path helpers (hoisted out of always_ff for old-ModelSim compat)
    logic signed [15:0]      prod_c;
    logic signed [ACC_W-1:0] acc_nxt_c;
    assign prod_c    = w_data_q * $signed(amem[col_d]);
    assign acc_nxt_c = acc + prod_c;

    assign busy = (state != S_IDLE);
    assign done = (state == S_DONE);

    // column of the issue pointer (constant-COLS modulo without % operator)
    // issue_cnt < WDEPTH always when issuing, so a subtractive reduce is exact.
    logic [$clog2(NUM_COLS)-1:0] col_issue_comb;
    always @* begin
        int tmp;
        tmp = issue_cnt;
        while (tmp >= NUM_COLS) tmp = tmp - NUM_COLS;
        col_issue_comb = tmp[$clog2(NUM_COLS)-1:0];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            issue_cnt  <= '0;
            rd_addr_r  <= '0;
            col_issue  <= '0;
            issuing    <= 1'b0;
            w_data_q   <= '0;
            col_d      <= '0;
            pipe_vld   <= 1'b0;
            cons_cnt   <= '0;
            acc        <= '0;
            r_rd_data  <= '0;
            r_rd_valid <= 1'b0;
        end else begin
            // ---- synchronous result read (BRAM-like, 1-cycle) ----
            r_rd_valid <= r_rd_en;
            if (r_rd_en) r_rd_data <= rmem[r_rd_addr];

            // ---- load ports (allowed in IDLE/DONE; blocked mid-compute) ----
            if (w_wr_en && state != S_COMP) wmem[w_wr_addr] <= $signed(w_wr_data);
            if (a_wr_en && state != S_COMP) amem[a_wr_addr] <= $signed(a_wr_data);

            case (state)
                S_IDLE: begin
                    pipe_vld <= 1'b0;
                    issuing  <= 1'b0;
                    if (start) begin
`ifdef DEBUG_PIM
                        $display("[DUT] IDLE->COMP t=%0t", $time);
`endif
                        state     <= S_COMP;
                        issue_cnt <= '0;
                        cons_cnt  <= '0;
                        acc       <= '0;
                    end
                end
                S_COMP: begin
                    // issue one read per cycle until the matrix is covered
                    if (issue_cnt < WDEPTH) begin
                        rd_addr_r <= issue_cnt[$clog2(WDEPTH)-1:0];
                        col_issue <= col_issue_comb;
                        issuing   <= 1'b1;
                        issue_cnt <= issue_cnt + 1'b1;
                    end else begin
                        issuing <= 1'b0;
                    end
                    // consume path: data appears one cycle after issue
                    w_data_q <= wmem[rd_addr_r];
                    col_d    <= col_issue;
                    pipe_vld <= issuing;
                    if (pipe_vld) begin
                        if (col_d == NUM_COLS-1) begin
                            // row boundary: row = (cons_cnt+1)/COLS - 1
`ifdef DEBUG_PIM
                            $display("[DUT] rowwr row=%0d acc=0x%08h t=%0t w=%0d a=%0d",
                                     (cons_cnt+1)/NUM_COLS - 1, acc_nxt_c,
                                     $time, w_data_q, $signed(amem[col_d]));
`endif
                            rmem[(cons_cnt+1)/NUM_COLS - 1] <= acc_nxt_c;
                            acc <= '0;
                        end else begin
                            acc <= acc_nxt_c;
                        end
                        cons_cnt <= cons_cnt + 1'b1;
                    end
                    if (cons_cnt == WDEPTH && !pipe_vld && !issuing) begin
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    pipe_vld <= 1'b0;
                    issuing  <= 1'b0;
                    if (start) begin
                        state     <= S_COMP;
                        issue_cnt <= '0;
                        cons_cnt  <= '0;
                        acc       <= '0;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    // synthesis visibility: state_q mirrors state for wlf/log inspection
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state_q <= S_IDLE;
        else        state_q <= state;
    end

endmodule
