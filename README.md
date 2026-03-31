# VECOP — Vector Co-Processor Unit

VECOP is a modular and extensible RISC-V Vector (RVV) coprocessor designed as an educational and research-oriented project focused on vector architectures and FPGA implementations.

> [!NOTE]
> This project is being developed as an undergraduate final project, all by myself. It is currently a WIP...

## Overview

VECOP implements a RISC-V Vector Extension (RVV v1.0) compatible execution engine operating as a coprocessor connected to a scalar RISC-V core.

The design prioritizes:
- Modularity
- Extensibility
- Educational clarity
- FPGA feasibility (area-aware design)

> Performance is intentionally traded for architectural transparency and scalability.

## Architecture

VECOP follows a vector microarchitecture:
- Multi-cycle
- Non-pipelined
- Time-domain multiplexed execution
- Designed for FPGA deployment

## Top-Level Subsystems
### V-Dispatcher

Interface between scalar core and vector subsystem.

Responsibilities:
- Instruction FIFO (decoupling queue)
- First-level decode
- Execution subsystem dispatch
- Exception signaling to scalar core

Internal blocks:
- V-FRONTEND
- V-IQ (FIFO)
- V-BACKEND

### V-ALU (Vector Arithmetic Logic Unit)

Executes arithmetic, logical and mask operations.

Components:
- V-ALU SEQ — execution sequencer and level-2 control
- O-SEL — operand selector
- V-INT — integer execution unit
- V-MASK — mask processing unit

Characteristics:
- Fixed 32-bit datapath
- Chunk-based element processing
- Execution latency proportional to VLEN

Supported operations include:
- Integer arithmetic
- Bitwise operations
- Comparisons
- Widening operations
- Vector mask generating instructions (integer operands)

### V-LSU (Vector Load Store Unit)

Responsible for memory interaction.

Features:
- Address generation
- Data alignment
- Byte-enable generation
- Vector register file transfers

Supported addressing modes:
- Unit stride
- Constant stride

> Indexed accesses are intentionally omitted to reduce hardware complexity.

## Control Strategy

VECOP uses decentralized control:
  - Level 1 — Global Dispatch
    - Instruction classification
    - Subsystem activation
  - Level 2 — Local Control
    - Execution sequencing
    - Register access management
    - "Sub-cycle" execution control

### Advantages:
- Improved modularity
- Easier extensibility
- Reduced design coupling

## RISC-V Vector Support
- 32 vector registers
- Configurable:
  - VL
  - VSEW (8 / 16 / 32 bits)
  - VLMUL (1 / 2 / 4 / 8)

### Supported instruction classes:
- Vector configuration
- Integer arithmetic/logic
- Mask operations
- Vector load/store (stride-based)

## Verification

Verification infrastructure consists of two primary testbenches:

- VECOP TOP Testbench
  > Uses OSVVM verification methodology.
  - Random instruction generation with automatic checking:
    - Instruction/configuration randomization
    - Execution
    - Result comparison against expected values


- VECOP FLEX TOP Testbench
  - Instruction-driven verification using external TXT programs.

## Design Goals
- Provide a didactic RVV implementation
- Serve as an entry point for students studying:
  - Vector architectures
  - Parallel computing
  - Hardware acceleration
  - FPGA-based processors

## Ongoing Tasks
- [ ] VL configuration support
- [ ] Full masking integration
- [ ] Exception handling completion
- [ ] Memory access optimization
- [ ] Expanded verification coverage
- [ ] CPI and utilization measurements
- [ ] Design stabilization
