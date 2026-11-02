`timescale 1ns / 1ps
//==============================================================================
// canny_nms : non-maximum suppression on a 3x3 gradient-magnitude window.
//
//   The centre gradient vector (gx, gy) picks one of four quantised edge
//   directions (0 / 45 / 90 / 135 degrees).  The centre magnitude is kept only
//   when it is a strict local maximum along that direction; otherwise it is
//   suppressed to zero.  This thins the Sobel response from ~2..3 pixels down
//   to a 1-pixel-wide ridge before the hysteresis thresholds are applied.
//
//   Unlike nms3x3 (which also thresholds), this module outputs the suppressed
//   magnitude so that the downstream canny_hysteresis can apply the high/low
//   double threshold and the connectivity-based edge linking.
//
//   Combinational (0 cycles latency): grad_out / out_valid follow in_valid.
//==============================================================================
module canny_nms #(
    parameter DW = 12
)(
    input  wire [DW-1:0]     g00, g01, g02,
    input  wire [DW-1:0]     g10, g11, g12,
    input  wire [DW-1:0]     g20, g21, g22,
    input  wire signed [10:0] gx,
    input  wire signed [10:0] gy,
    input  wire              in_valid,

    output wire [DW-1:0]     grad_out,
    output wire              out_valid
);

    // absolute gradient components (gx/gy are 11-bit signed, range -1020..1020)
    wire [10:0] agx = gx[10] ? (~gx + 11'd1) : gx;
    wire [10:0] agy = gy[10] ? (~gy + 11'd1) : gy;

    // Four-sector direction split, identical to nms3x3.
    wire horiz  = ({1'b0, agx} >= {agy, 1'b0});        // |gx| >= 2|gy|
    wire vert   = ({1'b0, agy} >= {agx, 1'b0});        // |gy| >= 2|gx|
    wire diag45 = (gx[10] == gy[10]);

    // Local maximum test along the dominant direction.  The >= / > pairing
    // breaks ties deterministically so exactly one pixel of a flat ridge wins.
    wire nms_h = (g11 >= g10) && (g11 > g12);
    wire nms_v = (g11 >= g01) && (g11 > g21);
    wire nms_d = diag45 ? ((g11 >= g00) && (g11 > g22))
                        : ((g11 >= g02) && (g11 > g20));
    wire nms_ok = horiz ? nms_h : (vert ? nms_v : nms_d);

    assign grad_out  = nms_ok ? g11 : {DW{1'b0}};
    assign out_valid = in_valid;

endmodule
