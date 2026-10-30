// =============================================================================
// matmul_top.v  —  the complete matrix-multiply unit (read this LAST)
// -----------------------------------------------------------------------------
// This file only connects the pieces. Data path, left to right:
//
//   host writes        A SRAM --+                         +--> C SRAM --> host reads
//   A and B words  --> B SRAM --+--> zero-mux --> skew --> 8x8 array
//                                    ^                     ^
//                     controller ----+---------------------+  (when to read,
//                                                             clear, run, drain)
//
// ONE RUN computes one 8x8 output tile:
//        C_tile (8x8) = A_tile (8 x k_len) · B_tile (k_len x 8)
// With k_len = 8 that is a plain 8x8 multiply.
//
// HOW THE HOST USES IT (later the host will be CVA6; for now the testbench):
//   1. Write k_len words into A memory. Word k = column k of the A tile,
//      8 x int8 packed: A[i][k] in bits [i*8 +: 8].
//   2. Write k_len words into B memory. Word k = row k of the B tile,
//      B[k][j] in bits [j*8 +: 8].
//   3. Set k_len (1..KDEPTH) and accumulate (0 = fresh result, 1 = add onto
//      the previous result), then pulse 'start' for one cycle.
//   4. Wait for 'done'.
//   5. Read C memory: word i = row i of the tile, C[i][j] (int32) in
//      bits [j*32 +: 32]. Data comes out one cycle after c_raddr.
// Do not write A or B while busy = 1.
//
// BIGGER MATRICES (tiling, done by the host — see sim/gen_tiled.py):
//   - Split C into 8x8 output tiles ("folds", as SCALE-Sim calls them).
//     For each tile, stream the matching 8 rows of A and 8 columns of B over
//     the whole K in one run (k_len = K), as SCALE-Sim's output-stationary
//     model does.
//   - If K > KDEPTH, split K into blocks and run once per block, with
//     accumulate = 0 for the first block and 1 for the rest (Gemmini's rule).
//   - Sizes that are not multiples of 8 are zero-padded, as both references do.
// =============================================================================
module matmul_top #(
    parameter N      = 8,
    parameter DW     = 8,
    parameter AW     = 32,
    parameter ABITS  = 3,          // log2(N):      rows of the C tile
    parameter KDEPTH = 32,         // A/B SRAM depth = longest K in one run
    parameter KBITS  = 5           // log2(KDEPTH)
)(
    input  wire               clk,
    input  wire               rst_n,
    // host: load A
    input  wire               a_we,
    input  wire [KBITS-1:0]   a_waddr,
    input  wire [N*DW-1:0]    a_wdata,
    // host: load B
    input  wire               b_we,
    input  wire [KBITS-1:0]   b_waddr,
    input  wire [N*DW-1:0]    b_wdata,
    // host: read C
    input  wire [ABITS-1:0]   c_raddr,
    output wire [N*AW-1:0]    c_rdata,
    // control and status
    input  wire [KBITS:0]     k_len,
    input  wire               accumulate,
    input  wire               start,
    output wire               busy,
    output wire               done
);

    // ---- controller --------------------------------------------------------
    wire             clr, clr_acc, en, feed_valid, c_we;
    wire [KBITS-1:0] rd_addr;
    wire [ABITS-1:0] drain_row;

    matmul_ctrl #(.N(N), .ABITS(ABITS), .KBITS(KBITS)) u_ctrl (
        .clk(clk), .rst_n(rst_n), .start(start),
        .k_len(k_len), .accumulate(accumulate),
        .clr(clr), .clr_acc(clr_acc), .en(en),
        .rd_addr(rd_addr), .feed_valid(feed_valid),
        .c_we(c_we), .drain_row(drain_row),
        .busy(busy), .done(done)
    );

    // ---- input SRAMs: A (by columns) and B (by rows), KDEPTH words each ------
    wire [N*DW-1:0] a_rdata, b_rdata;

    sram_sdp #(.WIDTH(N*DW), .DEPTH(KDEPTH), .ABITS(KBITS)) u_sram_a (
        .clk(clk), .we(a_we), .waddr(a_waddr), .wdata(a_wdata),
        .raddr(rd_addr), .rdata(a_rdata)
    );

    sram_sdp #(.WIDTH(N*DW), .DEPTH(KDEPTH), .ABITS(KBITS)) u_sram_b (
        .clk(clk), .we(b_we), .waddr(b_waddr), .wdata(b_wdata),
        .raddr(rd_addr), .rdata(b_rdata)
    );

    // ---- zero-mux: only real data enters; otherwise feed zeros --------------
    wire [N*DW-1:0] a_feed = feed_valid ? a_rdata : {N*DW{1'b0}};
    wire [N*DW-1:0] b_feed = feed_valid ? b_rdata : {N*DW{1'b0}};

    // ---- skew buffers: lane L delayed by L cycles ---------------------------
    wire [N*DW-1:0] a_skewed, b_skewed;

    skew_buffer #(.N(N), .DW(DW)) u_skew_a (
        .clk(clk), .rst_n(rst_n), .clr(clr), .din(a_feed), .dout(a_skewed)
    );

    skew_buffer #(.N(N), .DW(DW)) u_skew_b (
        .clk(clk), .rst_n(rst_n), .clr(clr), .din(b_feed), .dout(b_skewed)
    );

    // ---- the 8x8 systolic array ---------------------------------------------
    wire [N*N*AW-1:0] acc_all;

    systolic_array #(.N(N), .DW(DW), .AW(AW)) u_array (
        .clk(clk), .rst_n(rst_n), .clr(clr), .clr_acc(clr_acc), .en(en),
        .a_left(a_skewed), .b_top(b_skewed),
        .acc_all(acc_all)
    );

    // ---- output SRAM: C tile, one row per word, written during DRAIN --------
    wire [N*AW-1:0] c_row = acc_all[drain_row*N*AW +: N*AW];

    sram_sdp #(.WIDTH(N*AW), .DEPTH(N), .ABITS(ABITS)) u_sram_c (
        .clk(clk), .we(c_we), .waddr(drain_row), .wdata(c_row),
        .raddr(c_raddr), .rdata(c_rdata)
    );

endmodule
