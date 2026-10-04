# 32-bit 5-Stage Pipelined RISC-V Processor — RTL to GDSII

## Overview

This project implements a **32-bit 5-stage pipelined RISC-V RV32I processor** in **Verilog-2001** and takes the design through an **RTL-to-GDSII physical design flow using OpenLane** and the **Sky130 HD standard-cell library**.

The processor follows the classical five-stage pipeline:

**IF → ID → EX → MEM → WB**

The project demonstrates the complete digital VLSI implementation flow from RTL design and verification to synthesis, floorplanning, placement, clock-tree synthesis, routing, parasitic extraction, physical verification, and final GDSII generation.

---

## Processor Architecture

The processor is organized into five pipeline stages:

| Stage | Function |
|---|---|
| IF — Instruction Fetch | Fetches the instruction and updates the program counter |
| ID — Instruction Decode | Decodes the instruction and reads register operands |
| EX — Execute | Performs ALU operations and branch calculations |
| MEM — Memory Access | Performs load/store memory operations |
| WB — Write Back | Writes the result back to the register file |

### Supported RV32I Instruction Classes

The RTL implements support for:

- Register-register arithmetic and logical instructions
- Immediate arithmetic and logical instructions
- Load and store instructions
- Conditional branch instructions
- JAL and JALR control-transfer instructions
- LUI
- AUIPC

### ALU Operations

The processor includes operations such as:

- ADD
- SUB
- AND
- OR
- XOR
- SLT
- SLTU
- SLL
- SRL
- SRA

---

## RTL Implementation

The processor is implemented as a single Verilog-2001 source file:

```text
src/riscv_pipeline.v
```

Top-level module:

```text
riscv_pipeline
```

Ports:

```text
clk
reset
result[31:0]
```

The RTL is designed for synthesis and physical implementation using the OpenLane flow.

---

## RTL-to-GDSII Flow

The complete implementation flow is:

```text
                 RISC-V RTL
                     │
                     ▼
              RTL Simulation
                     │
                     ▼
                 Synthesis
                     │
                     ▼
                Floorplanning
                     │
                     ▼
                 Placement
                     │
                     ▼
          Clock Tree Synthesis (CTS)
                     │
                     ▼
                  Routing
                     │
                     ▼
            SPEF Extraction
                     │
                     ▼
             Timing Analysis
                     │
                     ▼
              DRC / LVS Checks
                     │
                     ▼
                 Final GDSII
```

The physical implementation was performed using **OpenLane** with the **Sky130 HD standard-cell library**.

---

## OpenLane Configuration

The main configuration is stored in:

```text
config.json
```

Important parameters:

| Parameter | Value |
|---|---:|
| Design name | `riscv_pipeline` |
| Clock port | `clk` |
| Clock period | 10 ns |
| Target clock frequency | 100 MHz |
| FP core utilization | 15% |
| Placement target density | 55% |
| Floorplan aspect ratio | 1.0 |
| Clock Tree Synthesis | Enabled |
| SPEF extraction | Enabled |
| Standard-cell library | `sky130_fd_sc_hd` |

The 10 ns clock constraint corresponds to:

\[
f = \frac{1}{T}
\]

\[
f = \frac{1}{10\,ns} = 100\,MHz
\]

---

## Physical Design Results

The following values were obtained directly from the completed OpenLane run.

| Metric | Result |
|---|---:|
| Flow status | **Completed** |
| Technology | **Sky130 HD** |
| Clock period | **10 ns** |
| Clock constraint | **100 MHz** |
| WNS | **0 ns** |
| TNS | **0 ns** |
| Die area | **0.001969 mm²** |
| Core area | **763.232 µm²** |
| Total cells | **129** |
| Wire length | **375 µm** |
| Vias | **81** |
| Core utilization | **15%** |
| Placement target density | **55%** |
| TritonRoute violations | **0** |
| Short violations | **0** |
| Metal spacing violations | **0** |
| Off-grid violations | **0** |
| Magic violations | **0** |
| Pin antenna violations | **0** |
| Net antenna violations | **0** |
| LVS errors | **0** |

### Timing Result

The design successfully met the imposed **10 ns (100 MHz) clock constraint**:

```text
WNS = 0 ns
TNS = 0 ns
```

This indicates that no negative timing slack was reported for the configured clock constraint.

> **Note:** 100 MHz is the applied clock constraint, not a claim of the absolute maximum operating frequency of the processor.

---

## Final Physical Design Outputs

The final OpenLane outputs are stored in:

```text
openlane_results/
```

Important files include:

```text
openlane_results/
├── metrics.csv
├── riscv_pipeline.gds
├── riscv_pipeline.def
├── riscv_pipeline.lef
├── riscv_pipeline.nl.v
└── riscv_pipeline.sdc
```

### GDSII

```text
openlane_results/riscv_pipeline.gds
```

The final GDSII file was successfully generated.

### DEF

```text
openlane_results/riscv_pipeline.def
```

The DEF contains the final physical placement and routing information.

### Gate-Level Netlist

```text
openlane_results/riscv_pipeline.nl.v
```

### Timing Constraints

```text
openlane_results/riscv_pipeline.sdc
```

### OpenLane Metrics

```text
openlane_results/metrics.csv
```

---

## Repository Structure

```text
riscv_pipeline/
│
├── README.md
├── config.json
│
├── src/
│   └── riscv_pipeline.v
│
└── openlane_results/
    ├── metrics.csv
    ├── riscv_pipeline.gds
    ├── riscv_pipeline.def
    ├── riscv_pipeline.lef
    ├── riscv_pipeline.nl.v
    └── riscv_pipeline.sdc
```

---

## Tools and Technologies

- **Verilog-2001**
- **RISC-V RV32I**
- **OpenLane**
- **Yosys**
- **OpenROAD**
- **SkyWater SKY130 PDK**
- **Sky130 HD standard-cell library**
- **Magic**
- **Netgen / LVS**
- **SPEF parasitic extraction**
- **GDSII physical design**

---

## Project Highlights

- Designed a **32-bit RV32I RISC-V processor**
- Implemented a **5-stage pipeline**
- Implemented the RTL using **Verilog-2001**
- Verified the design through simulation
- Synthesized the processor using OpenLane
- Performed floorplanning and placement
- Performed clock-tree synthesis
- Completed physical routing
- Performed parasitic extraction
- Generated final **GDSII**
- Achieved **0 WNS and 0 TNS** for the 10 ns clock constraint
- Reported **0 routing violations**
- Reported **0 Magic violations**
- Reported **0 LVS errors**

---

## Future Improvements

Potential extensions include:

- Improved branch prediction
- More advanced hazard handling
- Deeper pipeline optimization
- Cache implementation
- Memory subsystem improvements
- Power optimization
- Timing optimization for higher clock frequencies
- Area optimization
- More extensive post-layout verification
- Automated RTL-to-GDSII regression flow

---

## Author

**Udaya Sree**

B.Tech — Electronics and Communication Engineering

Focus areas:

**VLSI | RTL Design | Verilog | Digital Design | Physical Design | RISC-V | ASIC Design**


