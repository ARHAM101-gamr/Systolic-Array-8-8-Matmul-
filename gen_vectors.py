#!/usr/bin/env python3
"""
gen_vectors.py — the "golden" reference model for the 8x8 matmul unit.

Python computes C = A x B the simple, obviously-correct way, and writes:
  a_mem.hex  : 8 lines per test, line k = column k of A, packed like the SRAM
  b_mem.hex  : 8 lines per test, line k = row k of B
  c_exp.hex  : 8 lines per test, line i = expected row i of C (8 x int32)
  num_tests.txt
The Verilog testbench loads these files, runs the hardware, and compares.
If hardware and Python ever disagree, the hardware is wrong.

Packing (same as the RTL):
  A word k : A[i][k] in bits [i*8 +: 8]   (lane i = row i)
  B word k : B[k][j] in bits [j*8 +: 8]   (lane j = column j)
  C word i : C[i][j] in bits [j*32 +: 32]
Negative numbers are stored in two's complement.

Usage:  python3 gen_vectors.py [num_random_tests] [seed]
"""
import random
import sys

N = 8


def to_twos(value, bits):
    """Signed integer -> unsigned two's-complement bit pattern."""
    return value & ((1 << bits) - 1)


def pack(values, bits):
    """Pack a list of signed ints, element 0 in the lowest bits."""
    word = 0
    for idx, v in enumerate(values):
        word |= to_twos(v, bits) << (idx * bits)
    return word


def matmul(A, B):
    return [[sum(A[i][k] * B[k][j] for k in range(N)) for j in range(N)]
            for i in range(N)]


def fixed_tests():
    """Hand-picked cases that catch typical hardware bugs."""
    I = [[1 if i == j else 0 for j in range(N)] for i in range(N)]
    seq = [[i * N + j - 32 for j in range(N)] for i in range(N)]
    tests = [
        ("identity x sequence", I, seq),          # C must equal B exactly
        ("sequence x identity", seq, I),          # C must equal A exactly
        ("all -128 (largest result)",             # 8 * 16384 = 131072
         [[-128] * N for _ in range(N)], [[-128] * N for _ in range(N)]),
        ("+127 x -128 (most negative)",
         [[127] * N for _ in range(N)], [[-128] * N for _ in range(N)]),
        ("all zeros", [[0] * N for _ in range(N)], [[0] * N for _ in range(N)]),
        # one non-zero per matrix: shows if any value lands in the wrong PE
        ("single element A[3][5] x B[5][6]",
         [[7 if (i, k) == (3, 5) else 0 for k in range(N)] for i in range(N)],
         [[-9 if (k, j) == (5, 6) else 0 for j in range(N)] for k in range(N)]),
    ]
    return tests


def main():
    n_random = int(sys.argv[1]) if len(sys.argv) > 1 else 50
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    rng = random.Random(seed)

    tests = fixed_tests()
    for t in range(n_random):
        A = [[rng.randint(-128, 127) for _ in range(N)] for _ in range(N)]
        B = [[rng.randint(-128, 127) for _ in range(N)] for _ in range(N)]
        tests.append((f"random #{t}", A, B))

    with open("a_mem.hex", "w") as fa, open("b_mem.hex", "w") as fb, \
         open("c_exp.hex", "w") as fc, open("test_names.txt", "w") as fn:
        for name, A, B in tests:
            C = matmul(A, B)
            for k in range(N):
                fa.write(f"{pack([A[i][k] for i in range(N)], 8):016x}\n")
                fb.write(f"{pack([B[k][j] for j in range(N)], 8):016x}\n")
            for i in range(N):
                fc.write(f"{pack(C[i], 32):064x}\n")
            fn.write(name + "\n")

    with open("num_tests.txt", "w") as f:
        f.write(f"{len(tests)}\n")
    print(f"wrote {len(tests)} tests ({len(fixed_tests())} fixed + {n_random} random)")


if __name__ == "__main__":
    main()
