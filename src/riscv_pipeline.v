`timescale 1ns/1ps

// ============================================================================
// 32-bit 5-stage pipelined RISC-V RV32I processor
// Single-file Verilog-2001 implementation for Vivado
// Module name: riscv_pipeline
// Stages: IF -> ID -> EX -> MEM -> WB
// ============================================================================

module riscv_pipeline (
    input wire clk,
    input wire reset,
    output wire [31:0] result
);

assign result = WB_WriteBackData;

    // ------------------------------------------------------------------------
    // Opcodes
    // ------------------------------------------------------------------------
    localparam [6:0] OP_R       = 7'b0110011;
    localparam [6:0] OP_I_ALU  = 7'b0010011;
    localparam [6:0] OP_LOAD   = 7'b0000011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [6:0] OP_AUIPC  = 7'b0010111;

    // ALU control
    localparam [4:0] ALU_ADD  = 5'd0;
    localparam [4:0] ALU_SUB  = 5'd1;
    localparam [4:0] ALU_AND  = 5'd2;
    localparam [4:0] ALU_OR   = 5'd3;
    localparam [4:0] ALU_XOR  = 5'd4;
    localparam [4:0] ALU_SLT  = 5'd5;
    localparam [4:0] ALU_SLTU = 5'd6;
    localparam [4:0] ALU_SLL  = 5'd7;
    localparam [4:0] ALU_SRL  = 5'd8;
    localparam [4:0] ALU_SRA  = 5'd9;

    // Write-back select
    localparam [1:0] WB_ALU = 2'd0;
    localparam [1:0] WB_MEM = 2'd1;
    localparam [1:0] WB_PC4 = 2'd2;
    localparam [1:0] WB_IMM = 2'd3;

    // ------------------------------------------------------------------------
    // PC / Memories / Register File
    // ------------------------------------------------------------------------
    reg [31:0] PC;
    reg [31:0] instruction_memory [0:255];
    reg [31:0] data_memory        [0:255];
    reg [31:0] registers          [0:31];

    wire [31:0] instruction;
    wire [31:0] PC_plus4;

    assign instruction = instruction_memory[PC[9:2]];
    assign PC_plus4 = PC + 32'd4;

    // ------------------------------------------------------------------------
    // IF/ID
    // ------------------------------------------------------------------------
    reg        IF_ID_valid;
    reg [31:0] IF_ID_PC;
    reg [31:0] IF_ID_PCPlus4;
    reg [31:0] IF_ID_Instruction;

    // ------------------------------------------------------------------------
    // ID stage decode
    // ------------------------------------------------------------------------
    wire [6:0] id_opcode = IF_ID_Instruction[6:0];
    wire [4:0] id_rd     = IF_ID_Instruction[11:7];
    wire [2:0] id_funct3 = IF_ID_Instruction[14:12];
    wire [4:0] id_rs1    = IF_ID_Instruction[19:15];
    wire [4:0] id_rs2    = IF_ID_Instruction[24:20];
    wire [6:0] id_funct7 = IF_ID_Instruction[31:25];

    // Register-file read with explicit WB bypass. This removes the
    // same-cycle WB -> ID read dependency and makes the pipeline robust
    // across simulators/FPGA implementations.
    wire [31:0] id_rs1_data =
        (id_rs1 == 5'd0) ? 32'd0 :
        ((MEM_WB_valid && MEM_WB_RegWrite && (MEM_WB_rd != 5'd0) &&
          (MEM_WB_rd == id_rs1)) ? WB_WriteBackData : registers[id_rs1]);

    wire [31:0] id_rs2_data =
        (id_rs2 == 5'd0) ? 32'd0 :
        ((MEM_WB_valid && MEM_WB_RegWrite && (MEM_WB_rd != 5'd0) &&
          (MEM_WB_rd == id_rs2)) ? WB_WriteBackData : registers[id_rs2]);

    reg        id_regwrite;
    reg        id_memread;
    reg        id_memwrite;
    reg        id_branch;
    reg        id_jump;
    reg        id_jalr;
    reg        id_alusrc;
    reg        id_auipc;
    reg [4:0]  id_alucontrol;
    reg [1:0]  id_wbsel;
    reg [31:0] id_imm;
    reg        id_use_rs1;
    reg        id_use_rs2;
    reg [2:0]  id_branch_type;

    // ------------------------------------------------------------------------
    // Immediate / control decoder
    // ------------------------------------------------------------------------
    always @(*) begin
        id_regwrite    = 1'b0;
        id_memread     = 1'b0;
        id_memwrite    = 1'b0;
        id_branch      = 1'b0;
        id_jump        = 1'b0;
        id_jalr        = 1'b0;
        id_alusrc      = 1'b0;
        id_auipc       = 1'b0;
        id_alucontrol  = ALU_ADD;
        id_wbsel       = WB_ALU;
        id_imm         = 32'd0;
        id_use_rs1     = 1'b0;
        id_use_rs2     = 1'b0;
        id_branch_type = 3'b000;

        case (id_opcode)
            OP_R: begin
                id_regwrite = 1'b1;
                id_use_rs1  = 1'b1;
                id_use_rs2  = 1'b1;
                case (id_funct3)
                    3'b000: id_alucontrol = (id_funct7 == 7'b0100000) ? ALU_SUB : ALU_ADD;
                    3'b111: id_alucontrol = ALU_AND;
                    3'b110: id_alucontrol = ALU_OR;
                    3'b100: id_alucontrol = ALU_XOR;
                    3'b010: id_alucontrol = ALU_SLT;
                    3'b011: id_alucontrol = ALU_SLTU;
                    3'b001: id_alucontrol = ALU_SLL;
                    3'b101: id_alucontrol = (id_funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;
                    default: id_alucontrol = ALU_ADD;
                endcase
            end

            OP_I_ALU: begin
                id_regwrite = 1'b1;
                id_alusrc   = 1'b1;
                id_use_rs1  = 1'b1;
                case (id_funct3)
                    3'b000: begin id_alucontrol = ALU_ADD;  id_imm = {{20{IF_ID_Instruction[31]}},IF_ID_Instruction[31:20]}; end
                    3'b111: begin id_alucontrol = ALU_AND;  id_imm = {{20{IF_ID_Instruction[31]}},IF_ID_Instruction[31:20]}; end
                    3'b110: begin id_alucontrol = ALU_OR;   id_imm = {{20{IF_ID_Instruction[31]}},IF_ID_Instruction[31:20]}; end
                    3'b100: begin id_alucontrol = ALU_XOR;  id_imm = {{20{IF_ID_Instruction[31]}},IF_ID_Instruction[31:20]}; end
                    3'b010: begin id_alucontrol = ALU_SLT;  id_imm = {{20{IF_ID_Instruction[31]}},IF_ID_Instruction[31:20]}; end
                    3'b011: begin id_alucontrol = ALU_SLTU; id_imm = {{20{IF_ID_Instruction[31]}},IF_ID_Instruction[31:20]}; end
                    3'b001: begin id_alucontrol = ALU_SLL;  id_imm = {27'd0,IF_ID_Instruction[24:20]}; end
                    3'b101: begin
                        id_alucontrol = (id_funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;
                        id_imm = {27'd0,IF_ID_Instruction[24:20]};
                    end
                    default: begin id_alucontrol = ALU_ADD; id_imm = 32'd0; end
                endcase
            end

            OP_LOAD: begin
                if (id_funct3 == 3'b010) begin
                    id_regwrite   = 1'b1;
                    id_memread    = 1'b1;
                    id_alusrc     = 1'b1;
                    id_wbsel      = WB_MEM;
                    id_use_rs1    = 1'b1;
                    id_alucontrol = ALU_ADD;
                    id_imm = {{20{IF_ID_Instruction[31]}},IF_ID_Instruction[31:20]};
                end
            end

            OP_STORE: begin
                if (id_funct3 == 3'b010) begin
                    id_memwrite   = 1'b1;
                    id_alusrc     = 1'b1;
                    id_use_rs1    = 1'b1;
                    id_use_rs2    = 1'b1;
                    id_alucontrol = ALU_ADD;
                    id_imm = {{20{IF_ID_Instruction[31]}},IF_ID_Instruction[31:25],IF_ID_Instruction[11:7]};
                end
            end

            OP_BRANCH: begin
                id_branch = 1'b1;
                id_use_rs1 = 1'b1;
                id_use_rs2 = 1'b1;
                id_branch_type = id_funct3;
                id_imm = {{19{IF_ID_Instruction[31]}},IF_ID_Instruction[31],IF_ID_Instruction[7],IF_ID_Instruction[30:25],IF_ID_Instruction[11:8],1'b0};
            end

            OP_JAL: begin
                id_regwrite = 1'b1;
                id_jump = 1'b1;
                id_wbsel = WB_PC4;
                id_imm = {{11{IF_ID_Instruction[31]}},IF_ID_Instruction[31],IF_ID_Instruction[19:12],IF_ID_Instruction[20],IF_ID_Instruction[30:21],1'b0};
            end

            OP_JALR: begin
                if (id_funct3 == 3'b000) begin
                    id_regwrite = 1'b1;
                    id_jump = 1'b1;
                    id_jalr = 1'b1;
                    id_wbsel = WB_PC4;
                    id_alusrc = 1'b1;
                    id_use_rs1 = 1'b1;
                    id_imm = {{20{IF_ID_Instruction[31]}},IF_ID_Instruction[31:20]};
                end
            end

            OP_LUI: begin
                id_regwrite = 1'b1;
                id_wbsel = WB_IMM;
                id_imm = {IF_ID_Instruction[31:12],12'd0};
            end

           OP_AUIPC: begin
           
           id_regwrite   = 1'b1;
           id_auipc      = 1'b1;
           id_alusrc     = 1'b1;  // IMPORTANT: use immediate as ALU operand B
           id_wbsel      = WB_ALU;
           id_use_rs1    = 1'b0;
           id_use_rs2    = 1'b0;
           id_alucontrol = ALU_ADD;
           id_imm        = {IF_ID_Instruction[31:12],12'd0};
           end

            default: begin end
        endcase
    end

    // ------------------------------------------------------------------------
    // ID/EX
    // ------------------------------------------------------------------------
    reg        ID_EX_valid;
    reg [31:0] ID_EX_PC;
    reg [31:0] ID_EX_PCPlus4;
    reg [31:0] ID_EX_rs1_data;
    reg [31:0] ID_EX_rs2_data;
    reg [31:0] ID_EX_imm;
    reg [4:0]  ID_EX_rs1;
    reg [4:0]  ID_EX_rs2;
    reg [4:0]  ID_EX_rd;
    reg [4:0]  ID_EX_alucontrol;
    reg [2:0]  ID_EX_branch_type;
    reg        ID_EX_RegWrite;
    reg        ID_EX_MemRead;
    reg        ID_EX_MemWrite;
    reg        ID_EX_Branch;
    reg        ID_EX_Jump;
    reg        ID_EX_JALR;
    reg        ID_EX_ALUSrc;
    reg        ID_EX_AUIPC;
    reg [1:0]  ID_EX_WBSel;

    // ------------------------------------------------------------------------
    // Forwarding / EX
    // ------------------------------------------------------------------------
    reg [1:0] ForwardA;
    reg [1:0] ForwardB;
    reg [31:0] EX_operandA;
    reg [31:0] EX_operandB_reg;
    reg [31:0] EX_operandB;
    reg [31:0] EX_ALUResult;

    // ------------------------------------------------------------------------
    // EX/MEM
    // ------------------------------------------------------------------------
    reg        EX_MEM_valid;
    reg [31:0] EX_MEM_ALUResult;
    reg [31:0] EX_MEM_WriteData;
    reg [31:0] EX_MEM_PCPlus4;
    reg [31:0] EX_MEM_Immediate;
    reg [4:0]  EX_MEM_rd;
    reg        EX_MEM_RegWrite;
    reg        EX_MEM_MemRead;
    reg        EX_MEM_MemWrite;
    reg [1:0]  EX_MEM_WBSel;

    // ------------------------------------------------------------------------
    // MEM
    // ------------------------------------------------------------------------
    reg [31:0] MEM_ReadData;
    always @(*) begin
        if (EX_MEM_valid && EX_MEM_MemRead)
            MEM_ReadData = data_memory[EX_MEM_ALUResult[9:2]];
        else
            MEM_ReadData = 32'd0;
    end

    // ------------------------------------------------------------------------
    // MEM/WB
    // ------------------------------------------------------------------------
    reg        MEM_WB_valid;
    reg [31:0] MEM_WB_ALUResult;
    reg [31:0] MEM_WB_ReadData;
    reg [31:0] MEM_WB_PCPlus4;
    reg [31:0] MEM_WB_Immediate;
    reg [4:0]  MEM_WB_rd;
    reg        MEM_WB_RegWrite;
    reg [1:0]  MEM_WB_WBSel;
    reg [31:0] WB_WriteBackData;

    // ------------------------------------------------------------------------
    // Forwarding unit
    // ------------------------------------------------------------------------
    always @(*) begin
        ForwardA = 2'b00;
        ForwardB = 2'b00;

        if (ID_EX_rs1 != 5'd0) begin
            if (EX_MEM_valid && EX_MEM_RegWrite && !EX_MEM_MemRead &&
                (EX_MEM_rd != 5'd0) && (EX_MEM_rd == ID_EX_rs1))
                ForwardA = 2'b10;
            else if (MEM_WB_valid && MEM_WB_RegWrite &&
                     (MEM_WB_rd != 5'd0) && (MEM_WB_rd == ID_EX_rs1))
                ForwardA = 2'b01;
        end

        if (ID_EX_rs2 != 5'd0) begin
            if (EX_MEM_valid && EX_MEM_RegWrite && !EX_MEM_MemRead &&
                (EX_MEM_rd != 5'd0) && (EX_MEM_rd == ID_EX_rs2))
                ForwardB = 2'b10;
            else if (MEM_WB_valid && MEM_WB_RegWrite &&
                     (MEM_WB_rd != 5'd0) && (MEM_WB_rd == ID_EX_rs2))
                ForwardB = 2'b01;
        end
    end

    always @(*) begin
        case (ForwardA)
            2'b10: EX_operandA = EX_MEM_ALUResult;
            2'b01: EX_operandA = WB_WriteBackData;
            default: EX_operandA = ID_EX_rs1_data;
        endcase

        case (ForwardB)
            2'b10: EX_operandB_reg = EX_MEM_ALUResult;
            2'b01: EX_operandB_reg = WB_WriteBackData;
            default: EX_operandB_reg = ID_EX_rs2_data;
        endcase

        if (ID_EX_AUIPC)
            EX_operandA = ID_EX_PC;

        if (ID_EX_ALUSrc)
            EX_operandB = ID_EX_imm;
        else
            EX_operandB = EX_operandB_reg;
    end

    always @(*) begin
        case (ID_EX_alucontrol)
            ALU_ADD:  EX_ALUResult = EX_operandA + EX_operandB;
            ALU_SUB:  EX_ALUResult = EX_operandA - EX_operandB;
            ALU_AND:  EX_ALUResult = EX_operandA & EX_operandB;
            ALU_OR:   EX_ALUResult = EX_operandA | EX_operandB;
            ALU_XOR:  EX_ALUResult = EX_operandA ^ EX_operandB;
            ALU_SLT:  EX_ALUResult = ($signed(EX_operandA) < $signed(EX_operandB)) ? 32'd1 : 32'd0;
            ALU_SLTU: EX_ALUResult = (EX_operandA < EX_operandB) ? 32'd1 : 32'd0;
            ALU_SLL:  EX_ALUResult = EX_operandA << EX_operandB[4:0];
            ALU_SRL:  EX_ALUResult = EX_operandA >> EX_operandB[4:0];
            ALU_SRA:  EX_ALUResult = $signed(EX_operandA) >>> EX_operandB[4:0];
            default:  EX_ALUResult = 32'd0;
        endcase
    end

    // ------------------------------------------------------------------------
    // Branch / jump resolution in EX
    // ------------------------------------------------------------------------
    reg BranchTaken_EX;
    reg [31:0] BranchTarget_EX;

    always @(*) begin
        BranchTaken_EX = 1'b0;

        if (ID_EX_Jump) begin
            BranchTaken_EX = 1'b1;
        end
        else if (ID_EX_Branch) begin
            case (ID_EX_branch_type)
                3'b000: BranchTaken_EX = (EX_operandA == EX_operandB_reg); // BEQ
                3'b001: BranchTaken_EX = (EX_operandA != EX_operandB_reg); // BNE
                3'b100: BranchTaken_EX = ($signed(EX_operandA) < $signed(EX_operandB_reg));
                3'b101: BranchTaken_EX = ($signed(EX_operandA) >= $signed(EX_operandB_reg));
                3'b110: BranchTaken_EX = (EX_operandA < EX_operandB_reg);
                3'b111: BranchTaken_EX = (EX_operandA >= EX_operandB_reg);
                default: BranchTaken_EX = 1'b0;
            endcase
        end

        if (ID_EX_JALR)
            BranchTarget_EX = (EX_operandA + ID_EX_imm) & 32'hFFFFFFFE;
        else
            BranchTarget_EX = ID_EX_PC + ID_EX_imm;
    end

    // ------------------------------------------------------------------------
    // WB mux
    // ------------------------------------------------------------------------
    always @(*) begin
        case (MEM_WB_WBSel)
            WB_ALU: WB_WriteBackData = MEM_WB_ALUResult;
            WB_MEM: WB_WriteBackData = MEM_WB_ReadData;
            WB_PC4: WB_WriteBackData = MEM_WB_PCPlus4;
            WB_IMM: WB_WriteBackData = MEM_WB_Immediate;
            default: WB_WriteBackData = MEM_WB_ALUResult;
        endcase
    end

    // ------------------------------------------------------------------------
    // Load-use hazard
    // ------------------------------------------------------------------------
    wire LoadUseStall;
    assign LoadUseStall =
        ID_EX_valid && ID_EX_MemRead && (ID_EX_rd != 5'd0) && IF_ID_valid &&
        ((id_use_rs1 && (id_rs1 == ID_EX_rd)) ||
         (id_use_rs2 && (id_rs2 == ID_EX_rd)));

    // ------------------------------------------------------------------------
    // Helper: bubble ID/EX
    // ------------------------------------------------------------------------
    task clear_id_ex;
    begin
        ID_EX_valid       <= 1'b0;
        ID_EX_PC          <= 32'd0;
        ID_EX_PCPlus4     <= 32'd0;
        ID_EX_rs1_data    <= 32'd0;
        ID_EX_rs2_data    <= 32'd0;
        ID_EX_imm         <= 32'd0;
        ID_EX_rs1         <= 5'd0;
        ID_EX_rs2         <= 5'd0;
        ID_EX_rd          <= 5'd0;
        ID_EX_alucontrol  <= ALU_ADD;
        ID_EX_branch_type <= 3'd0;
        ID_EX_RegWrite    <= 1'b0;
        ID_EX_MemRead     <= 1'b0;
        ID_EX_MemWrite    <= 1'b0;
        ID_EX_Branch      <= 1'b0;
        ID_EX_Jump        <= 1'b0;
        ID_EX_JALR        <= 1'b0;
        ID_EX_ALUSrc      <= 1'b0;
        ID_EX_AUIPC       <= 1'b0;
        ID_EX_WBSel       <= WB_ALU;
    end
    endtask

    // ------------------------------------------------------------------------
    // Initialization for simulation and FPGA-friendly deterministic startup
    // ------------------------------------------------------------------------
    integer i;
    initial begin
        PC = 32'd0;

        IF_ID_valid = 1'b0;
        IF_ID_PC = 32'd0;
        IF_ID_PCPlus4 = 32'd0;
        IF_ID_Instruction = 32'd0;

        ID_EX_valid = 1'b0;
        ID_EX_PC = 32'd0;
        ID_EX_PCPlus4 = 32'd0;
        ID_EX_rs1_data = 32'd0;
        ID_EX_rs2_data = 32'd0;
        ID_EX_imm = 32'd0;
        ID_EX_rs1 = 5'd0;
        ID_EX_rs2 = 5'd0;
        ID_EX_rd = 5'd0;
        ID_EX_alucontrol = ALU_ADD;
        ID_EX_branch_type = 3'd0;
        ID_EX_RegWrite = 1'b0;
        ID_EX_MemRead = 1'b0;
        ID_EX_MemWrite = 1'b0;
        ID_EX_Branch = 1'b0;
        ID_EX_Jump = 1'b0;
        ID_EX_JALR = 1'b0;
        ID_EX_ALUSrc = 1'b0;
        ID_EX_AUIPC = 1'b0;
        ID_EX_WBSel = WB_ALU;

        EX_MEM_valid = 1'b0;
        EX_MEM_ALUResult = 32'd0;
        EX_MEM_WriteData = 32'd0;
        EX_MEM_PCPlus4 = 32'd0;
        EX_MEM_Immediate = 32'd0;
        EX_MEM_rd = 5'd0;
        EX_MEM_RegWrite = 1'b0;
        EX_MEM_MemRead = 1'b0;
        EX_MEM_MemWrite = 1'b0;
        EX_MEM_WBSel = WB_ALU;

        MEM_WB_valid = 1'b0;
        MEM_WB_ALUResult = 32'd0;
        MEM_WB_ReadData = 32'd0;
        MEM_WB_PCPlus4 = 32'd0;
        MEM_WB_Immediate = 32'd0;
        MEM_WB_rd = 5'd0;
        MEM_WB_RegWrite = 1'b0;
        MEM_WB_WBSel = WB_ALU;

        for (i = 0; i < 256; i = i + 1) begin
            instruction_memory[i] = 32'd0;
            data_memory[i] = 32'd0;
        end
        for (i = 0; i < 32; i = i + 1)
            registers[i] = 32'd0;
    end

    // ------------------------------------------------------------------------
    // Sequential pipeline
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            PC <= 32'd0;

            IF_ID_valid <= 1'b0;
            IF_ID_PC <= 32'd0;
            IF_ID_PCPlus4 <= 32'd0;
            IF_ID_Instruction <= 32'd0;

            clear_id_ex;

            EX_MEM_valid <= 1'b0;
            EX_MEM_ALUResult <= 32'd0;
            EX_MEM_WriteData <= 32'd0;
            EX_MEM_PCPlus4 <= 32'd0;
            EX_MEM_Immediate <= 32'd0;
            EX_MEM_rd <= 5'd0;
            EX_MEM_RegWrite <= 1'b0;
            EX_MEM_MemRead <= 1'b0;
            EX_MEM_MemWrite <= 1'b0;
            EX_MEM_WBSel <= WB_ALU;

            MEM_WB_valid <= 1'b0;
            MEM_WB_ALUResult <= 32'd0;
            MEM_WB_ReadData <= 32'd0;
            MEM_WB_PCPlus4 <= 32'd0;
            MEM_WB_Immediate <= 32'd0;
            MEM_WB_rd <= 5'd0;
            MEM_WB_RegWrite <= 1'b0;
            MEM_WB_WBSel <= WB_ALU;

            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'd0;
        end
        else begin
            // WB
            if (MEM_WB_valid && MEM_WB_RegWrite && (MEM_WB_rd != 5'd0))
                registers[MEM_WB_rd] <= WB_WriteBackData;
            registers[0] <= 32'd0;

            // MEM -> WB
            MEM_WB_valid <= EX_MEM_valid;
            MEM_WB_ALUResult <= EX_MEM_ALUResult;
            MEM_WB_ReadData <= MEM_ReadData;
            MEM_WB_PCPlus4 <= EX_MEM_PCPlus4;
            MEM_WB_Immediate <= EX_MEM_Immediate;
            MEM_WB_rd <= EX_MEM_rd;
            MEM_WB_RegWrite <= EX_MEM_RegWrite;
            MEM_WB_WBSel <= EX_MEM_WBSel;

            // Store in MEM
            if (EX_MEM_valid && EX_MEM_MemWrite)
                data_memory[EX_MEM_ALUResult[9:2]] <= EX_MEM_WriteData;

            // EX -> MEM
            EX_MEM_valid <= ID_EX_valid;
            EX_MEM_ALUResult <= EX_ALUResult;
            EX_MEM_WriteData <= EX_operandB_reg;
            EX_MEM_PCPlus4 <= ID_EX_PCPlus4;
            EX_MEM_Immediate <= ID_EX_imm;
            EX_MEM_rd <= ID_EX_rd;
            EX_MEM_RegWrite <= ID_EX_RegWrite;
            EX_MEM_MemRead <= ID_EX_MemRead;
            EX_MEM_MemWrite <= ID_EX_MemWrite;
            EX_MEM_WBSel <= ID_EX_WBSel;

            // Control priority: taken branch/jump > load-use stall > normal
            if (BranchTaken_EX) begin
                PC <= BranchTarget_EX;

                // Flush younger instruction in IF/ID
                IF_ID_valid <= 1'b0;
                IF_ID_PC <= 32'd0;
                IF_ID_PCPlus4 <= 32'd0;
                IF_ID_Instruction <= 32'd0;

                // Flush younger instruction in ID/EX
                clear_id_ex;
            end
            else if (LoadUseStall) begin
                // Hold fetch and decode instruction; insert one bubble in EX
                PC <= PC;
                IF_ID_valid <= IF_ID_valid;
                IF_ID_PC <= IF_ID_PC;
                IF_ID_PCPlus4 <= IF_ID_PCPlus4;
                IF_ID_Instruction <= IF_ID_Instruction;
                clear_id_ex;
            end
            else begin
                // Normal IF
                PC <= PC_plus4;
                IF_ID_valid <= 1'b1;
                IF_ID_PC <= PC;
                IF_ID_PCPlus4 <= PC_plus4;
                IF_ID_Instruction <= instruction;

                // Normal ID -> EX
                ID_EX_valid <= IF_ID_valid;
                ID_EX_PC <= IF_ID_PC;
                ID_EX_PCPlus4 <= IF_ID_PCPlus4;
                ID_EX_rs1_data <= id_rs1_data;
                ID_EX_rs2_data <= id_rs2_data;
                ID_EX_imm <= id_imm;
                ID_EX_rs1 <= id_rs1;
                ID_EX_rs2 <= id_rs2;
                ID_EX_rd <= id_rd;
                ID_EX_alucontrol <= id_alucontrol;
                ID_EX_branch_type <= id_branch_type;
                ID_EX_RegWrite <= id_regwrite;
                ID_EX_MemRead <= id_memread;
                ID_EX_MemWrite <= id_memwrite;
                ID_EX_Branch <= id_branch;
                ID_EX_Jump <= id_jump;
                ID_EX_JALR <= id_jalr;
                ID_EX_ALUSrc <= id_alusrc;
                ID_EX_AUIPC <= id_auipc;
                ID_EX_WBSel <= id_wbsel;
            end
        end
    end

endmodule

// Optional wrapper with the name used by some older testbenches.
