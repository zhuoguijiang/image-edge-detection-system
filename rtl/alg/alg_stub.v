//==============================================================================
// alg_stub : placeholder for the A-group image pipeline.
//
// CONTRACT (must be preserved when A-group's alg_top replaces this module)
//   - same port list
//   - same LATENCY parameter = number of pipeline stages the module inserts
//   - de / hs / vs / valid / x / y leave the module delayed by exactly
//     LATENCY cycles relative to the data they belong to.
//
//   B-group instantiates this in system_top and sets ALG_LATENCY to the value
//   A-group reports, so the un-processed branch (video_delay) and the
//   processed branch arrive at the split MUX perfectly aligned.
//
// PLACEHOLDER BEHAVIOUR
//   Threshold binarisation of the raw byte.  It is deliberately trivial: it
//   proves the whole capture -> stream -> algorithm -> split -> HDMI path and
//   it makes the key-controlled threshold visible on the right half of the
//   screen before the real Sobel pipeline exists.
//==============================================================================
module alg_stub #(
    parameter LATENCY = 1,
    parameter X_BITS  = 11,
    parameter Y_BITS  = 11
)(
    input  wire                clk,
    input  wire                rst_n,

    input  wire [7:0]          in_data,
    input  wire                in_valid,
    input  wire                in_de,
    input  wire                in_hs,
    input  wire                in_vs,
    input  wire [X_BITS-1:0]   in_x,
    input  wire [Y_BITS-1:0]   in_y,

    input  wire [7:0]          threshold,

    output wire [7:0]          out_data,
    output wire                out_valid,
    output wire                out_de,
    output wire                out_hs,
    output wire                out_vs,
    output wire [X_BITS-1:0]   out_x,
    output wire [Y_BITS-1:0]   out_y
);

    wire [7:0] binarised = (in_data > threshold) ? 8'hFF : 8'h00;

    video_delay #(
        .STAGES(LATENCY),
        .X_BITS(X_BITS),
        .Y_BITS(Y_BITS)
    ) u_pipe (
        .clk(clk), .rst_n(rst_n),
        .in_data(binarised),
        .in_valid(in_valid), .in_de(in_de),
        .in_hs(in_hs), .in_vs(in_vs),
        .in_x(in_x), .in_y(in_y),
        .out_data(out_data),
        .out_valid(out_valid), .out_de(out_de),
        .out_hs(out_hs), .out_vs(out_vs),
        .out_x(out_x), .out_y(out_y)
    );

endmodule
