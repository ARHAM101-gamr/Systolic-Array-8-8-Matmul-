#!/usr/bin/env python3
"""
gen_tiled.py — multiplies BIG matrices on the 8x8 array by tiling.

This plays the role CVA6 software will play later: it plans the runs ("passes")
and writes them as a stream the testbench executes. It also computes the
expected answer with plain Python, so the hardware result can be checked.

TILING PLAN (taken from the references, not invented here):
  * SCALE-Sim, output-stationary model (scalesim/compute/systolic_compute_os.py):
      the OUTPUT C (M x Nc) is split into 8x8 tiles ("folds"):
          row_fold = ceil(M / 8),  col_fold = ceil(Nc / 8)
      and the reduction dimension K is NOT tiled — each fold streams all of K.
      -> one pass per tile with k_len = K, as long as K fits the SRAM.
  * Gemmini (src/main/scala/gemmini/LoopMatmul.scala):
      when K is too long for the on-chip memory, split K into blocks and set
          accumulate = (k_block != 0)
      i.e. the first block overwrites the result, later blocks add onto it.
      Edge tiles that do not fill a block are zero-padded (pad_i / pad_j).
  Here K blocks are at most KDEPTH = 32 long; the last block can be shorter
  (k_len < 32), so K itself never needs padding.

Files written (read by tb_tiled.v):
  pass_cfg.hex   one line per pass: bit7 = read result after this pass,
                 bit6 = accumulate, bits5..0 = k_len
  a_stream.hex   k_len words per pass: word k = column k of the A tile (8 x int8)
  b_stream.hex   k_len words per pass: word k = row k of the B tile    (8 x int8)
  c_tile_exp.hex 8 lines per finished tile: expected C rows (8 x int32)
  tiled_counts.txt   "passes words reads"
"""
import random
import sys

N = 8          # array size
KDEPTH = 32    # A/B SRAM depth = longest K block in one pass


def to_twos(v, bits):
    return v & ((1 << bits) - 1)


def pack(values, bits):
    w = 0
    for idx, v in enumerate(values):
        w |= to_twos(v, bits) << (idx * bits)
    return w


def matmul(A, B):
    M, K, Nc = len(A), len(B), len(B[0])
    return [[sum(A[i][k] * B[k][j] for k in range(K)) for j in range(Nc)]
            for i in range(M)]


def ceil_div(a, b):
    return (a + b - 1) // b


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    rng = random.Random(seed)

    # (name, M, K, Nc, value generator)
    rnd = lambda: rng.randint(-128, 127)
    cases = [
        ("8x8x8 (one tile, one pass)",            8,   8,  8, rnd),
        ("32x32x32 (16 tiles, K fits)",          32,  32, 32, rnd),
        ("16x64x16 (K split in 2: accumulate)",  16,  64, 16, rnd),
        ("20x13x27 (not multiples of 8: padding)", 20, 13, 27, rnd),
        ("40x100x24 (K blocks 32+32+32+4)",      40, 100, 24, rnd),
        ("8x128x8 all -128 (largest sums)",       8, 128,  8, lambda: -128),
    ]

    passes, a_words, b_words, c_lines, plan = [], [], [], [], []
    for name, M, K, Nc, gen in cases:
        A = [[gen() for _ in range(K)] for _ in range(M)]
        B = [[gen() for _ in range(Nc)] for _ in range(K)]
        C = matmul(A, B)
        row_fold, col_fold = ceil_div(M, N), ceil_div(Nc, N)   # SCALE-Sim folds
        k_blocks = ceil_div(K, KDEPTH)                          # Gemmini K blocks
        n_pass = 0
        for ti in range(row_fold):
            for tj in range(col_fold):
                for kb in range(k_blocks):
                    k0 = kb * KDEPTH
                    k_len = min(KDEPTH, K - k0)
                    accumulate = 1 if kb != 0 else 0           # Gemmini rule
                    read_out = 1 if kb == k_blocks - 1 else 0
                    passes.append((read_out << 7) | (accumulate << 6) | k_len)
                    for k in range(k0, k0 + k_len):
                        # column k of the A tile; rows past M are zero padding
                        col = [A[ti*N + i][k] if ti*N + i < M else 0 for i in range(N)]
                        a_words.append(pack(col, 8))
                        # row k of the B tile; columns past Nc are zero padding
                        row = [B[k][tj*N + j] if tj*N + j < Nc else 0 for j in range(N)]
                        b_words.append(pack(row, 8))
                    if read_out:
                        for i in range(N):
                            r = ti*N + i
                            vals = [C[r][tj*N + j] if (r < M and tj*N + j < Nc) else 0
                                    for j in range(N)]
                            c_lines.append(pack(vals, 32))
                    n_pass += 1
        plan.append(f"{name}: {row_fold}x{col_fold} tiles x {k_blocks} K-block(s) = {n_pass} passes")

    with open("pass_cfg.hex", "w") as f:
        f.writelines(f"{p:02x}\n" for p in passes)
    with open("a_stream.hex", "w") as f:
        f.writelines(f"{w:016x}\n" for w in a_words)
    with open("b_stream.hex", "w") as f:
        f.writelines(f"{w:016x}\n" for w in b_words)
    with open("c_tile_exp.hex", "w") as f:
        f.writelines(f"{w:064x}\n" for w in c_lines)
    with open("tiled_counts.txt", "w") as f:
        f.write(f"{len(passes)} {len(a_words)} {len(c_lines)//N}\n")
    for line in plan:
        print(line)
    print(f"total: {len(passes)} passes, {len(c_lines)//N} output tiles to check")


if __name__ == "__main__":
    main()
