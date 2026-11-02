`timescale 1ns / 1ps
//==============================================================================
// gaussian5x5 : 5x5 Gaussian blur for the Canny pre-smoothing stage.
//
//   Kernel = [1 4 6 4 1]^T x [1 4 6 4 1] / 256  (sigma ~ 1.0)
//
//   Implemented as a single self-contained module: four 1-line stores build a
//   5x5 sliding window (same synchronous-read block-RAM pattern as
//   line_buffer_3x3), then the 25 taps are summed with shift-add multipliers
//   only (no DSP, no divider).  This smooths the gradient before Sobel, which
//   is what removes sensor noise and the jagged "staircase" on slanted edges.
//
//   LATENCY : 2 cycles (1 for the window register, 1 for the weighted sum).
//   Spatial : the window centre is (x-2, y-2), so valid pixels are shrunk by
//             2 columns on each side and 2 rows on top/bottom.
//
//   din_vsync is an active-high reset of the line pointers, one pulse per
//   frame (aligned with din).  Tie to 1'b0 when the caller keeps the stream
//   width constant and handles frame boundaries downstream (as alg_top does
//   for its other line buffers).
//==============================================================================
module gaussian5x5 #(
    parameter WIDTH = 640,
    parameter DW    = 8
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire [DW-1:0] din,
    input  wire          din_valid,
    input  wire          din_vsync,
    output reg  [DW-1:0] dout,
    output reg           dout_valid
);

    //--------------------------------------------------------------------------
    // 5x5 sliding window : four line stores + a 5-deep horizontal shift per row.
    // The window centre is (x-2, y-2); w22 is the centre pixel.
    //--------------------------------------------------------------------------
    reg [DW-1:0] lb1 [0:WIDTH-1];
    reg [DW-1:0] lb2 [0:WIDTH-1];
    reg [DW-1:0] lb3 [0:WIDTH-1];
    reg [DW-1:0] lb4 [0:WIDTH-1];
    reg [DW-1:0] q1, q2, q3, q4;          // 1..4 lines ago at the current column
    reg [15:0]   ptr;
    reg [15:0]   x_in, y_in;

    wire [15:0] nxt_ptr = (ptr == WIDTH-1) ? 16'd0 : ptr + 16'd1;
    wire [15:0] rd_ptr  = din_valid ? nxt_ptr : ptr;

    always @(posedge clk) begin
        if (din_valid) begin
            lb1[ptr] <= din;
            lb2[ptr] <= q1;
            lb3[ptr] <= q2;
            lb4[ptr] <= q3;
        end
        q1 <= lb1[rd_ptr];
        q2 <= lb2[rd_ptr];
        q3 <= lb3[rd_ptr];
        q4 <= lb4[rd_ptr];
    end

    // Horizontal taps for each of the five rows: d4..d0 = cols x-4 .. x.
    reg [DW-1:0] r4d1, r4d2, r4d3, r4d4;   // current row  (din)
    reg [DW-1:0] r3d1, r3d2, r3d3, r3d4;   // 1 line ago   (q1)
    reg [DW-1:0] r2d1, r2d2, r2d3, r2d4;   // 2 lines ago  (q2)
    reg [DW-1:0] r1d1, r1d2, r1d3, r1d4;   // 3 lines ago  (q3)
    reg [DW-1:0] r0d1, r0d2, r0d3, r0d4;   // 4 lines ago  (q4)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr <= 16'd0; x_in <= 16'd0; y_in <= 16'd0;
            r4d1 <= 0; r4d2 <= 0; r4d3 <= 0; r4d4 <= 0;
            r3d1 <= 0; r3d2 <= 0; r3d3 <= 0; r3d4 <= 0;
            r2d1 <= 0; r2d2 <= 0; r2d3 <= 0; r2d4 <= 0;
            r1d1 <= 0; r1d2 <= 0; r1d3 <= 0; r1d4 <= 0;
            r0d1 <= 0; r0d2 <= 0; r0d3 <= 0; r0d4 <= 0;
        end else if (din_vsync) begin
            ptr <= 16'd0; x_in <= 16'd0; y_in <= 16'd0;
            r4d1 <= 0; r4d2 <= 0; r4d3 <= 0; r4d4 <= 0;
            r3d1 <= 0; r3d2 <= 0; r3d3 <= 0; r3d4 <= 0;
            r2d1 <= 0; r2d2 <= 0; r2d3 <= 0; r2d4 <= 0;
            r1d1 <= 0; r1d2 <= 0; r1d3 <= 0; r1d4 <= 0;
            r0d1 <= 0; r0d2 <= 0; r0d3 <= 0; r0d4 <= 0;
        end else if (din_valid) begin
            ptr <= (ptr == WIDTH-1) ? 16'd0 : ptr + 16'd1;
            r4d1 <= din;  r4d2 <= r4d1; r4d3 <= r4d2; r4d4 <= r4d3;
            r3d1 <= q1;   r3d2 <= r3d1; r3d3 <= r3d2; r3d4 <= r3d3;
            r2d1 <= q2;   r2d2 <= r2d1; r2d3 <= r2d2; r2d4 <= r2d3;
            r1d1 <= q3;   r1d2 <= r1d1; r1d3 <= r1d2; r1d4 <= r1d3;
            r0d1 <= q4;   r0d2 <= r0d1; r0d3 <= r0d2; r0d4 <= r0d3;
            if (x_in == WIDTH-1) begin
                x_in <= 16'd0;
                // saturate so a vsync-less stream can never wrap the row gate
                y_in <= (y_in == 16'hFFFF) ? y_in : y_in + 16'd1;
            end else begin
                x_in <= x_in + 16'd1;
            end
        end
    end

    // combinational 5x5 window (rows top->bottom, cols left->right), centre w22
    wire [DW-1:0] w00 = r0d4, w01 = r0d3, w02 = r0d2, w03 = r0d1, w04 = q4;
    wire [DW-1:0] w10 = r1d4, w11 = r1d3, w12 = r1d2, w13 = r1d1, w14 = q3;
    wire [DW-1:0] w20 = r2d4, w21 = r2d3, w22 = r2d2, w23 = r2d1, w24 = q2;
    wire [DW-1:0] w30 = r3d4, w31 = r3d3, w32 = r3d2, w33 = r3d1, w34 = q1;
    wire [DW-1:0] w40 = r4d4, w41 = r4d3, w42 = r4d2, w43 = r4d1, w44 = din;

    //--------------------------------------------------------------------------
    // Weighted sum: v * k where k is one of {1,4,6,16,24,36} (shift-add only).
    //--------------------------------------------------------------------------
    function [15:0] wterm;
        input [7:0] v;
        input [5:0] k;
        begin
            case (k)
                6'd1 : wterm = {8'b0, v};
                6'd4 : wterm = {6'b0, v, 2'b0};
                6'd6 : wterm = {6'b0, v, 2'b0} + {7'b0, v, 1'b0};
                6'd16: wterm = {4'b0, v, 4'b0};
                6'd24: wterm = {4'b0, v, 4'b0} + {5'b0, v, 3'b0};
                6'd36: wterm = {3'b0, v, 5'b0} + {6'b0, v, 2'b0};
                default: wterm = 16'd0;
            endcase
        end
    endfunction

    // 256-total normalisation; the true maximum is 255*256 = 65280, so the
    // 16-bit accumulator can never overflow.
    wire [15:0] gsum =
        wterm(w00, 6'd1 ) + wterm(w01, 6'd4 ) + wterm(w02, 6'd6 ) +
        wterm(w03, 6'd4 ) + wterm(w04, 6'd1 ) +
        wterm(w10, 6'd4 ) + wterm(w11, 6'd16) + wterm(w12, 6'd24) +
        wterm(w13, 6'd16) + wterm(w14, 6'd4 ) +
        wterm(w20, 6'd6 ) + wterm(w21, 6'd24) + wterm(w22, 6'd36) +
        wterm(w23, 6'd24) + wterm(w24, 6'd6 ) +
        wterm(w30, 6'd4 ) + wterm(w31, 6'd16) + wterm(w32, 6'd24) +
        wterm(w33, 6'd16) + wterm(w34, 6'd4 ) +
        wterm(w40, 6'd1 ) + wterm(w41, 6'd4 ) + wterm(w42, 6'd6 ) +
        wterm(w43, 6'd4 ) + wterm(w44, 6'd1 );

    //--------------------------------------------------------------------------
    // Output stage (round to nearest -> divide by 256)
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout       <= {DW{1'b0}};
            dout_valid <= 1'b0;
        end else if (din_vsync) begin
            dout       <= {DW{1'b0}};
            dout_valid <= 1'b0;
        end else begin
            dout       <= (gsum + 16'd128) >> 8;
            dout_valid <= din_valid && (x_in >= 16'd4) && (y_in >= 16'd4);
        end
    end

endmodule
