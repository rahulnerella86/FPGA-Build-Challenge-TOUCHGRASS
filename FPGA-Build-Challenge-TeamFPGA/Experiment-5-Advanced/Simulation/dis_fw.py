#!/usr/bin/env python3
"""Correct RV32I disassembler for the tb_soc_top_cim firmware image."""
import sys

WORDS = [
0x100000B7, 0x10000113, 0x20000193, 0x00200213, 0x00100293, 0x0020A223,
0x0030A423, 0x0040A623, 0x0050A023, 0x0100A303, 0x00237393, 0xFE038CE3,
0x0140A403, 0x30000493, 0x0084A023, 0x20000137, 0x12300F93, 0x05000193,
0x00100213, 0x00312023, 0x00412223, 0x00118193, 0x00120213, 0x06000293,
0xFE51C6E3, 0x00000193, 0x00200213, 0x00312423, 0x00412623, 0x00118193,
0x01000293, 0xFE51C8E3, 0x0202900B, 0x01012303, 0x00137393, 0xFE038CE3,
0x01012303, 0x00237393, 0xFE038CE3, 0x01412583, 0x30800493, 0x00B4A023,
0x0202900B, 0x0202900B, 0x01012303, 0x00237393, 0xFE038CE3, 0x01412503,
0x01012303, 0x00437393, 0x00039463, 0x0000006F, 0x0202900B, 0x01012303,
0x00237393, 0xFE038CE3, 0x01012303, 0x00437393, 0x00039463, 0x0080006F,
0x0000006F, 0x0000006F,
]

def sx(v, bits):
    m = 1 << (bits - 1)
    return (v ^ m) - m

def dis(w, pc):
    op = w & 0x7F
    rd = (w >> 7) & 0x1F
    f3 = (w >> 12) & 0x7
    rs1 = (w >> 15) & 0x1F
    rs2 = (w >> 20) & 0x1F
    f7 = (w >> 25) & 0x7F
    # immediates
    imm_i = sx((w >> 20) & 0xFFF, 12)
    imm_s = sx(((w >> 25) << 5) | ((w >> 7) & 0x1F), 12)
    imm_b = sx(((w >> 31) << 12) | (((w >> 7) & 1) << 11) |
               (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1), 13)
    imm_u = w & 0xFFFFF000
    imm_j = sx(((w >> 31) << 20) | (((w >> 12) & 0xFF) << 12) |
               (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1), 21)

    if op == 0x37: return f"lui   x{rd}, 0x{imm_u >> 12:x}"
    if op == 0x17: return f"auipc x{rd}, 0x{imm_u >> 12:x}"
    if op == 0x6F: return f"jal   x{rd}, {pc + imm_j} (0x{pc + imm_j:03X})"
    if op == 0x67: return f"jalr  x{rd}, {imm_i}(x{rs1})"
    if op == 0x63:
        mn = ["beq", "bne", None, None, "blt", "bge", "bltu", "bgeu"][f3]
        return f"{mn:5s} x{rs1}, x{rs2}, {pc + imm_b} (0x{pc + imm_b:03X})"
    if op == 0x03:
        mn = ["lb", "lh", "lw", None, "lbu", "lhu"][f3] if f3 != 3 else None
        return f"{mn:5s} x{rd}, {imm_i}(x{rs1})"
    if op == 0x23:
        mn = ["sb", "sh", "sw"][f3] if f3 < 3 else None
        return f"{mn:5s} x{rs2}, {imm_s}(x{rs1})"
    if op == 0x13:
        if f3 == 0: return f"addi  x{rd}, x{rs1}, {imm_i}"
        if f3 == 2: return f"slti  x{rd}, x{rs1}, {imm_i}"
        if f3 == 3: return f"sltiu x{rd}, x{rs1}, {imm_i}"
        if f3 == 4: return f"xori  x{rd}, x{rs1}, {imm_i}"
        if f3 == 6: return f"ori   x{rd}, x{rs1}, {imm_i}"
        if f3 == 7: return f"andi  x{rd}, x{rs1}, {imm_i}"
        if f3 == 1: return f"slli  x{rd}, x{rs1}, {(w >> 20) & 0x1F}"
        if f3 == 5: return (f"srai  x{rd}, x{rs1}, {(w >> 20) & 0x1F}" if (w >> 30) & 1
                            else f"srli  x{rd}, x{rs1}, {(w >> 20) & 0x1F}")
    if op == 0x33:
        mn = {(0, 0): "add", (0, 0x20): "sub", (1, 0): "sll", (2, 0): "slt",
              (3, 0): "sltu", (4, 0): "xor", (5, 0): "srl", (5, 0x20): "sra",
              (6, 0): "or", (7, 0): "and"}.get((f3, f7))
        return f"{mn:5s} x{rd}, x{rs1}, x{rs2}"
    if op == 0x0B:
        return f"CIM.f{f3} rd=x{rd} rs1=x{rs1} rs2=x{rs2} (custom, core NOP)"
    return f"??? op=0x{op:02X}"

def main():
    print("idx  pc     word       disassembly")
    for i, w in enumerate(WORDS):
        print(f"{i:3d}  0x{i*4:03X}  0x{w:08X}  {dis(w, i*4)}")

if __name__ == "__main__":
    main()