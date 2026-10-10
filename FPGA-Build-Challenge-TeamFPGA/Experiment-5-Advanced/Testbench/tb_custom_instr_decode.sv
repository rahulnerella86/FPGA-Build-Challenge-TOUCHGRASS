// ============================================================================
// tb_custom_instr_decode.sv - isolated, exhaustive test of custom_instr_decode.
// ----------------------------------------------------------------------------
// E1: EXHAUSTIVE opcode(128) x funct3(8) x funct7(128) = 131072 words with
//     fixed rd/rs1/rs2: cim_valid must be 1 for EXACTLY ONE combination
//     (0001011/001/0000001) and 0 everywhere else. This proves no RV32I
//     major opcode - including every opcode the base core decodes
//     (0110011, 0010011, 0000011, 0100011, 1100011, 1101111, 1100111,
//     0110111, 0010111) and near-misses (FENCE 0001111, SYSTEM 1110011,
//     LOAD-FP 0000111, custom-1/2/3) - is misidentified, and no other
//     funct3/funct7 alias of custom-0 fires.
// E2: OPERAND SWEEP: all 32^3 = 32768 rd/rs1/rs2 values on the valid word:
//     cim_valid stays 1 and passthrough fields track the word bits.
// E3: NEAR-MISS SPOT CHECKS with explicit hand-computed words (documents
//     the encoding): CIM.RUN row 2 = 0x0201100B fires; same word with
//     funct3=010, funct7=0000010, or opcode 0101011 (custom-1) does not.
// Old-ModelSim-safe: declarations precede statements in every block.
// PASS: "*** ALL CHECKS PASSED (tb_custom_instr_decode) ***".
// ============================================================================
`timescale 1ns/1ps
module tb_custom_instr_decode;
    logic [31:0] instruction;
    wire        cim_valid;
    wire [4:0]  cim_rd, cim_rs1, cim_rs2;
    wire [2:0]  cim_funct3;

    int errors;
    int n_valid;

    custom_instr_decode dut (
        .instruction (instruction),
        .cim_valid   (cim_valid),
        .cim_rd      (cim_rd),
        .cim_rs1     (cim_rs1),
        .cim_rs2     (cim_rs2),
        .cim_funct3  (cim_funct3)
    );

    // The nine major opcodes the base core gives non-default controls.
    function automatic bit core_implements(input [6:0] op);
        case (op)
            7'b0110011, 7'b0010011, 7'b0000011, 7'b0100011, 7'b1100011,
            7'b1101111, 7'b1100111, 7'b0110111, 7'b0010111: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction

    initial begin
        int op, f3, f7, rd, rs1, rs2;
        logic want;
        errors = 0;
        n_valid = 0;

        // ---------- E1: exhaustive opcode x funct3 x funct7 ----------
        for (op = 0; op < 128; op = op + 1) begin
            for (f3 = 0; f3 < 8; f3 = f3 + 1) begin
                for (f7 = 0; f7 < 128; f7 = f7 + 1) begin
                    instruction = {f7[6:0], 5'd3, 5'd2, f3[2:0], 5'd1, op[6:0]};
                    #1;
                    want = (op == 7'b0001011) && (f3 == 3'b001) && (f7 == 7'b0000001);
                    if (cim_valid !== want) begin
                        $display("[E1-FAIL] op=%07b f3=%03b f7=%07b: valid=%b want %b",
                                 op[6:0], f3[2:0], f7[6:0], cim_valid, want);
                        errors = errors + 1;
                    end
                    if (cim_valid === 1'b1) begin
                        n_valid = n_valid + 1;
                        // every core-implemented opcode must NEVER coincide
                        if (core_implements(op[6:0])) begin
                            $display("[E1-FAIL] valid overlaps core opcode %07b", op[6:0]);
                            errors = errors + 1;
                        end
                    end
                    // passthrough integrity on the valid word
                    if (want) begin
                        if ({cim_rs1, cim_rs2, cim_rd} !== {5'd2, 5'd3, 5'd1}) begin
                            $display("[E1-FAIL] passthrough wrong: %0d %0d %0d",
                                     cim_rs1, cim_rs2, cim_rd);
                            errors = errors + 1;
                        end
                    end
                end
            end
        end
        if (n_valid !== 1) begin
            $display("[E1-FAIL] exactly one combo must fire, saw %0d", n_valid);
            errors = errors + 1;
        end else begin
            $display("[E1-PASS] 131072 combos: exactly the CIM.RUN word fires");
        end

        // ---------- E2: operand sweep on the valid word ----------
        for (rd = 0; rd < 32; rd = rd + 1) begin
            for (rs1 = 0; rs1 < 32; rs1 = rs1 + 1) begin
                for (rs2 = 0; rs2 < 32; rs2 = rs2 + 1) begin
                    instruction = {7'b0000001, rs2[4:0], rs1[4:0], 3'b001, rd[4:0], 7'b0001011};
                    #1;
                    if (cim_valid !== 1'b1) begin
                        $display("[E2-FAIL] valid word lost valid: rd=%0d rs1=%0d rs2=%0d",
                                 rd, rs1, rs2);
                        errors = errors + 1;
                    end
                    if ({cim_rs1, cim_rs2, cim_rd} !== {rs1[4:0], rs2[4:0], rd[4:0]}) begin
                        $display("[E2-FAIL] passthrough mismatch");
                        errors = errors + 1;
                    end
                end
            end
        end
        $display("[E2-PASS] 32768 operand combos: valid stable, fields track");

        // ---------- E3: hand-computed near misses ----------
        instruction = 32'h0201_100B; // CIM.RUN row 2 (rs1=2)
        #1;
        if (cim_valid !== 1'b1 || cim_rs1 !== 5'd2) begin
            $display("[E3-FAIL] 0x0201100B should fire with rs1=2");
            errors = errors + 1;
        end
        instruction = 32'h0201_100B ^ 32'h0000_2000; // funct3 001->011 (bit 13)
        #1;
        if (cim_valid !== 1'b0) begin
            $display("[E3-FAIL] funct3 variant must not fire"); errors = errors + 1;
        end
        instruction = 32'h0201_100B ^ 32'h0400_0000; // funct7 bit6 flip
        #1;
        if (cim_valid !== 1'b0) begin
            $display("[E3-FAIL] funct7 variant must not fire"); errors = errors + 1;
        end
        instruction = 32'h0201_102B; // opcode 0001011->0101011 (custom-1)
        #1;
        if (cim_valid !== 1'b0) begin
            $display("[E3-FAIL] custom-1 opcode must not fire"); errors = errors + 1;
        end
        instruction = 32'h0000_0013; // NOP (ADDI x0,x0,0)
        #1;
        if (cim_valid !== 1'b0) begin
            $display("[E3-FAIL] NOP must not fire"); errors = errors + 1;
        end
        $display("[E3-PASS] hand-computed near misses all correct");

        if (errors == 0)
            $display("*** ALL CHECKS PASSED (tb_custom_instr_decode) ***");
        else begin
            $display("*** FAILURES: %0d ***", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule
