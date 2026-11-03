# 8×8 Systolic Array Matrix Multiply Unit

An **8×8 output-stationary systolic array** for signed 8-bit matrix multiplication,
written from scratch in Verilog-2001, with on-chip SRAM and its own controller.
It targets the **Terasic DE10-Standard** (Intel Cyclone V `5CSXFC6D6F31C6`) and is
designed to be attached to a **CVA6 RISC-V core** as an accelerator.

Part of the final-year project *"Matrix Multiplication Engine and RVV-lite Extension
for a Scalar RISC-V Architecture"*, NED University of Engineering and Technology.

---

## Highlights

- **64 multiply-accumulate units** working in parallel: 512 MACs for one 8×8×8 multiply in **33 cycles**
- **Exact results**: int8 inputs, int32 accumulators (no truncation or overflow inside the array)
- **Real on-chip SRAM** for A, B and C (Cyclone V M10K blocks)
- **Tiling support**: stream up to 32 K-steps per run (`k_len`) and accumulate across
  runs (`accumulate`), so matrices of any size can be computed in 8×8 output tiles
- **Verified**: 206 tests (hand-picked edge cases + random) checked against a Python reference
- **Small**: 6 % of the DE10's logic, leaving room for the CVA6 core

## Results (Quartus Prime 25.1 Lite, standalone compile)

| Resource | Used | Device total |
|---|---|---|
| Logic (ALMs) | 2,401 | 41,910 (6 %) |
| Registers | 3,287 | — |
| DSP blocks | 64 | 112 (57 %) — one per PE |
| RAM blocks (M10K) | 11 | 553 (2 %) |
| Block memory bits | 6,144 | — |
| **Fmax** (Slow 1100 mV 85 °C) | **89.84 MHz** | — |

---

## How it works

### Output-stationary dataflow
Each processing element (PE) keeps **its own result** `C[i][j]` and adds one product per
clock cycle. The inputs move instead: **A flows right, B flows down**, and each value is
reused by 8 PEs as it travels, so 16 values read per cycle keep all 64 PEs busy.

```
             B col 0   B col 1        B col 7
                ↓         ↓              ↓
A row 0 →   PE(0,0) → PE(0,1) → … → PE(0,7)
                ↓         ↓              ↓
A row 1 →   PE(1,0) → PE(1,1) → … → PE(1,7)
                …         …              …
A row 7 →   PE(7,0) → PE(7,1) → … → PE(7,7)

Each PE, every cycle:  acc += a_in × b_in ;  a_out ← a_in ;  b_out ← b_in
```

### The skew (diagonal wave)
PE(i,j) needs `A[i][k]` and `B[k][j]` with the **same k** at the same time. Row *i* of A is
delayed by *i* cycles and column *j* of B by *j* cycles before entering the array, so both
reach PE(i,j) after exactly *i + j* cycles.

### Controller
```
IDLE --start--> CLEAR (1) --> RUN (k_len + 2·(N−1) + 1) --> DRAIN (8) --> IDLE, done = 1
```
- **CLEAR** zeroes the accumulators (unless `accumulate = 1`) and flushes the pipelines.
- **RUN** reads one word of A and one of B per cycle for `k_len` cycles, then feeds zeros
  until the last product reaches PE(7,7).
- **DRAIN** copies one row of results per cycle into the C SRAM.

For the plain 8×8 case (`k_len = 8`) RUN is 23 cycles; one multiply takes 33 cycles from
`start` to `done`.

### Memory layout
| Memory | Size | Word k / i holds |
|---|---|---|
| A SRAM | 32 × 64 bit | column k of the A tile — `A[i][k]` in bits `[i*8 +: 8]` |
| B SRAM | 32 × 64 bit | row k of the B tile — `B[k][j]` in bits `[j*8 +: 8]` |
| C SRAM | 8 × 256 bit | row i of C — `C[i][j]` (int32) in bits `[j*32 +: 32]` |

A is stored by column and B by row so that **one read gives exactly the 8 values** the
array needs for step k.

---

## Repository layout

```
rtl/
  pe.v              processing element: MAC + pass-through registers
  systolic_array.v  8×8 grid of PEs
  skew_buffer.v     shift registers that create the diagonal wave
  sram_sdp.v        simple dual-port SRAM (maps to M10K)
  matmul_ctrl.v     controller state machine
  matmul_top.v      top level: SRAMs + skew + array + controller
sim/
  gen_vectors.py    Python golden model: random + edge-case tests
  tb_matmul.v       testbench acting as the host
  run_sim.sh        generate, compile, run, report PASS/FAIL
matmul.qpf / .qsf / .sdc   Quartus project for the DE10-Standard
run_compile.ps1            command-line Quartus compile
```

Every RTL file starts with a comment block explaining the idea behind it. Suggested reading
order: `pe.v` → `systolic_array.v` → `skew_buffer.v` → `sram_sdp.v` → `matmul_ctrl.v` → `matmul_top.v`.

---

## Using the unit (host protocol)

The host — the testbench today, CVA6 later — does:

1. Write `k_len` words into A SRAM (`a_we`, `a_waddr`, `a_wdata`) and B SRAM (`b_we`, `b_waddr`, `b_wdata`)
2. Set `k_len` (1–32) and `accumulate` (0 = fresh result, 1 = add onto previous), pulse `start`
3. Wait for `done`
4. Read 8 rows of C (`c_raddr` → `c_rdata`, one-cycle read latency)

Do not write A or B while `busy = 1`.

**Bigger matrices:** split C into 8×8 output tiles; for each tile stream the matching rows
of A and columns of B over the whole K (`k_len = K`). If K > 32, split K into blocks with
`accumulate = 0` for the first block and `1` for the rest (the rule used by Gemmini's
`LoopMatmul`). Pad edges with zeros. The tiling loop runs on the host; the hardware
provides the long-K streaming and accumulation.

---

## Running the simulation

Requires **Python 3** and **Icarus Verilog**.

Linux / WSL / Git Bash:
```sh
sh sim/run_sim.sh            # 200 random tests, seed 7
sh sim/run_sim.sh 500 42     # 500 random tests, seed 42
```

Windows PowerShell:
```powershell
cd sim
python gen_vectors.py 200 7
iverilog -g2005 -o sim.vvp tb_matmul.v ../rtl/pe.v ../rtl/systolic_array.v ../rtl/skew_buffer.v ../rtl/sram_sdp.v ../rtl/matmul_ctrl.v ../rtl/matmul_top.v
vvp sim.vvp +T=206
```

Expected output:
```
one matmul = 33 cycles from start to done
PASS: all 206 tests match the Python reference
```
Add `+vcd` to the `vvp` command to dump `matmul.vcd` for GTKWave.

## Compiling in Quartus

Edit the two paths at the top of `run_compile.ps1` (Quartus `bin64` folder and this
project folder), then run it in PowerShell. Results land in `output_files/`:
`matmul.fit.summary` (area) and `matmul.sta.rpt` (search "Fmax Summary").

All data ports are **virtual pins** — the unit is meant to be driven from inside the FPGA
by CVA6, not from board pins. Only `clk` (CLOCK_50, PIN_AF14) and `rst_n` (KEY0, PIN_AJ4)
are real pins.
<img width="1919" height="1079" alt="image" src="https://github.com/user-attachments/assets/c1c9d80a-5c31-4084-8c62-fa8d502c1d5e" />

---
## RTL Design
<img width="1853" height="1079" alt="image" src="https://github.com/user-attachments/assets/fcf426e0-a2dc-4db8-ad10-b171dfc6eda6" />

---

## Design choices

**Why output-stationary?** In this project both matrices change on every multiply, so
there is no gain from pre-loading weights (weight-stationary, as in Google's TPU).
Output-stationary keeps the exact 32-bit sum inside each PE, maps one PE onto one Cyclone V
DSP block (multiplier + accumulator), and handles any K length by simply streaming longer.

**Why 8×8?** With one DSP block per PE, 8×8 (64 blocks) plus CVA6 (16 blocks) fits the
DE10's 112 DSP blocks; 10×10 and above do not. Larger matrices are handled by tiling.

## Status and roadmap

- [x] 8×8 array, skew, SRAM, controller — verified
- [x] Long-K streaming and accumulation for tiling
- [x] Standalone Quartus compile on the DE10-Standard
- [ ] Memory-mapped wrapper so CVA6 can load A/B and read C over AXI
- [ ] Input checking (`k_len` range, writes while busy) in the wrapper
- [ ] Integration with CVA6 on the board and a demo program
- [ ] Overlap DRAIN with the next run (double-buffered results)

## References

- H. T. Kung and C. E. Leiserson, "Systolic Arrays (for VLSI)," 1979 — the original systolic-array concept
- H. Genc et al., "Gemmini: Enabling Systematic Deep-Learning Architecture Evaluation via
  Full-Stack Integration," DAC 2021 — https://github.com/ucb-bar/gemmini
- A. Samajdar et al., "SCALE-Sim: Systolic CNN Accelerator Simulator," 2018 —
  https://arxiv.org/abs/1811.02883 (output-stationary folding model)
- N. P. Jouppi et al., "In-Datacenter Performance Analysis of a Tensor Processing Unit," ISCA 2017
- OpenHW Group CVA6 — https://github.com/openhwgroup/cva6

This design does not reuse code from the projects above; it follows their published dataflow
and tiling methods.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
