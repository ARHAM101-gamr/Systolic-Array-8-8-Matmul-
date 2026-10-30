// =============================================================================
// matmul_ctrl.v  —  the controller (state machine) (read this FIFTH)
// -----------------------------------------------------------------------------
// The array, skew buffers and SRAMs only move data. This FSM decides WHEN:
//
//   IDLE  --start-->  CLEAR  -->  RUN  -->  DRAIN  -->  IDLE (done = 1)
//
//   IDLE  : wait for the host to load A and B and pulse 'start'.
//   CLEAR : one cycle. Flush the pass-through and skew registers. Zero every
//           PE's running total too, unless 'accumulate' was set (see below).
//   RUN   : read A word k and B word k from SRAM for k = 0 .. k_len-1 and
//           feed them in. Then keep clocking with zeros until the last product
//           has reached the far corner PE(7,7). (Zeros add nothing to the sums,
//           so feeding them is a simple, safe way to flush the pipeline.)
//   DRAIN : copy the results out of the PEs into the C SRAM, one row of C
//           (8 x 32 bits) per cycle, 8 cycles.
//
// TWO RUN-TIME SETTINGS (both latched when 'start' is seen):
//   k_len      : how many k steps to stream (1 .. KDEPTH). For a plain 8x8
//                multiply this is 8. A longer k_len lets one run compute an
//                8x8 output tile of a bigger multiply, e.g. (8 x 32)·(32 x 8).
//                This follows SCALE-Sim's output-stationary model: the output
//                is tiled into folds, but the reduction dimension K is NOT
//                tiled — each fold streams all of K and the PEs keep adding.
//   accumulate : 1 = do not zero the running totals in CLEAR; add this run's
//                products onto the previous result. Needed only when K is
//                longer than the SRAM holds, so K is split into blocks.
//                Rule (from Gemmini's LoopMatmul.scala): first K block
//                accumulate = 0, every later K block accumulate = 1.
//
// HOW LONG IS RUN? Count cycles from the first RUN cycle, cnt = 0:
//   - cnt = k        : address k goes to the A and B SRAMs
//   - cnt = k + 1    : SRAM data for step k is out (1-cycle read latency)
//   - PE(i,j) gets step k after another i + j cycles (skew + travel),
//     so it does the MAC for step k in cycle  cnt = 1 + k + i + j
//   - The LAST MAC is step k = k_len-1 in PE(N-1,N-1):
//         1 + (k_len - 1) + 2(N-1)  =  k_len + 2(N-1)
//   For the plain 8x8 case (k_len = 8): 8 + 14 = 22, so RUN is cnt 0..22,
//   23 cycles — exactly what the first version used.
//
// TOTAL TIME for one run: 1 (CLEAR) + k_len + 2(N-1) + 1 (RUN) + N (DRAIN).
//   k_len = 8  ->  32 cycles   (512 MACs)
//   k_len = 32 ->  56 cycles   (2048 MACs)
// =============================================================================
module matmul_ctrl #(
    parameter N     = 8,
    parameter ABITS = 3,                 // log2(N): rows of C
    parameter KBITS = 5                  // log2(KDEPTH): address bits of A/B SRAM
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,       // pulse from the host
    input  wire [KBITS:0]   k_len,       // 1 .. 2^KBITS  (one extra bit so 32 fits)
    input  wire             accumulate,  // 1 = keep previous totals and add
    // to the PEs and skew buffers
    output wire             clr,
    output wire             clr_acc,
    output wire             en,
    // to the A and B SRAMs (read side)
    output wire [KBITS-1:0] rd_addr,
    output reg              feed_valid,  // 1 = SRAM data this cycle is real
    // to the C SRAM (write side)
    output wire             c_we,
    output wire [ABITS-1:0] drain_row,
    // status for the host
    output wire             busy,
    output reg              done         // stays 1 until the next start
);

    localparam S_IDLE  = 2'd0,
               S_CLEAR = 2'd1,
               S_RUN   = 2'd2,
               S_DRAIN = 2'd3;

    reg [1:0]     state;
    reg [7:0]     cnt;                   // counts cycles inside RUN and DRAIN
    reg [KBITS:0] k_len_r;               // settings latched at start
    reg           acc_r;

    // Last RUN cycle: k_len + 2(N-1)   (22 for the plain 8x8 case)
    localparam [7:0] FILL = 2*(N-1);     // cycles for the wave to cross the array
    wire [7:0] k_len_8 = {{(7-KBITS){1'b0}}, k_len_r};   // zero-extend to 8 bits
    wire [7:0] last    = k_len_8 + FILL;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            cnt        <= 0;
            done       <= 1'b0;
            feed_valid <= 1'b0;
            k_len_r    <= 0;
            acc_r      <= 1'b0;
        end else begin
            // SRAM data appears one cycle after its address, so the "this
            // data is real" flag is the read condition, delayed one cycle.
            feed_valid <= (state == S_RUN) && (cnt < k_len_8);

            case (state)
                S_IDLE: begin
                    if (start) begin
                        done    <= 1'b0;
                        k_len_r <= k_len;
                        acc_r   <= accumulate;
                        state   <= S_CLEAR;
                    end
                end
                S_CLEAR: begin
                    cnt   <= 0;
                    state <= S_RUN;
                end
                S_RUN: begin
                    if (cnt == last) begin
                        cnt   <= 0;
                        state <= S_DRAIN;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
                S_DRAIN: begin
                    if (cnt == N-1) begin
                        cnt   <= 0;
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
            endcase
        end
    end

    assign clr       = (state == S_CLEAR);
    assign clr_acc   = (state == S_CLEAR) && !acc_r;  // Gemmini: overwrite unless accumulating
    assign en        = (state == S_RUN);
    assign rd_addr   = cnt[KBITS-1:0];                // only meaningful while cnt < k_len
    assign c_we      = (state == S_DRAIN);
    assign drain_row = cnt[ABITS-1:0];
    assign busy      = (state != S_IDLE);

endmodule
