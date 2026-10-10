// ============================================================================
// main_cim.c - minimal firmware driving the CIM.RUN custom instruction.
// ----------------------------------------------------------------------------
// BUILD (needs riscv32-unknown-elf-gcc - NOT installed on the sim box, so
// this file is source-only here; simulation uses hand-encoded words in
// tb_soc_top_cim.sv instead):
//   riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostartfiles \
//       -T link.ld main_cim.c -o main_cim.elf
//   riscv32-unknown-elf-objcopy -O verilog main_cim.elf main_cim.hex
//
// FLOW (row 5 = weights 1..16, activations all 2 -> dot = 272):
//   1. stage weights/activations through the CIM MMIO loader window;
//   2. issue CIM.RUN via inline assembly (custom-0 opcode 0001011,
//      funct3=001, funct7=0000001, rs1=row; the base core executes the
//      word as a NOP while cim_dispatch acts on it in parallel);
//   3. poll STATUS busy-then-done (done sticks - never poll done alone);
//   4. read RESULT, compare against 272, return 0 on match.
// ============================================================================
#include <stdint.h>

#define CIM_BASE   0x20000000u
#define CIM_WADDR  (*(volatile uint32_t *)(CIM_BASE + 0x00))
#define CIM_WDATA  (*(volatile uint32_t *)(CIM_BASE + 0x04))
#define CIM_AADDR  (*(volatile uint32_t *)(CIM_BASE + 0x08))
#define CIM_ADATA  (*(volatile uint32_t *)(CIM_BASE + 0x0C))
#define CIM_STATUS (*(volatile uint32_t *)(CIM_BASE + 0x10))
#define CIM_RESULT (*(volatile uint32_t *)(CIM_BASE + 0x14))

// CIM.RUN word: funct7(0000001) rs2(00000) rs1(row) f3(001) rd(00000) 0001011
#define CIM_RUN_WORD(row) \
    (0x02000000u | (((uint32_t)(row) & 0x1Fu) << 15) | (1u << 12) | 0x0Bu)
#define CIM_RUN(row) \
    __asm__ volatile (".word %0" :: "i"(CIM_RUN_WORD(row)))

static uint32_t cim_status(void) { return CIM_STATUS; }

int main(void) {
    uint32_t i, st;

    for (i = 0; i < 16; i++) {       // row 5 weights = 1..16
        CIM_WADDR = 5u * 16u + i;
        CIM_WDATA = i + 1u;
    }
    for (i = 0; i < 16; i++) {       // activations = all 2
        CIM_AADDR = i;
        CIM_ADATA = 2u;
    }

    CIM_RUN(5);                      // launch matvec, select row 5

    do { st = cim_status(); } while ((st & 1u) == 0u); // wait busy...
    do { st = cim_status(); } while ((st & 2u) == 0u); // ...then done

    if ((st & 4u) != 0u)
        return 2;                    // overlapping launch dropped (unexpected here)

    return (CIM_RESULT == 272u) ? 0 : 1;
}
