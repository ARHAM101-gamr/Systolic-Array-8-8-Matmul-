#!/bin/sh
# Generate tests, compile the RTL with Icarus Verilog, run, report PASS/FAIL.
# Usage: ./run_sim.sh [num_random_tests] [seed]      add +vcd at the end of the vvp line for waves
cd "$(dirname "$0")"
python3 gen_vectors.py ${1:-200} ${2:-7} || exit 1
iverilog -g2005 -o sim.vvp tb_matmul.v ../rtl/*.v || exit 1
vvp sim.vvp +T=$(cat num_tests.txt) | grep -E "cycles|PASS|FAIL|TIMEOUT"
