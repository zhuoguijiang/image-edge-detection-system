//==============================================================================
// split_mux : 分屏显示 MUX
//
//   left  half [0 .. SPLIT_X-1]        <- stream A (灰度原图)
//   right half [SPLIT_X .. H_ACTIVE-1] <- stream B (Sobel 边缘图)
//
// A SPLIT_W-pixel separator is drawn at the boundary so the split is obvious
// on the monitor.
//
// Purely combinational on purpose: the two input streams must already be
// latency-matched (see video_delay.v / alg_stub.v) and the HDMI encoder
// consumes the video timing of the un-processed branch, so inserting a
// register here would misalign data and sync by one pixel.  An 8-bit mux at
// 25.2 MHz has no timing pressure.
//==============================================================================
module split_mux #(
    parameter H_ACTIVE = 640,
    parameter X_BITS   = 11,
    parameter SPLIT_X  = 320,
    parameter SPLIT_W  = 2,
    parameter [7:0] SEP_R = 8'hFF,
    parameter [7:0] SEP_G = 8'hFF,
    parameter [7:0] SEP_B = 8'h00
)(
    // stream A - e.g. grayscale original
    input  wire [7:0]        a_data,
    input  wire              a_valid,

    // stream B - e.g. Sobel edges
    input  wire [7:0]        b_data,
    input  wire              b_valid,

    // display timing (shared by both streams)
    input  wire              de,
    input  wire [X_BITS-1:0] x,

    output wire [7:0]        out_data,
    output wire              out_valid,
    output wire              out_is_sep
);

    wire sel_b  = (x >= SPLIT_X);
    wire is_sep = (x >= (SPLIT_X - SPLIT_W)) && (x < SPLIT_X);

    assign out_valid  = de & (sel_b ? b_valid : a_valid);
    assign out_is_sep = de & is_sep;
    assign out_data   = is_sep ? SEP_R : (sel_b ? b_data : a_data);

endmodule
