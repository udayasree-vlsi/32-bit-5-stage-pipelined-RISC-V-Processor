`timescale 1ns/1ps

// ================================================================
// 32-BIT 5-STAGE RISC-V PIPELINE - COMPREHENSIVE TESTBENCH
//
// Matches the current DUT hierarchy:
//   riscv_pipeline dut
//   dut.instruction_memory[0:255]
//   dut.data_memory[0:255]
//   dut.registers[0:31]
//   dut.ForwardA / dut.ForwardB
//   dut.LoadUseStall
//   dut.BranchTaken_EX
//
// Verilog-2001 / Vivado behavioral simulation.

//
// Tests:
//   24 RV32I instructions
//   1. ADD
//   2. SUB
//   3. AND
//   4. OR
//   5. XOR
//   6. SLT
//   7. SLTU
//   8. SLL
//   9. SRL
//  10. SRA
//  11. ADDI
//  12. ANDI
//  13. ORI
//  14. XORI
//  15. LW
//  16. SW
//  17. BEQ
//  18. BNE
//  19. BLT
//  20. BGE
//  21. JAL
//  22. JALR
//  23. LUI
//  24. AUIPC
//
// Additional pipeline verification:
//   Forwarding
//   Load-use hazard / stall
//   Branch flush
// ================================================================

module riscv_pipeline_tb;

    reg clk;
    reg reset;

    integer pass_count;
    integer fail_count;

    reg forwarding_seen;
    reg load_use_stall_seen;
    reg branch_taken_seen;

    integer i;

    // ============================================================
    // DUT
    // ============================================================

    riscv_pipeline dut (
        .clk   (clk),
        .reset (reset)
    );

    // ============================================================
    // CLOCK
    // ============================================================

    initial begin
        clk = 1'b0;

        forever #5 clk = ~clk;
    end

    // ============================================================
    // PIPELINE MECHANISM MONITOR
    // ============================================================
    always @(posedge clk) begin
        if (!reset) begin
            if ((dut.ForwardA != 2'b00) || (dut.ForwardB != 2'b00))
                forwarding_seen = 1'b1;

            if (dut.LoadUseStall === 1'b1)
                load_use_stall_seen = 1'b1;

            if (dut.BranchTaken_EX === 1'b1)
                branch_taken_seen = 1'b1;
        end
    end

    // ============================================================
    // RV32I OPCODES
    // ============================================================

    localparam [6:0] OP_R      = 7'b0110011;
    localparam [6:0] OP_I      = 7'b0010011;
    localparam [6:0] OP_LOAD   = 7'b0000011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [6:0] OP_AUIPC  = 7'b0010111;

    // ============================================================
    // NOP
    // ADDI x0,x0,0
    // ============================================================

    localparam [31:0] NOP = 32'h00000013;

    // ============================================================
    // INSTRUCTION ENCODING FUNCTIONS
    // ============================================================

    // ------------------------------------------------------------
    // R-TYPE
    // ------------------------------------------------------------

    function [31:0] R_TYPE;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;

        begin
            R_TYPE = {
                funct7,
                rs2,
                rs1,
                funct3,
                rd,
                OP_R
            };
        end
    endfunction

    // ------------------------------------------------------------
    // I-TYPE
    // ------------------------------------------------------------

    function [31:0] I_TYPE;
        input signed [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;

        begin
            I_TYPE = {
                imm,
                rs1,
                funct3,
                rd,
                opcode
            };
        end
    endfunction

    // ------------------------------------------------------------
    // S-TYPE
    // ------------------------------------------------------------

    function [31:0] S_TYPE;
        input signed [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;

        begin
            S_TYPE = {
                imm[11:5],
                rs2,
                rs1,
                funct3,
                imm[4:0],
                OP_STORE
            };
        end
    endfunction

    // ------------------------------------------------------------
    // B-TYPE
    //
    // immediate is byte offset
    // ------------------------------------------------------------

    function [31:0] B_TYPE;
        input signed [12:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;

        begin
            B_TYPE = {
                imm[12],
                imm[10:5],
                rs2,
                rs1,
                funct3,
                imm[4:1],
                imm[11],
                OP_BRANCH
            };
        end
    endfunction

    // ------------------------------------------------------------
    // U-TYPE
    // ------------------------------------------------------------

    function [31:0] U_TYPE;
        input [19:0] imm20;
        input [4:0] rd;
        input [6:0] opcode;

        begin
            U_TYPE = {
                imm20,
                rd,
                opcode
            };
        end
    endfunction

    // ------------------------------------------------------------
    // J-TYPE
    //
    // immediate is byte offset
    // ------------------------------------------------------------

    function [31:0] J_TYPE;
        input signed [20:0] imm;
        input [4:0] rd;

        begin
            J_TYPE = {
                imm[20],
                imm[10:1],
                imm[11],
                imm[19:12],
                rd,
                OP_JAL
            };
        end
    endfunction

    // ============================================================
    // RESET + MEMORY INITIALIZATION
    // ============================================================

    task begin_test;
        integer k;

        begin

            reset = 1'b1;

            // Initialize instruction memory with NOPs
            for (k = 0; k < 256; k = k + 1)
                dut.instruction_memory[k] = NOP;

            // Clear data memory
            for (k = 0; k < 256; k = k + 1)
                dut.data_memory[k] = 32'd0;

            // Clear registers
            for (k = 0; k < 32; k = k + 1)
                dut.registers[k] = 32'd0;

            // Hold reset for two clock cycles
            repeat (2)
                @(posedge clk);

        end
    endtask

    // ============================================================
    // RELEASE RESET
    // ============================================================

    task release_reset;

        begin

            @(negedge clk);

            reset = 1'b0;

        end

    endtask

    // ============================================================
    // WAIT FOR PIPELINE
    // ============================================================

    task wait_pipeline;
        input integer cycles;

        integer c;

        begin

            for (c = 0; c < cycles; c = c + 1)
                @(posedge clk);

        
            @(negedge clk);

        end
    endtask

    // ============================================================
    // REGISTER CHECK
    // ============================================================

    task check_reg;

        input [255:0] test_name;
        input [4:0]   reg_num;
        input [31:0]  expected;

        begin

            if (dut.registers[reg_num] === expected) begin

                $display(
                    "PASS: %-25s x%0d = %08h",
                    test_name,
                    reg_num,
                    dut.registers[reg_num]
                );

                pass_count = pass_count + 1;

            end
            else begin

                $display(
                    "FAIL: %-25s x%0d = %08h EXPECTED %08h",
                    test_name,
                    reg_num,
                    dut.registers[reg_num],
                    expected
                );

                fail_count = fail_count + 1;

            end

        end
    endtask

    // ============================================================
    // MEMORY CHECK
    // ============================================================

    task check_mem;

        input [255:0] test_name;
        input integer address;
        input [31:0] expected;

        begin

            if (dut.data_memory[address] === expected) begin

                $display(
                    "PASS: %-25s mem[%0d] = %08h",
                    test_name,
                    address,
                    dut.data_memory[address]
                );

                pass_count = pass_count + 1;

            end
            else begin

                $display(
                    "FAIL: %-25s mem[%0d] = %08h EXPECTED %08h",
                    test_name,
                    address,
                    dut.data_memory[address],
                    expected
                );

                fail_count = fail_count + 1;

            end

        end
    endtask

    // ============================================================
    // TEST SEQUENCE
    // ============================================================

    initial begin

        pass_count = 0;
        fail_count = 0;

        forwarding_seen     = 1'b0;
        load_use_stall_seen = 1'b0;
        branch_taken_seen   = 1'b0;

        clk   = 1'b0;
        reset = 1'b1;

        $display("");
        $display("============================================================");
        $display("          32-BIT 5-STAGE RISC-V PIPELINE");
        $display("             COMPREHENSIVE VERIFICATION");
        $display("============================================================");
        $display("");

        // ========================================================
        // TEST 1 - ADD
        // x1 = 10
        // x2 = 3
        // x3 = x1 + x2 = 13
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(12'd10, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd3,  5'd0, 3'b000, 5'd2, OP_I);
        dut.instruction_memory[2] = R_TYPE(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3);

        release_reset;
        wait_pipeline(10);

        check_reg("ADD", 5'd3, 32'd13);

        // ========================================================
        // TEST 2 - SUB
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(12'd10, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd3,  5'd0, 3'b000, 5'd2, OP_I);
        dut.instruction_memory[2] = R_TYPE(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd3);

        release_reset;
        wait_pipeline(10);

        check_reg("SUB", 5'd3, 32'd7);

        // ========================================================
        // TEST 3 - AND
        // 10 & 3 = 2
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(12'd10, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd3,  5'd0, 3'b000, 5'd2, OP_I);
        dut.instruction_memory[2] = R_TYPE(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd3);

        release_reset;
        wait_pipeline(10);

        check_reg("AND", 5'd3, 32'd2);

        // ========================================================
        // TEST 4 - OR
        // 10 | 3 = 11
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(12'd10, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd3,  5'd0, 3'b000, 5'd2, OP_I);
        dut.instruction_memory[2] = R_TYPE(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd3);

        release_reset;
        wait_pipeline(10);

        check_reg("OR", 5'd3, 32'd11);

        // ========================================================
        // TEST 5 - XOR
        // 10 ^ 3 = 9
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(12'd10, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd3,  5'd0, 3'b000, 5'd2, OP_I);
        dut.instruction_memory[2] = R_TYPE(7'b0000000, 5'd2, 5'd1, 3'b100, 5'd3);

        release_reset;
        wait_pipeline(10);

        check_reg("XOR", 5'd3, 32'd9);

        // ========================================================
        // TEST 6 - SLT
        // -1 < 1 = 1
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(-12'sd1, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd1,   5'd0, 3'b000, 5'd2, OP_I);
        dut.instruction_memory[2] = R_TYPE(7'b0000000, 5'd2, 5'd1, 3'b010, 5'd3);

        release_reset;
        wait_pipeline(10);

        check_reg("SLT", 5'd3, 32'd1);

        // ========================================================
        // TEST 7 - SLTU
        // 0xFFFFFFFF < 1 unsigned = 0
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(-12'sd1, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd1,   5'd0, 3'b000, 5'd2, OP_I);
        dut.instruction_memory[2] = R_TYPE(7'b0000000, 5'd2, 5'd1, 3'b011, 5'd3);

        release_reset;
        wait_pipeline(10);

        check_reg("SLTU", 5'd3, 32'd0);

        // ========================================================
        // TEST 8 - SLL
        // 10 << 3 = 80
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(12'd10, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd3,  5'd0, 3'b000, 5'd2, OP_I);
        dut.instruction_memory[2] = R_TYPE(7'b0000000, 5'd2, 5'd1, 3'b001, 5'd3);

        release_reset;
        wait_pipeline(10);

        check_reg("SLL", 5'd3, 32'd80);

        // ========================================================
        // TEST 9 - SRL
        // 10 >> 3 = 1
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(12'd10, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd3,  5'd0, 3'b000, 5'd2, OP_I);
        dut.instruction_memory[2] = R_TYPE(7'b0000000, 5'd2, 5'd1, 3'b101, 5'd3);

        release_reset;
        wait_pipeline(10);

        check_reg("SRL", 5'd3, 32'd1);

        // ========================================================
        // TEST 10 - SRA
        // -16 >>> 2 = -4
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(-12'sd16, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd2,   5'd0, 3'b000, 5'd2, OP_I);
        dut.instruction_memory[2] = R_TYPE(7'b0100000, 5'd2, 5'd1, 3'b101, 5'd3);

        release_reset;
        wait_pipeline(10);

        check_reg("SRA", 5'd3, 32'hFFFFFFFC);

        // ========================================================
        // TEST 11 - ADDI
        // x1 = 10 + 5 = 15
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(12'd10, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd5,  5'd1, 3'b000, 5'd2, OP_I);

        release_reset;
        wait_pipeline(10);

        check_reg("ADDI", 5'd2, 32'd15);

        // ========================================================
        // TEST 12 - ANDI
        // 10 & 3 = 2
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(12'd10, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd3,  5'd1, 3'b111, 5'd2, OP_I);

        release_reset;
        wait_pipeline(10);

        check_reg("ANDI", 5'd2, 32'd2);

        // ========================================================
        // TEST 13 - ORI
        // 10 | 3 = 11
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(12'd10, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd3,  5'd1, 3'b110, 5'd2, OP_I);

        release_reset;
        wait_pipeline(10);

        check_reg("ORI", 5'd2, 32'd11);

        // ========================================================
        // TEST 14 - XORI
        // 10 ^ 3 = 9
        // ========================================================

        begin_test;

        dut.instruction_memory[0] = I_TYPE(12'd10, 5'd0, 3'b000, 5'd1, OP_I);
        dut.instruction_memory[1] = I_TYPE(12'd3,  5'd1, 3'b100, 5'd2, OP_I);

        release_reset;
        wait_pipeline(10);

        check_reg("XORI", 5'd2, 32'd9);

        // ========================================================
        // TEST 15 - LW
        // data_memory[0] = 123
        // x3 = 123
        // ========================================================

        begin_test;

        dut.data_memory[0] = 32'd123;

        dut.instruction_memory[0] =
            I_TYPE(12'd0, 5'd0, 3'b000, 5'd1, OP_I);

        dut.instruction_memory[1] =
            I_TYPE(12'd0, 5'd1, 3'b010, 5'd3, OP_LOAD);

        release_reset;
        wait_pipeline(12);

        check_reg("LW", 5'd3, 32'd123);

        // ========================================================
        // TEST 16 - SW
        // data_memory[0] should become 123
        // ========================================================

        begin_test;

        dut.instruction_memory[0] =
            I_TYPE(12'd0, 5'd0, 3'b000, 5'd1, OP_I);

        dut.instruction_memory[1] =
            I_TYPE(12'd123, 5'd0, 3'b000, 5'd2, OP_I);

        dut.instruction_memory[2] =
            S_TYPE(12'd0, 5'd2, 5'd1, 3'b010);

        release_reset;
        wait_pipeline(12);

        check_mem("SW", 0, 32'd123);

        // ========================================================
        // TEST 17 - BEQ
        //
        // Branch taken.
        // Wrong-path instruction x3=99 must be flushed.
        // Target writes x3=42.
        // ========================================================

        begin_test;

        dut.instruction_memory[0] =
            I_TYPE(12'd5, 5'd0, 3'b000, 5'd1, OP_I);

        dut.instruction_memory[1] =
            I_TYPE(12'd5, 5'd0, 3'b000, 5'd2, OP_I);

        // PC=8, branch +8 -> PC=16
        dut.instruction_memory[2] =
            B_TYPE(13'sd8, 5'd2, 5'd1, 3'b000);

        // Must be flushed
        dut.instruction_memory[3] =
            I_TYPE(12'd99, 5'd0, 3'b000, 5'd3, OP_I);

        // Branch target
        dut.instruction_memory[4] =
            I_TYPE(12'd42, 5'd0, 3'b000, 5'd3, OP_I);

        release_reset;
        wait_pipeline(14);

        check_reg("BEQ", 5'd3, 32'd42);

        // ========================================================
        // TEST 18 - BNE
        //
        // x1 != x2, branch taken
        // ========================================================

        begin_test;

        dut.instruction_memory[0] =
            I_TYPE(12'd5, 5'd0, 3'b000, 5'd1, OP_I);

        dut.instruction_memory[1] =
            I_TYPE(12'd6, 5'd0, 3'b000, 5'd2, OP_I);

        // PC=8, branch +8 -> PC=16
        dut.instruction_memory[2] =
            B_TYPE(13'sd8, 5'd2, 5'd1, 3'b001);

        dut.instruction_memory[3] =
            I_TYPE(12'd99, 5'd0, 3'b000, 5'd3, OP_I);

        dut.instruction_memory[4] =
            I_TYPE(12'd42, 5'd0, 3'b000, 5'd3, OP_I);

        release_reset;
        wait_pipeline(14);

        check_reg("BNE", 5'd3, 32'd42);

        // ========================================================
        // TEST 19 - BLT
        //
        // 1 < 2 -> taken
        // ========================================================

        begin_test;

        dut.instruction_memory[0] =
            I_TYPE(12'd1, 5'd0, 3'b000, 5'd1, OP_I);

        dut.instruction_memory[1] =
            I_TYPE(12'd2, 5'd0, 3'b000, 5'd2, OP_I);

        // BLT
        dut.instruction_memory[2] =
            B_TYPE(13'sd8, 5'd2, 5'd1, 3'b100);

        dut.instruction_memory[3] =
            I_TYPE(12'd99, 5'd0, 3'b000, 5'd3, OP_I);

        dut.instruction_memory[4] =
            I_TYPE(12'd42, 5'd0, 3'b000, 5'd3, OP_I);

        release_reset;
        wait_pipeline(14);

        check_reg("BLT", 5'd3, 32'd42);

        // ========================================================
        // TEST 20 - BGE
        //
        // 2 >= 1 -> taken
        // ========================================================

        begin_test;

        dut.instruction_memory[0] =
            I_TYPE(12'd2, 5'd0, 3'b000, 5'd1, OP_I);

        dut.instruction_memory[1] =
            I_TYPE(12'd1, 5'd0, 3'b000, 5'd2, OP_I);

        // BGE
        dut.instruction_memory[2] =
            B_TYPE(13'sd8, 5'd2, 5'd1, 3'b101);

        dut.instruction_memory[3] =
            I_TYPE(12'd99, 5'd0, 3'b000, 5'd3, OP_I);

        dut.instruction_memory[4] =
            I_TYPE(12'd42, 5'd0, 3'b000, 5'd3, OP_I);

        release_reset;
        wait_pipeline(14);

        check_reg("BGE", 5'd3, 32'd42);

        // ========================================================
        // TEST 21 - JAL
        //
        // JAL at PC=0
        // target PC=8
        // x5 receives PC+4 = 4
        // ========================================================

        begin_test;

        dut.instruction_memory[0] =
            J_TYPE(21'sd8, 5'd5);

        // Wrong path
        dut.instruction_memory[1] =
            I_TYPE(12'd99, 5'd0, 3'b000, 5'd6, OP_I);

        // Target
        dut.instruction_memory[2] =
            I_TYPE(12'd42, 5'd0, 3'b000, 5'd7, OP_I);

        release_reset;
        wait_pipeline(14);

        check_reg("JAL link", 5'd5, 32'd4);
        check_reg("JAL target", 5'd7, 32'd42);

        // ========================================================
        // TEST 22 - JALR
        //
        // x1 = 16
        // JALR target = 16
        // x5 = PC+4 = 8
        // ========================================================

        begin_test;

        dut.instruction_memory[0] =
            I_TYPE(12'd16, 5'd0, 3'b000, 5'd1, OP_I);

        dut.instruction_memory[1] =
            I_TYPE(12'd0, 5'd1, 3'b000, 5'd5, OP_JALR);

        // Wrong path
        dut.instruction_memory[2] =
            I_TYPE(12'd99, 5'd0, 3'b000, 5'd6, OP_I);

        dut.instruction_memory[3] = NOP;

        // Target address = 16 = instruction_memory[4]
        dut.instruction_memory[4] =
            I_TYPE(12'd42, 5'd0, 3'b000, 5'd7, OP_I);

        release_reset;
        wait_pipeline(16);

        check_reg("JALR link", 5'd5, 32'd8);
        check_reg("JALR target", 5'd7, 32'd42);

        // ========================================================
        // TEST 23 - LUI
        // x3 = 0x12345000
        // ========================================================

        begin_test;

        dut.instruction_memory[0] =
            U_TYPE(20'h12345, 5'd3, OP_LUI);

        release_reset;
        wait_pipeline(10);

        check_reg("LUI", 5'd3, 32'h12345000);

        // ========================================================
        // TEST 24 - AUIPC
        //
        // PC = 0
        // x3 = 0 + 0x00001000
        // ========================================================

        begin_test;

        dut.instruction_memory[0] =
            U_TYPE(20'h00001, 5'd3, OP_AUIPC);

        release_reset;
        wait_pipeline(10);

        check_reg("AUIPC", 5'd3, 32'h00001000);

        // ========================================================
        // ADDITIONAL PIPELINE TEST 1
        // FORWARDING
        // ========================================================

        begin_test;

        forwarding_seen = 1'b0;

        // x1 = 5
        dut.instruction_memory[0] =
            I_TYPE(12'd5, 5'd0, 3'b000, 5'd1, OP_I);

        // x2 = 10
        dut.instruction_memory[1] =
            I_TYPE(12'd10, 5'd0, 3'b000, 5'd2, OP_I);

        // x3 = x1 + x2 = 15
        // Requires forwarding
        dut.instruction_memory[2] =
            R_TYPE(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3);

        // x4 = x3 - x1 = 10
        // Requires forwarding again
        dut.instruction_memory[3] =
            R_TYPE(7'b0100000, 5'd1, 5'd3, 3'b000, 5'd4);

        release_reset;
        wait_pipeline(14);

        check_reg("FORWARDING ADD", 5'd3, 32'd15);
        check_reg("FORWARDING SUB", 5'd4, 32'd10);

        if (forwarding_seen) begin
            $display("PASS: FORWARDING CONTROL     ForwardA/ForwardB asserted");
            pass_count = pass_count + 1;
        end
        else begin
            $display("FAIL: FORWARDING CONTROL     ForwardA/ForwardB never asserted");
            fail_count = fail_count + 1;
        end

        // ========================================================
        // ADDITIONAL PIPELINE TEST 2
        // LOAD-USE HAZARD
        // ========================================================

        begin_test;

        load_use_stall_seen = 1'b0;

        // x1 = 0
        dut.instruction_memory[0] =
            I_TYPE(12'd0, 5'd0, 3'b000, 5'd1, OP_I);

        // x2 = 7
        dut.instruction_memory[1] =
            I_TYPE(12'd7, 5'd0, 3'b000, 5'd2, OP_I);

        // store 7
        dut.instruction_memory[2] =
            S_TYPE(12'd0, 5'd2, 5'd1, 3'b010);

        // load 7 into x3
        dut.instruction_memory[3] =
            I_TYPE(12'd0, 5'd1, 3'b010, 5'd3, OP_LOAD);

        // Immediately use loaded value
        // x4 = x3 + x2 = 14
        //
        // This specifically exercises load-use hazard detection
        // and pipeline stall.
        dut.instruction_memory[4] =
            R_TYPE(7'b0000000, 5'd2, 5'd3, 3'b000, 5'd4);

        release_reset;
        wait_pipeline(16);

        check_reg("LOAD-USE LW", 5'd3, 32'd7);
        check_reg("LOAD-USE ADD", 5'd4, 32'd14);

        if (load_use_stall_seen) begin
            $display("PASS: LOAD-USE STALL       LoadUseStall asserted");
            pass_count = pass_count + 1;
        end
        else begin
            $display("FAIL: LOAD-USE STALL       LoadUseStall never asserted");
            fail_count = fail_count + 1;
        end

        // ========================================================
        // ADDITIONAL PIPELINE TEST 3
        // BRANCH FLUSH
        // ========================================================

        begin_test;

        branch_taken_seen = 1'b0;

        // x1 = 5
        dut.instruction_memory[0] =
            I_TYPE(12'd5, 5'd0, 3'b000, 5'd1, OP_I);

        // x2 = 5
        dut.instruction_memory[1] =
            I_TYPE(12'd5, 5'd0, 3'b000, 5'd2, OP_I);

        // BEQ taken
        dut.instruction_memory[2] =
            B_TYPE(13'sd12, 5'd2, 5'd1, 3'b000);

        // Wrong path instruction
        dut.instruction_memory[3] =
            I_TYPE(12'd111, 5'd0, 3'b000, 5'd8, OP_I);

        // Wrong path instruction
        dut.instruction_memory[4] =
            I_TYPE(12'd222, 5'd0, 3'b000, 5'd9, OP_I);

        // Target at PC=20
        dut.instruction_memory[5] =
            I_TYPE(12'd42, 5'd0, 3'b000, 5'd10, OP_I);

        release_reset;
        wait_pipeline(16);

        check_reg("BRANCH FLUSH target", 5'd10, 32'd42);
        check_reg("BRANCH FLUSH x8", 5'd8, 32'd0);
        check_reg("BRANCH FLUSH x9", 5'd9, 32'd0);

        if (branch_taken_seen) begin
            $display("PASS: BRANCH TAKE/FLUSH    BranchTaken_EX asserted");
            pass_count = pass_count + 1;
        end
        else begin
            $display("FAIL: BRANCH TAKE/FLUSH    BranchTaken_EX never asserted");
            fail_count = fail_count + 1;
        end

        // ========================================================
        // FINAL RESULT
        // ========================================================

        $display("");
        $display("============================================================");
        $display("                    VERIFICATION RESULT");
        $display("============================================================");

        $display("TOTAL PASS = %0d", pass_count);
        $display("TOTAL FAIL = %0d", fail_count);

        if (fail_count == 0) begin

            $display("");
            $display("============================================================");
            $display("              ALL TESTS PASSED");
            $display("============================================================");
            $display("");
            $display("24 RV32I instruction tests       : PASS");
            $display("Forwarding functional/control    : PASS");
            $display("Load-use functional/stall        : PASS");
            $display("Branch functional/take/flush     : PASS");
            $display("");
            $display("32-BIT 5-STAGE RISC-V PIPELINE");
            $display("VERIFICATION SUCCESSFUL");
            $display("============================================================");

        end
        else begin

            $display("");
            $display("============================================================");
            $display("                  VERIFICATION FAILED");
            $display("============================================================");
            $display("Check the FAIL messages above.");
            $display("============================================================");

        end

        // Allow waveform inspection
        #20;

        $finish;

    end

endmodule