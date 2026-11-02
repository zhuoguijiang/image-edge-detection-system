//==============================================================================
// edge_link3x3 : directional one-pixel edge linking
//
//   A normal 3x3 closing fills a missing centre whenever *any* opposite
//   neighbours are set, which can bridge across corners and thicken lines.
//   This module only fills the centre when both neighbours along the local
//   edge direction are set:
//
//     horizontal gradient -> edge runs vertically -> fill e01 & e21
//     vertical gradient   -> edge runs horizontally -> fill e10 & e12
//     diagonal gradient   -> fill e02&e20 or e00&e22
//
//   e11 is always kept, so existing 1-pixel edges stay 1 pixel wide; only
//   single-pixel gaps that already have two collinear neighbours are filled.
//==============================================================================
module edge_link3x3 #(
    parameter WIDTH = 640
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  in_edge,
    input  wire                  in_valid,
    input  wire signed [10:0]    gx,
    input  wire signed [10:0]    gy,

    output wire                  out_edge,
    output wire                  out_valid
);

    wire e00, e01, e02, e10, e11, e12, e20, e21, e22;
    wire e_valid;

    line_buffer_3x3 #(.WIDTH(WIDTH), .DW(1)) u_lb (
        .clk(clk), .rst_n(rst_n),
        .din(in_edge), .din_valid(in_valid), .din_vsync(1'b0),
        .w00(e00), .w01(e01), .w02(e02),
        .w10(e10), .w11(e11), .w12(e12),
        .w20(e20), .w21(e21), .w22(e22),
        .dout_valid(e_valid), .dout_x(), .dout_y()
    );

    // gx/gy are aligned with the un-delayed NMS edge; the line buffer adds
    // one cycle.
    reg signed [10:0] gx_d1, gy_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gx_d1 <= 11'sd0;
            gy_d1 <= 11'sd0;
        end else begin
            gx_d1 <= gx;
            gy_d1 <= gy;
        end
    end

    wire [10:0] agx = gx_d1[10] ? (~gx_d1 + 11'd1) : gx_d1;
    wire [10:0] agy = gy_d1[10] ? (~gy_d1 + 11'd1) : gy_d1;

    wire horiz = ({1'b0, agx} >= {agy, 1'b0});   // |gx| >= 2|gy|
    wire vert  = ({1'b0, agy} >= {agx, 1'b0});   // |gy| >= 2|gx|
    wire diag_same = (gx_d1[10] == gy_d1[10]);

    wire fill_h = e01 & e21;                     // vertical edge
    wire fill_v = e10 & e12;                     // horizontal edge
    wire fill_d = diag_same ? (e02 & e20) : (e00 & e22);
    wire fill   = horiz ? fill_h : (vert ? fill_v : fill_d);

    assign out_edge  = e11 | fill;
    assign out_valid = e_valid;

endmodule
