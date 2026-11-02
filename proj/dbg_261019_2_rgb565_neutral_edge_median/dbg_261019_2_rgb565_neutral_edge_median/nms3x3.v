//==============================================================================
// nms3x3 : non-maximum suppression + local hysteresis on a 3x3 gradient window
//
//   g00 g01 g02       g00 = top-left ... g22 = bottom-right
//   g10 g11 g12       g11 = centre gradient magnitude
//   g20 g21 g22
//
//   The centre gradient vector (gx, gy) selects one of four quantised
//   directions (0/45/90/135 degrees).  The centre is kept only when its
//   magnitude is a local maximum along that direction, which thins a Sobel
//   response from ~2 pixels to ~1 pixel.
//
//   Hysteresis is local (3x3): a weak centre survives only if at least one
//   neighbour is strong.  This is intentionally cheap; a full Canny-style
//   connected-component hysteresis would need extra state/line buffers.
//==============================================================================
module nms3x3 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [11:0] g00, g01, g02,
    input  wire [11:0] g10, g11, g12,
    input  wire [11:0] g20, g21, g22,
    input  wire signed [10:0] gx,
    input  wire signed [10:0] gy,
    input  wire        in_valid,
    input  wire [7:0]  high_thr,
    input  wire [7:0]  low_thr,

    output wire        edge_out,
    output wire        out_valid
);

    // absolute gradient components
    wire [10:0] agx = gx[10] ? (~gx + 11'd1) : gx;
    wire [10:0] agy = gy[10] ? (~gy + 11'd1) : gy;

    // dominant gradient direction
    wire horiz  = ({1'b0, agx} >= {agy, 1'b0});       // |gx| >= 2|gy|
    wire vert   = ({1'b0, agy} >= {agx, 1'b0});       // |gy| >= 2|gx|
    wire diag45 = (gx[10] == gy[10]);

    wire nms_h = (g11 >= g10) && (g11 > g12);
    wire nms_v = (g11 >= g01) && (g11 > g21);
    wire nms_d = diag45 ? ((g11 >= g00) && (g11 > g22))
                        : ((g11 >= g02) && (g11 > g20));
    wire nms_ok = horiz ? nms_h : (vert ? nms_v : nms_d);

    wire [11:0] high = {4'b0000, high_thr};
    wire [11:0] low  = {4'b0000, low_thr};
    wire strong_px = (g11 >= high);
    wire weak_px   = (g11 >= low);

    wire any_strong =
        (g00 >= high) || (g01 >= high) || (g02 >= high) ||
        (g10 >= high) ||                 (g12 >= high) ||
        (g20 >= high) || (g21 >= high) || (g22 >= high);

    assign edge_out  = nms_ok && (strong_px || (weak_px && any_strong));
    assign out_valid = in_valid;

endmodule
