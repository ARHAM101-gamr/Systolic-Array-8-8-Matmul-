// =============================================================================
// tb_tiled.v  —  big matrices on the 8x8 array, via tiling
// -----------------------------------------------------------------------------
// gen_tiled.py plans the passes (one 8x8 output tile per pass, K split into
// blocks of up to 32 with accumulate on the later blocks). This testbench just
// carries out that plan, like CVA6 software will later:
//   for each pass: load k_len A words and k_len B words, set k_len and
//   accumulate, start, wait for done; after the last K block of a tile,
//   read the 8 rows of C and compare with Python's answer.
//
// Run:  python3 gen_tiled.py
//       iverilog -g2005 -o tiled.vvp tb_tiled.v ../rtl/*.v
//       vvp tiled.vvp +P=<passes> +W=<words> +R=<tiles>   (numbers in tiled_counts.txt)
// =============================================================================
`timescale 1ns/1ps
module tb_tiled;

    localparam N = 8, DW = 8, AW = 32, ABITS = 3, KBITS = 5;
    localparam MAXW = 1 << 16;

    reg                clk = 0;
    reg                rst_n = 0;
    reg                a_we = 0, b_we = 0, start = 0, accumulate = 0;
    reg  [KBITS-1:0]   a_waddr = 0, b_waddr = 0;
    reg  [KBITS:0]     k_len = 0;
    reg  [ABITS-1:0]   c_raddr = 0;
    reg  [N*DW-1:0]    a_wdata = 0, b_wdata = 0;
    wire [N*AW-1:0]    c_rdata;
    wire               busy, done;

    always #10 clk = ~clk;

    matmul_top #(.N(N), .DW(DW), .AW(AW), .ABITS(ABITS)) dut (
        .clk(clk), .rst_n(rst_n),
        .a_we(a_we), .a_waddr(a_waddr), .a_wdata(a_wdata),
        .b_we(b_we), .b_waddr(b_waddr), .b_wdata(b_wdata),
        .c_raddr(c_raddr), .c_rdata(c_rdata),
        .k_len(k_len), .accumulate(accumulate),
        .start(start), .busy(busy), .done(done)
    );

    reg [7:0]      cfg   [0:MAXW-1];
    reg [N*DW-1:0] a_str [0:MAXW-1];
    reg [N*DW-1:0] b_str [0:MAXW-1];
    reg [N*AW-1:0] c_exp [0:MAXW-1];

    integer P, W, R, p, w, r, k, i, j, cycles, total_cycles, bad_tiles, tile_err;
    reg signed [AW-1:0] got, exp;

    initial begin
        if (!$value$plusargs("P=%d", P)) P = 0;
        if (!$value$plusargs("W=%d", W)) W = 0;
        if (!$value$plusargs("R=%d", R)) R = 0;
        $readmemh("pass_cfg.hex", cfg,   0, P-1);
        $readmemh("a_stream.hex", a_str, 0, W-1);
        $readmemh("b_stream.hex", b_str, 0, W-1);
        $readmemh("c_tile_exp.hex", c_exp, 0, R*N-1);

        w = 0; r = 0; bad_tiles = 0; total_cycles = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (p = 0; p < P; p = p + 1) begin
            // ---- load this pass's A and B words -----------------------------
            for (k = 0; k < cfg[p][5:0]; k = k + 1) begin
                @(negedge clk);
                a_we = 1; a_waddr = k; a_wdata = a_str[w];
                b_we = 1; b_waddr = k; b_wdata = b_str[w];
                w = w + 1;
            end
            @(negedge clk);
            a_we = 0; b_we = 0;

            // ---- run --------------------------------------------------------
            k_len      = cfg[p][5:0];
            accumulate = cfg[p][6];
            start = 1;
            @(negedge clk);
            start = 0;
            cycles = 1;
            while (!done) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            total_cycles = total_cycles + cycles;

            // ---- after the last K block of a tile: check it -----------------
            if (cfg[p][7]) begin
                tile_err = 0;
                for (i = 0; i < N; i = i + 1) begin
                    c_raddr = i;
                    @(negedge clk);
                    for (j = 0; j < N; j = j + 1) begin
                        got = c_rdata[j*AW +: AW];
                        exp = c_exp[r*N + i][j*AW +: AW];
                        if (got !== exp) begin
                            if (tile_err < 3)
                                $display("  tile %0d: C[%0d][%0d] = %0d, expected %0d",
                                         r, i, j, got, exp);
                            tile_err = tile_err + 1;
                        end
                    end
                end
                if (tile_err) bad_tiles = bad_tiles + 1;
                r = r + 1;
            end
        end

        $display("compute cycles (start to done, all passes): %0d", total_cycles);
        if (bad_tiles == 0 && r == R)
            $display("PASS: all %0d output tiles (%0d passes) match the Python reference", R, P);
        else
            $display("FAIL: %0d of %0d tiles wrong (checked %0d)", bad_tiles, R, r);
        $finish;
    end

    initial begin
        #(64'd2000000000);
        $display("TIMEOUT");
        $finish;
    end

endmodule
