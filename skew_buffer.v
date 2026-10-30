// =============================================================================
// skew_buffer.v  —  turns a straight column of data into a diagonal wave
// (read this THIRD)
// -----------------------------------------------------------------------------
// THE PROBLEM
// PE(i,j) must multiply A[i][k] with B[k][j] — the SAME k — in the same cycle.
//   - A[i][k] enters at row i and walks right j steps   -> j cycles of delay
//   - B[k][j] enters at column j and walks down i steps -> i cycles of delay
// If we pushed all 8 values of a memory word in at once, row 0's A would meet
// the wrong B further along. The two streams would be out of step.
//
// THE FIX: delay lane L by L cycles before it enters the array.
//   - A for row i is delayed by i cycles, then walks j steps:  total i + j
//   - B for col j is delayed by j cycles, then walks i steps:  total j + i
// Both arrive at PE(i,j) after exactly i + j cycles, so the right pair meets.
//
// Picture (A side, each row delayed one more cycle than the row above):
//
//   cycle:     t   t+1  t+2  t+3 ...
//   row 0:   A00  A01  A02  A03
//   row 1:    -   A10  A11  A12
//   row 2:    -    -   A20  A21
//   row 3:    -    -    -   A30
//
// That staircase is the "diagonal wave" moving through the array.
//
// HOW: lane 0 = a plain wire, lane 1 = 1 register, lane 2 = 2 registers in a
// row (a shift register), ... lane 7 = 7 registers. 28 registers per side.
// =============================================================================
module skew_buffer #(
    parameter N  = 8,
    parameter DW = 8
)(
    input  wire            clk,
    input  wire            rst_n,
    input  wire            clr,      // empty the pipeline at the start of a run
    input  wire [N*DW-1:0] din,      // all lanes, straight (same cycle)
    output wire [N*DW-1:0] dout      // lane L delayed by L cycles
);

    // Lane 0: no delay.
    assign dout[0 +: DW] = din[0 +: DW];

    genvar L;
    generate
        for (L = 1; L < N; L = L + 1) begin : g_lane
            // A shift register L stages long for lane L.
            reg [DW-1:0] sr [0:L-1];
            integer s;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (s = 0; s < L; s = s + 1) sr[s] <= 0;
                end else if (clr) begin
                    for (s = 0; s < L; s = s + 1) sr[s] <= 0;
                end else begin
                    sr[0] <= din[L*DW +: DW];             // value enters
                    for (s = 1; s < L; s = s + 1)
                        sr[s] <= sr[s-1];                 // moves one step
                end
            end
            assign dout[L*DW +: DW] = sr[L-1];            // exits L cycles later
        end
    endgenerate

endmodule
