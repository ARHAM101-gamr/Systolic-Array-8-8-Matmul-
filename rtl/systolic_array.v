// =============================================================================
// systolic_array.v  —  8x8 grid of PEs (read this SECOND)
// -----------------------------------------------------------------------------
// We place N x N copies of pe.v in a grid and wire each one to its neighbours:
//
//              b_top[col0] b_top[col1]  ...  b_top[col7]
//                  |           |                 |
//                  v           v                 v
//  a_left[row0] -> PE(0,0) -> PE(0,1) -> ... -> PE(0,7)
//                  |           |                 |
//                  v           v                 v
//  a_left[row1] -> PE(1,0) -> PE(1,1) -> ... -> PE(1,7)
//                  ...         ...               ...
//  a_left[row7] -> PE(7,0) -> PE(7,1) -> ... -> PE(7,7)
//
//  - A values enter on the LEFT edge, one value per row, and move RIGHT.
//  - B values enter on the TOP edge, one value per column, and move DOWN.
//  - Every PE keeps its own sum. After the run, PE(i,j) holds C[i][j].
//
// Why "systolic"? Data pulses through the grid in step with the clock, like
// blood pumped by a heart. Each value is fetched from memory ONCE and then
// re-used by 8 PEs as it travels, which is what makes the array efficient:
// 64 multiply-accumulates per cycle from just 16 numbers read per cycle.
//
// Packing convention (Verilog-2001 has no 2-D ports, so we flatten):
//   a_left : row i      is bits [i*DW +: DW]
//   b_top  : column j   is bits [j*DW +: DW]
//   acc_all: PE(i,j)    is bits [(i*N + j)*AW +: AW]   (row-major)
//            so one whole row i of C is bits [i*N*AW +: N*AW]
// =============================================================================
module systolic_array #(
    parameter N  = 8,
    parameter DW = 8,
    parameter AW = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              clr,
    input  wire              clr_acc,
    input  wire              en,
    input  wire [N*DW-1:0]   a_left,    // one A value per row, entering left
    input  wire [N*DW-1:0]   b_top,     // one B value per column, entering top
    output wire [N*N*AW-1:0] acc_all    // all 64 results, row-major
);

    // Internal wires between PEs.
    // a_bus[i][j] is the A value going INTO PE(i,j) from the left.
    // Column N of a_bus is what falls off the right edge (unused).
    // b_bus[i][j] is the B value going INTO PE(i,j) from above.
    // Row N of b_bus is what falls off the bottom edge (unused).
    wire [DW-1:0] a_bus [0:N-1][0:N];
    wire [DW-1:0] b_bus [0:N][0:N-1];

    genvar i, j;
    generate
        // Connect the left edge and the top edge to the module inputs.
        for (i = 0; i < N; i = i + 1) begin : g_edge
            assign a_bus[i][0] = a_left[i*DW +: DW];
            assign b_bus[0][i] = b_top [i*DW +: DW];
        end

        // Build the grid.
        for (i = 0; i < N; i = i + 1) begin : g_row
            for (j = 0; j < N; j = j + 1) begin : g_col
                pe #(.DW(DW), .AW(AW)) u_pe (
                    .clk   (clk),
                    .rst_n (rst_n),
                    .clr   (clr),
                    .clr_acc(clr_acc),
                    .en    (en),
                    .a_in  (a_bus[i][j]),       // from the left neighbour
                    .b_in  (b_bus[i][j]),       // from the neighbour above
                    .a_out (a_bus[i][j+1]),     // to the right neighbour
                    .b_out (b_bus[i+1][j]),     // to the neighbour below
                    .acc   (acc_all[(i*N + j)*AW +: AW])
                );
            end
        end
    endgenerate

endmodule
