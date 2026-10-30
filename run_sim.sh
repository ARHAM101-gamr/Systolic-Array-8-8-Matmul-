#!/bin/sh
# Runs both test suites. Usage: ./run_sim.sh [num_random_tests] [seed]
cd "$(dirname "$0")"
echo "== plain 8x8 tests"
python3 gen_vectors.py ${1:-200} ${2:-7} || exit 1
iverilog -g2005 -o sim.vvp tb_matmul.v ../rtl/*.v || exit 1
vvp sim.vvp +T=$(cat num_tests.txt) | grep -E "cycles|PASS|FAIL|TIMEOUT"
echo "== tiled tests (big matrices on the 8x8 array)"
python3 gen_tiled.py ${2:-3} || exit 1
read P W R < tiled_counts.txt
iverilog -g2005 -o tiled.vvp tb_tiled.v ../rtl/*.v || exit 1
vvp tiled.vvp +P=$P +W=$W +R=$R | grep -E "cycles|PASS|FAIL|TIMEOUT"
