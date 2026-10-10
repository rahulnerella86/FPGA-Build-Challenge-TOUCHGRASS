// ============================================================================
// tb_soc_top_cim.sv - full-SoC test: custom instr in-pipeline + MMIO regress.
// ----------------------------------------------------------------------------
// Firmware (62 words, hardcoded below with field comments; standard words
// cross-checked against ../05-riscv-ai-accelerator tb patterns, CIM.RUN =
// 0x0202900B = funct7(0000001) rs2(0) rs1(5) f3(001) rd(0) op(0001011)):
//   Phase A (idx 0-14):  MMIO regression - CPU drives mac_accelerator for
//                         [3,4].[5,6]=39, stores dmem[0x300]. Must be
//                         bit-identical behavior to the base SoC.
//   Phase B (idx 15-41): CIM via MMIO loader (row5 = 1..16, act = all 2),
//                         CIM.RUN row 5, busy-then-done poll, RESULT_L into
//                         x11 (preserves phase-A x8=39 evidence) ->
//                         dmem[0x308] must be 272.
//   Phase C (idx 42-61): hazard - back-to-back CIM.RUN with no poll:
//                         2nd launch must drop (STATUS[2]=1), first result
//                         intact in x10; 3rd launch (clean) clears the flag.
//                         Parks at 61 on success, 51/60 on failure.
// Checks: dmem[0x300]==39, dmem[0x308]==272, x10==272, x31==0x123
// (sentinel: proves CIM.RUN words never corrupt the register file - the
// core executes them as NOP), PC==0xF4 (expected park, never fail sinks),
// sel_q==5, dropped_q==0 at end. Bounded PC-stable completion + watchdog.
// PASS: "*** ALL CHECKS PASSED (tb_soc_top_cim) ***".
// ============================================================================
`timescale 1ns/1ps
module tb_soc_top_cim;
    logic clk;
    logic rst_n;
    int errors;

    soc_top_cim #(
        .IMEM_DEPTH (256),
        .DMEM_DEPTH (1024)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        int n, stable;
        logic [31:0] last_pc;
        errors = 0;
        $display("== tb_soc_top_cim start ==");

        // ---- dmem vectors for the MMIO regression phase ----
        dut.dmem_inst.mem[32'h100 >> 2] = 32'sd3;
        dut.dmem_inst.mem[32'h104 >> 2] = 32'sd4;
        dut.dmem_inst.mem[32'h200 >> 2] = 32'sd5;
        dut.dmem_inst.mem[32'h204 >> 2] = 32'sd6;

        // ---- firmware (see header for encoding notes) ----
        dut.imem_inst.mem[0]  = 32'h100000B7;
        dut.imem_inst.mem[1]  = 32'h10000113;
        dut.imem_inst.mem[2]  = 32'h20000193;
        dut.imem_inst.mem[3]  = 32'h00200213;
        dut.imem_inst.mem[4]  = 32'h00100293;
        dut.imem_inst.mem[5]  = 32'h0020A223;
        dut.imem_inst.mem[6]  = 32'h0030A423;
        dut.imem_inst.mem[7]  = 32'h0040A623;
        dut.imem_inst.mem[8]  = 32'h0050A023;
        dut.imem_inst.mem[9]  = 32'h0100A303;
        dut.imem_inst.mem[10] = 32'h00237393;
        dut.imem_inst.mem[11] = 32'hFE038CE3;
        dut.imem_inst.mem[12] = 32'h0140A403;
        dut.imem_inst.mem[13] = 32'h30000493;
        dut.imem_inst.mem[14] = 32'h0084A023;
        dut.imem_inst.mem[15] = 32'h20000137;
        dut.imem_inst.mem[16] = 32'h12300F93;
        dut.imem_inst.mem[17] = 32'h05000193;
        dut.imem_inst.mem[18] = 32'h00100213;
        dut.imem_inst.mem[19] = 32'h00312023;
        dut.imem_inst.mem[20] = 32'h00412223;
        dut.imem_inst.mem[21] = 32'h00118193;
        dut.imem_inst.mem[22] = 32'h00120213;
        dut.imem_inst.mem[23] = 32'h06000293;
        dut.imem_inst.mem[24] = 32'hFE51C6E3;
        dut.imem_inst.mem[25] = 32'h00000193;
        dut.imem_inst.mem[26] = 32'h00200213;
        dut.imem_inst.mem[27] = 32'h00312423;
        dut.imem_inst.mem[28] = 32'h00412623;
        dut.imem_inst.mem[29] = 32'h00118193;
        dut.imem_inst.mem[30] = 32'h01000293;
        dut.imem_inst.mem[31] = 32'hFE51C8E3;
        dut.imem_inst.mem[32] = 32'h0202900B;
        dut.imem_inst.mem[33] = 32'h01012303;
        dut.imem_inst.mem[34] = 32'h00137393;
        dut.imem_inst.mem[35] = 32'hFE038CE3;
        dut.imem_inst.mem[36] = 32'h01012303;
        dut.imem_inst.mem[37] = 32'h00237393;
        dut.imem_inst.mem[38] = 32'hFE038CE3;
        dut.imem_inst.mem[39] = 32'h01412583;
        dut.imem_inst.mem[40] = 32'h30800493;
        dut.imem_inst.mem[41] = 32'h00B4A023;
        dut.imem_inst.mem[42] = 32'h0202900B;
        dut.imem_inst.mem[43] = 32'h0202900B;
        dut.imem_inst.mem[44] = 32'h01012303;
        dut.imem_inst.mem[45] = 32'h00237393;
        dut.imem_inst.mem[46] = 32'hFE038CE3;
        dut.imem_inst.mem[47] = 32'h01412503;
        dut.imem_inst.mem[48] = 32'h01012303;
        dut.imem_inst.mem[49] = 32'h00437393;
        dut.imem_inst.mem[50] = 32'h00039463;
        dut.imem_inst.mem[51] = 32'h0000006F;
        dut.imem_inst.mem[52] = 32'h0202900B;
        dut.imem_inst.mem[53] = 32'h01012303;
        dut.imem_inst.mem[54] = 32'h00237393;
        dut.imem_inst.mem[55] = 32'hFE038CE3;
        dut.imem_inst.mem[56] = 32'h01012303;
        dut.imem_inst.mem[57] = 32'h00437393;
        dut.imem_inst.mem[58] = 32'h00039463;
        dut.imem_inst.mem[59] = 32'h0080006F;
        dut.imem_inst.mem[60] = 32'h0000006F;
        dut.imem_inst.mem[61] = 32'h0000006F;

        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;

        // ---- completion: PC parked (firmware ends in J self-loop) ----
        last_pc = 32'h0; stable = 0; n = 0;
        while (n < 50000 && stable < 50) begin
            @(posedge clk); #1;
            n = n + 1;
            if (dut.cpu_inst.pc_inst.pc_reg === last_pc)
                stable = stable + 1;
            else begin
                last_pc = dut.cpu_inst.pc_inst.pc_reg;
                stable = 0;
            end
        end
        if (stable < 50) begin
            $display("[FAIL] firmware never parked after %0d cycles", n);
            errors = errors + 1;
        end else begin
            $display("[PASS] firmware parked at PC=0x%08h after %0d cycles",
                     last_pc, n);
        end
        if (last_pc !== 32'h0000_00F4) begin
            $display("[FAIL] park PC=0x%08h, want 0xF4 (fail sinks: 0xCC/0xF0)",
                     last_pc);
            errors = errors + 1;
        end else begin
            $display("[PASS] parked at success sink 0xF4");
        end

        // ---- Phase A regression ----
        if (dut.dmem_inst.mem[32'h300 >> 2] !== 32'd39) begin
            $display("[FAIL] MMIO regression: dmem[0x300]=%0d, want 39",
                     dut.dmem_inst.mem[32'h300 >> 2]);
            errors = errors + 1;
        end else $display("[PASS] MMIO regression: dmem[0x300]=39");
        if (dut.cpu_inst.reg_file_inst.regs[8] !== 32'd39) begin
            $display("[FAIL] MMIO regression: x8=%0d, want 39",
                     dut.cpu_inst.reg_file_inst.regs[8]);
            errors = errors + 1;
        end else $display("[PASS] MMIO regression: x8=39");

        // ---- Phase B CIM result (x11 + dmem, x8 still holds phase A) ----
        if (dut.cpu_inst.reg_file_inst.regs[11] !== 32'd272) begin
            $display("[FAIL] CIM result: x11=%0d, want 272",
                     dut.cpu_inst.reg_file_inst.regs[11]);
            errors = errors + 1;
        end else $display("[PASS] CIM result: x11=272");
        if (dut.dmem_inst.mem[32'h308 >> 2] !== 32'd272) begin
            $display("[FAIL] CIM result: dmem[0x308]=%0d (0x%08h), want 272",
                     $signed(dut.dmem_inst.mem[32'h308 >> 2]),
                     dut.dmem_inst.mem[32'h308 >> 2]);
            errors = errors + 1;
        end else $display("[PASS] CIM result: dmem[0x308]=272");

        // ---- Phase C hazard handling ----
        if (dut.cpu_inst.reg_file_inst.regs[10] !== 32'd272) begin
            $display("[FAIL] hazard phase: x10=%0d, want 272 (first run intact)",
                     dut.cpu_inst.reg_file_inst.regs[10]);
            errors = errors + 1;
        end else $display("[PASS] hazard phase: x10=272, overlapped run dropped cleanly");

        // ---- core untouched by custom words ----
        if (dut.cpu_inst.reg_file_inst.regs[31] !== 32'h123) begin
            $display("[FAIL] sentinel x31=0x%08h, want 0x123 (RF corrupted!)",
                     dut.cpu_inst.reg_file_inst.regs[31]);
            errors = errors + 1;
        end else $display("[PASS] sentinel x31 intact across 4 CIM.RUN words");

        // ---- dispatch end-state ----
        if (dut.cim_inst.sel_q !== 5) begin
            $display("[FAIL] sel_q=%0d, want 5", dut.cim_inst.sel_q);
            errors = errors + 1;
        end else $display("[PASS] dispatch row select = 5");
        if (dut.cim_inst.dropped_q !== 1'b0) begin
            $display("[FAIL] dropped flag stuck set");
            errors = errors + 1;
        end else $display("[PASS] dropped flag clear after clean relaunch");

        if (errors == 0)
            $display("*** ALL CHECKS PASSED (tb_soc_top_cim) ***");
        else begin
            $display("*** FAILURES: %0d ***", errors);
            $fatal(1);
        end
        $finish;
    end

    initial begin
        repeat (500000) @(posedge clk);
        $display("*** WATCHDOG TIMEOUT ***");
        $fatal(1);
    end
endmodule
