//==============================================================================
// alg_top : A-group image pipeline behind the frozen pixel-stream interface.
//
//   RAW8 Bayer (BGGR)
//     -> line_buffer_3x3 -> debayer      (RAW8 -> RGB888)
//     -> grayscale                        (RGB888 -> Y8)
//     -> line_buffer_3x3 -> median3x3     (3x3 median denoise)
//     -> line_buffer_3x3 -> sobel         (grad = |Gx|+|Gy|, threshold)
//     -> out_data = binary edge (0xFF / 0x00)
//
// Port list matches rtl/alg/alg_stub.v exactly, so it is a drop-in replacement.
// de/hs/vs/x/y are delayed by LATENCY cycles so they stay aligned with data.
// The algorithm itself has a 3-pixel / 3-line spatial delay (three 3x3 window
// stages), so out_x/out_y are corrected by that amount.
//==============================================================================
module alg_top #(
    parameter WIDTH   = 640,
    parameter X_BITS  = 11,
    parameter Y_BITS  = 11,
    parameter LATENCY = 12    // 1(lb1)+1(debayer)+1(gray)+1(lb2)+3(median)+1(lb3)+4(sobel)
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

    localparam W = WIDTH;

    // interface vsync is active-low; the line buffer reset is active-high
    wire vs_act = ~in_vs;

    //--------------------------------------------------------------------------
    // stage 1 : 3x3 window + debayer  (RAW8 -> RGB888)
    //--------------------------------------------------------------------------
    wire [7:0] a00,a01,a02,a10,a11,a12,a20,a21,a22;
    wire       a_valid;
    wire [15:0] a_x, a_y;

    line_buffer_3x3 #(.WIDTH(W), .DW(8)) u_lb1 (
        .clk(clk), .rst_n(rst_n),
        .din(in_data), .din_valid(in_valid), .din_vsync(vs_act),
        .w00(a00), .w01(a01), .w02(a02),
        .w10(a10), .w11(a11), .w12(a12),
        .w20(a20), .w21(a21), .w22(a22),
        .dout_valid(a_valid), .dout_x(a_x), .dout_y(a_y)
    );

    wire [7:0] rgb_r, rgb_g, rgb_b;
    wire       rgb_valid;
    debayer u_db (
        .clk(clk), .rst_n(rst_n),
        .w00(a00), .w01(a01), .w02(a02),
        .w10(a10), .w11(a11), .w12(a12),
        .w20(a20), .w21(a21), .w22(a22),
        .in_valid(a_valid), .in_x(a_x), .in_y(a_y),
        .r(rgb_r), .g(rgb_g), .b(rgb_b), .out_valid(rgb_valid)
    );

    //--------------------------------------------------------------------------
    // stage 2 : grayscale
    //--------------------------------------------------------------------------
    wire [7:0] gray_y;
    wire       gray_valid, gray_href, gray_vsync;
    grayscale u_gray (
        .clk(clk), .rst_n(rst_n),
        .r(rgb_r), .g(rgb_g), .b(rgb_b),
        .in_valid(rgb_valid), .in_href(1'b1), .in_vsync(1'b0),
        .y(gray_y), .out_valid(gray_valid),
        .out_href(gray_href), .out_vsync(gray_vsync)
    );

    //--------------------------------------------------------------------------
    // stage 3 : 3x3 window + median filter
    //--------------------------------------------------------------------------
    wire [7:0] b00,b01,b02,b10,b11,b12,b20,b21,b22;
    wire       b_valid;
    wire [15:0] b_x, b_y;

    line_buffer_3x3 #(.WIDTH(W-2), .DW(8)) u_lb2 (
        .clk(clk), .rst_n(rst_n),
        .din(gray_y), .din_valid(gray_valid), .din_vsync(1'b0),
        .w00(b00), .w01(b01), .w02(b02),
        .w10(b10), .w11(b11), .w12(b12),
        .w20(b20), .w21(b21), .w22(b22),
        .dout_valid(b_valid), .dout_x(b_x), .dout_y(b_y)
    );

    wire [7:0] med_y;
    wire       med_valid;
    median3x3 u_med (
        .clk(clk), .rst_n(rst_n),
        .w00(b00), .w01(b01), .w02(b02),
        .w10(b10), .w11(b11), .w12(b12),
        .w20(b20), .w21(b21), .w22(b22),
        .in_valid(b_valid), .med(med_y), .out_valid(med_valid)
    );

    //--------------------------------------------------------------------------
    // stage 4 : 3x3 window + sobel
    //--------------------------------------------------------------------------
    wire [7:0] c00,c01,c02,c10,c11,c12,c20,c21,c22;
    wire       c_valid;
    wire [15:0] c_x, c_y;

    line_buffer_3x3 #(.WIDTH(W-4), .DW(8)) u_lb3 (
        .clk(clk), .rst_n(rst_n),
        .din(med_y), .din_valid(med_valid), .din_vsync(1'b0),
        .w00(c00), .w01(c01), .w02(c02),
        .w10(c10), .w11(c11), .w12(c12),
        .w20(c20), .w21(c21), .w22(c22),
        .dout_valid(c_valid), .dout_x(c_x), .dout_y(c_y)
    );

    wire [11:0] grad;
    wire        sob_valid, sob_edge;
    sobel u_sob (
        .clk(clk), .rst_n(rst_n),
        .w00(c00), .w01(c01), .w02(c02),
        .w10(c10), .w11(c11), .w12(c12),
        .w20(c20), .w21(c21), .w22(c22),
        .in_valid(c_valid), .threshold({4'b0000, threshold}),
        .grad(grad), .edge_out(sob_edge), .out_valid(sob_valid)
    );

    //--------------------------------------------------------------------------
    // output timing delayed by exactly LATENCY cycles
    //--------------------------------------------------------------------------
    wire [7:0]        dly_data;
    wire              dly_valid, dly_de, dly_hs, dly_vs;
    wire [X_BITS-1:0] dly_x;
    wire [Y_BITS-1:0] dly_y;

    video_delay #(
        .STAGES(LATENCY), .X_BITS(X_BITS), .Y_BITS(Y_BITS)
    ) u_dly (
        .clk(clk), .rst_n(rst_n),
        .in_data(in_data), .in_valid(in_valid), .in_de(in_de),
        .in_hs(in_hs), .in_vs(in_vs),
        .in_x(in_x), .in_y(in_y),
        .out_data(dly_data), .out_valid(dly_valid), .out_de(dly_de),
        .out_hs(dly_hs), .out_vs(dly_vs),
        .out_x(dly_x), .out_y(dly_y)
    );

    // binary edge image; blank outside the fully-valid region
    assign out_data  = (sob_valid && sob_edge) ? 8'hFF : 8'h00;
    assign out_valid = sob_valid;
    assign out_de    = dly_de;
    assign out_hs    = dly_hs;
    assign out_vs    = dly_vs;
    assign out_x     = (dly_x >= 11'd3) ? (dly_x - 11'd3) : {X_BITS{1'b0}};
    assign out_y     = (dly_y >= 11'd3) ? (dly_y - 11'd3) : {Y_BITS{1'b0}};

endmodule
