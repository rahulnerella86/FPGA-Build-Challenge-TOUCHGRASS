// ============================================================================
// custom_instr_decode.sv - custom-0 instruction decoder for the CiM path.
// ----------------------------------------------------------------------------
// Recognizes ONE custom instruction in RISC-V reserved opcode space:
//
//   CIM.RUN : R-type, opcode = 7'b0001011 (custom-0, per the RISC-V spec
//             chapter on custom extensions: 0001011/0101011/1011011/1111011
//             are reserved for custom use and will never be standard ops),
//             funct3 = 3'b001, funct7 = 7'b0000001 (CIM.RUN class).
//             rs1[4:0] = result-row select, rs2/rd = reserved (ignored).
//
// Example word: CIM.RUN row 2 =
//   funct7(0000001) rs2(00000) rs1(00010) f3(001) rd(00000) op(0001011)
//   = 32'h0201_100B.
//
// COLLISION ANALYSIS (vs ../05-riscv-ai-accelerator control_unit.sv, which
// is NOT modified here): the base core decodes 0110011, 0010011, 0000011,
// 0100011, 1100011, 1101111, 1100111, 0110111, 0010111; EVERYTHING else,
// including 0001011 in any funct combination, falls into `default:` (all
// control signals 0: no RF write, no mem access, no branch -> the core
// executes our word as a harmless NOP and advances PC+4). The dispatch
// layer in cim_dispatch.sv acts on the same word in parallel. Verified by
// tb_custom_instr_decode.sv (exhaustive opcode x funct3 x funct7 sweep).
//
// Purely combinational: testable in isolation, synthesizable as-is.
// ============================================================================
module custom_instr_decode #(
    parameter logic [6:0] CIM_OPCODE = 7'b0001011, // custom-0, never standard
    parameter logic [2:0] CIM_FUNCT3 = 3'b001,     // CIM.RUN subclass
    parameter logic [6:0] CIM_FUNCT7 = 7'b0000001  // CIM.RUN class
)(
    input  wire [31:0] instruction,  // live fetch word (snooped, not consumed)
    output wire        cim_valid,    // 1: this word is CIM.RUN
    output wire [4:0]  cim_rd,       // reserved (core ignores; passed for TB)
    output wire [4:0]  cim_rs1,      // result-row select
    output wire [4:0]  cim_rs2,      // reserved (ignored)
    output wire [2:0]  cim_funct3    // = CIM_FUNCT3 when valid
);
    wire [6:0] opcode;
    wire [6:0] funct7;
    wire [2:0] funct3;

    assign opcode = instruction[6:0];
    assign funct7 = instruction[31:25];
    assign funct3 = instruction[14:12];

    assign cim_valid  = (opcode == CIM_OPCODE) &&
                        (funct3 == CIM_FUNCT3) &&
                        (funct7 == CIM_FUNCT7);
    assign cim_rd     = instruction[11:7];
    assign cim_rs1    = instruction[19:15];
    assign cim_rs2    = instruction[24:20];
    assign cim_funct3 = funct3;

endmodule
