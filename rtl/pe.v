// =============================================================================
// pe.v  —  Processing Element (PE): the single "cell" of the systolic array
// -----------------------------------------------------------------------------
// READ THIS FILE FIRST. The whole 8x8 array is just 64 copies of this cell.
//
// What one PE does, every clock cycle:
//   1. Multiply the number arriving from the LEFT (a_in) by the number
//      arriving from the TOP (b_in).
//   2. Add that product into its own private running total (acc).
//   3. Pass a_in on to the PE on its RIGHT, and b_in on to the PE BELOW,
//      one cycle later (through a register).
//
// "Output-stationary" means the result (acc) STAYS in this PE for the whole
// computation. Only the inputs move. PE(i,j) ends up holding C[i][j]:
//
//        C[i][j] = sum over k of  A[i][k] * B[k][j]
//
//                    b_in (from above)
//                       |
//                       v
//              +-----------------+
//   a_in ----> |  acc += a * b   | ----> a_out (to the right, 1 cycle later)
//  (from left) |                 |
//              +-----------------+
//                       |
//                       v
//                    b_out (to below, 1 cycle later)
//
// Number sizes:
//   a, b  : 8-bit signed integers  (-128 .. +127)
//   acc   : 32-bit signed integer
//   Worst case for 8 products: 8 * (-128 * -128) = 131,072, which needs only
//   19 bits. 32 bits leaves room for longer sums later (e.g. tiling bigger
//   matrices into 8x8 blocks).
// =============================================================================
module pe #(
    parameter DW = 8,           // data width of a and b
    parameter AW = 32           // accumulator width
)(
    input  wire                 clk,
    input  wire                 rst_n,   // asynchronous reset, active low
    input  wire                 clr,     // synchronous clear of the pass-through registers
    input  wire                 clr_acc, // with clr: also zero acc (0 = keep it: "accumulate")
    input  wire                 en,      // 1 = do a MAC this cycle
    input  wire signed [DW-1:0] a_in,    // from the left neighbour
    input  wire signed [DW-1:0] b_in,    // from the neighbour above
    output reg  signed [DW-1:0] a_out,   // to the right neighbour
    output reg  signed [DW-1:0] b_out,   // to the neighbour below
    output reg  signed [AW-1:0] acc      // this PE's result, C[i][j]
);

    // Because a_in, b_in and acc are all declared "signed", Verilog
    // sign-extends a_in and b_in to 32 bits before multiplying, so negative
    // numbers come out right. (If any operand were unsigned, the whole
    // expression would silently become unsigned — a classic bug.)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc   <= 0;
            a_out <= 0;
            b_out <= 0;
        end else if (clr) begin
            // New run: flush the pass-through registers so no stale numbers
            // leak in. Zero the running total too, UNLESS this run should
            // add onto the previous one (clr_acc = 0). That "keep and add"
            // case is how a long K is split into blocks (tiling): the same
            // rule Gemmini uses — overwrite on the first K block, accumulate
            // on the rest (LoopMatmul.scala: accumulate = k =/= 0).
            if (clr_acc)
                acc <= 0;
            a_out <= 0;
            b_out <= 0;
        end else if (en) begin
            acc   <= acc + a_in * b_in;   // the MAC: multiply-accumulate
            a_out <= a_in;                // hand A to the right
            b_out <= b_in;                // hand B downwards
        end
    end

endmodule
