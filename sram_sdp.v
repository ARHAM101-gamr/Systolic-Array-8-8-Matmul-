// =============================================================================
// sram_sdp.v  —  on-chip SRAM, simple dual-port (read this FOURTH)
// -----------------------------------------------------------------------------
// "Simple dual-port" = one port only writes, the other port only reads, and
// both can be used in the same cycle.
//
// Written in this exact pattern, Quartus maps it onto the Cyclone V's real
// block RAM (M10K blocks: 10 Kbit each, 553 of them on the DE10). The
// ramstyle attribute asks for M10K explicitly, so the matrices really live
// in SRAM and not in ordinary flip-flops.
//
// IMPORTANT TIMING: the read is SYNCHRONOUS. You give the address in cycle t
// and the data appears in cycle t+1. Real block RAM always works this way,
// and the controller has to allow for this 1-cycle delay.
//
// We use three of these:
//   A memory : 8 words x 64 bits.  Word k = column k of A = A[0..7][k]
//   B memory : 8 words x 64 bits.  Word k = row    k of B = B[k][0..7]
//   C memory : 8 words x 256 bits. Word i = row    i of C = C[i][0..7] (32-bit each)
// Why store A by COLUMN and B by ROW? In step k the array needs A[i][k] for
// every row i (a column of A) and B[k][j] for every column j (a row of B).
// One memory read then gives exactly the 8 values needed for that step.
// =============================================================================
module sram_sdp #(
    parameter WIDTH = 64,
    parameter DEPTH = 8,
    parameter ABITS = 3        // log2(DEPTH)
)(
    input  wire             clk,
    // write port
    input  wire             we,
    input  wire [ABITS-1:0] waddr,
    input  wire [WIDTH-1:0] wdata,
    // read port
    input  wire [ABITS-1:0] raddr,
    output reg  [WIDTH-1:0] rdata
);

    (* ramstyle = "M10K" *) reg [WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
        rdata <= mem[raddr];     // registered read: data valid next cycle
    end

endmodule
