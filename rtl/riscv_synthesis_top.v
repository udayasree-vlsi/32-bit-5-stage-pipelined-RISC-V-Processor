`timescale 1ns/1ps

module riscv_synthesis_top (
    input  wire        clk,
    input  wire        reset,

    output wire [31:0] debug_pc,
    output wire [31:0] debug_instruction,
    output wire [31:0] debug_alu_result,
    output wire [31:0] debug_wb_data
);

    riscv_pipeline u_core (
        .clk   (clk),
        .reset (reset)
    );

    assign debug_pc          = u_core.PC;
    assign debug_instruction = u_core.instruction;
    assign debug_alu_result  = u_core.EX_ALUResult;
    assign debug_wb_data     = u_core.WB_WriteBackData;

endmodule