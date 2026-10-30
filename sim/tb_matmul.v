// =============================================================================
// tb_matmul.v  —  testbench: acts as the "host" and checks every answer
// -----------------------------------------------------------------------------
// For each test from gen_vectors.py:
//   1. write 8 A words and 8 B words into the unit's SRAMs
//   2. pulse start, count cycles until done
//   3. read the 8 rows of C and compare with Python's expected answer
// Tests run back to back, which also proves CLEAR really wipes the old result.
//
// Run:   iverilog -g2005 -o sim.vvp tb_matmul.v ../rtl/*.v && vvp sim.vvp +T=<n>
// Waves: add +vcd, then open matmul.vcd in GTKWave.
// =============================================================================
`timescale 1ns/1ps
module tb_matmul;

    localparam N = 8, DW = 8, AW = 32, ABITS = 3, KBITS = 5;
    localparam MAXT = 1000;

    reg                clk = 0;
    reg                rst_n = 0;
    reg                a_we = 0, b_we = 0, start = 0;
    reg  [KBITS-1:0]   a_waddr = 0, b_waddr = 0;
    reg  [ABITS-1:0]   c_raddr = 0;
    reg  [N*DW-1:0]    a_wdata = 0, b_wdata = 0;
    wire [N*AW-1:0]    c_rdata;
    wire               busy, done;

    always #10 clk = ~clk;   // 50 MHz

    // Plain 8x8 tests: k_len = 8, accumulate = 0 (behaves exactly like v1).
    matmul_top #(.N(N), .DW(DW), .AW(AW), .ABITS(ABITS)) dut (
        .clk(clk), .rst_n(rst_n),
        .a_we(a_we), .a_waddr(a_waddr), .a_wdata(a_wdata),
        .b_we(b_we), .b_waddr(b_waddr), .b_wdata(b_wdata),
        .c_raddr(c_raddr), .c_rdata(c_rdata),
        .k_len(6'd8), .accumulate(1'b0),
        .start(start), .busy(busy), .done(done)
    );

    reg [N*DW-1:0] a_mem [0:MAXT*N-1];
    reg [N*DW-1:0] b_mem [0:MAXT*N-1];
    reg [N*AW-1:0] c_exp [0:MAXT*N-1];

    integer T, t, k, i, j, cycles, errors, test_errors;
    reg signed [AW-1:0] got, exp;

    initial begin
        if (!$value$plusargs("T=%d", T)) T = 1;
        if ($test$plusargs("vcd")) begin
            $dumpfile("matmul.vcd");
            $dumpvars(0, tb_matmul);
        end
        $readmemh("a_mem.hex", a_mem, 0, T*N-1);
        $readmemh("b_mem.hex", b_mem, 0, T*N-1);
        $readmemh("c_exp.hex", c_exp, 0, T*N-1);
        errors = 0;

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (t = 0; t < T; t = t + 1) begin
            // ---- 1. load A and B (one word of each per cycle) -------------
            for (k = 0; k < N; k = k + 1) begin
                @(negedge clk);
                a_we = 1; a_waddr = k; a_wdata = a_mem[t*N + k];
                b_we = 1; b_waddr = k; b_wdata = b_mem[t*N + k];
            end
            @(negedge clk);
            a_we = 0; b_we = 0;

            // ---- 2. start and wait for done ----------------------------------
            start = 1;
            @(negedge clk);
            start = 0;
            cycles = 1;
            while (!done) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            // ---- 3. read C row by row and compare ----------------------------
            test_errors = 0;
            for (i = 0; i < N; i = i + 1) begin
                c_raddr = i;
                @(negedge clk);            // SRAM read: data valid next cycle
                for (j = 0; j < N; j = j + 1) begin
                    got = c_rdata[j*AW +: AW];
                    exp = c_exp[t*N + i][j*AW +: AW];
                    if (got !== exp) begin
                        if (test_errors < 4)
                            $display("  test %0d: C[%0d][%0d] = %0d, expected %0d",
                                     t, i, j, got, exp);
                        test_errors = test_errors + 1;
                    end
                end
            end
            if (test_errors) errors = errors + 1;
            if (t == 0) $display("one matmul = %0d cycles from start to done", cycles);
        end

        if (errors == 0)
            $display("PASS: all %0d tests match the Python reference", T);
        else
            $display("FAIL: %0d of %0d tests had wrong results", errors, T);
        $finish;
    end

    // safety net: never hang forever
    initial begin
        #(MAXT * 2000 * 20);
        $display("TIMEOUT");
        $finish;
    end

endmodule
