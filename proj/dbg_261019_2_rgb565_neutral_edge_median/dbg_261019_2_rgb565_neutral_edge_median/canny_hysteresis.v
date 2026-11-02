`timescale 1ns / 1ps
//==============================================================================
// canny_hysteresis : double-threshold + hysteresis edge linking (streaming).
//
//   Canny's final step.  Every non-suppressed gradient is classified as
//       strong  (grad >= high_thr)
//       weak    (low_thr <= grad < high_thr)
//       none    (grad <  low_thr)
//   and the output edge is
//       edge = strong | (weak & connected-to-strong)
//
//   Unlike nms3x3's single 3x3 "any strong neighbour" rule, this module does a
//   raster-scan *propagation*: a weak pixel is confirmed when it touches an
//   already-confirmed pixel to its left, up-left, up or up-right.  Because the
//   confirmed flag feeds back, a weak chain that runs horizontally (or
//   downward) is followed for its whole length, not just one pixel.  The
//   previous row is kept in a 1-bit line store, so the cost is one RAM per
//   width (vs. a full frame for textbook two-pass hysteresis) and the whole
//   stage still runs at one pixel per clock with a single-cycle latency.
//
//   A weak ridge that only connects to a strong pixel *below* it is not
//   recovered by this single top-down pass; the edge_link3x3 stage that
//   follows fills the remaining one-pixel gaps using the gradient direction.
//   This is the standard streaming approximation of Canny hysteresis and is
//   what keeps the design comfortably inside the Ti60F225 RAM budget.
//
//   LATENCY : 1 cycle (the previous-row read is registered).
//==============================================================================
module canny_hysteresis #(
    parameter WIDTH = 640
)(
    input  wire         clk,
    input  wire         rst_n,

    input  wire [11:0]  grad,        // NMS-suppressed gradient magnitude
    input  wire         in_valid,
    input  wire         din_vsync,   // active-high, one pulse per frame (opt.)

    input  wire [7:0]   high_thr,
    input  wire [7:0]   low_thr,

    output reg          edge_out,
    output reg          out_valid
);

    wire [11:0] high = {4'b0000, high_thr};
    wire [11:0] low  = {4'b0000, low_thr};

    // NB: "strong"/"weak" are SystemVerilog drive-strength keywords, so use
    // *_px suffixes here (Efinity compiles with -sv_09 and rejects them).
    wire strong_px = (grad >= high);
    wire weak_px   = (grad >= low);       // includes strong; priority below

    // 1-bit line store of the *confirmed* edge of the previous row.
    reg        lb [0:WIDTH-1];
    reg [10:0] wptr;                      // write column
    reg        ur, up, ul;                // prev-row confirmed at c+1, c, c-1
    reg        left_conf;                 // current-row confirmed at c-1
    reg [3:0]  row_cnt;                   // saturating completed-row counter

    // Read two columns ahead so that, one cycle later, ur/up/ul hold the
    // previous row's columns c+1 / c / c-1 while we process column c.
    wire [10:0] rd_ptr =
        (wptr >= WIDTH-2) ? ((wptr + 2'd2) - WIDTH[10:0]) : (wptr + 2'd2);

    // The left neighbour only exists from the second pixel of a row onward.
    wire left_eff = (wptr != 10'd0) ? left_conf : 1'b0;

    wire confirmed = strong_px | (weak_px & (left_eff | ul | up | ur));

    always @(posedge clk) begin
        if (in_valid) lb[wptr] <= confirmed;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ur <= 1'b0; up <= 1'b0; ul <= 1'b0; left_conf <= 1'b0;
            wptr <= 11'd0; row_cnt <= 4'd0;
            edge_out <= 1'b0; out_valid <= 1'b0;
        end else if (din_vsync) begin
            ur <= 1'b0; up <= 1'b0; ul <= 1'b0; left_conf <= 1'b0;
            wptr <= 11'd0; row_cnt <= 4'd0;
            edge_out <= 1'b0; out_valid <= 1'b0;
        end else begin
            ur <= lb[rd_ptr];
            up <= ur;
            ul <= up;

            left_conf <= in_valid ? confirmed : 1'b0;

            if (in_valid) begin
                if (wptr == WIDTH-1) begin
                    wptr <= 11'd0;
                    if (row_cnt != 4'd15) row_cnt <= row_cnt + 1'b1;
                end else begin
                    wptr <= wptr + 1'b1;
                end
            end

            // one full previous row must exist, and the up/up-left/up-right
            // neighbours must lie inside the frame (drop the two border cols)
            edge_out  <= confirmed;
            out_valid <= in_valid && (row_cnt >= 4'd1) &&
                         (wptr >= 11'd1) && (wptr <= WIDTH[10:0] - 2'd2);
        end
    end

endmodule
