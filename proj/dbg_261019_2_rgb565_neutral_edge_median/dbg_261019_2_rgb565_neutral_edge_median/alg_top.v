//==============================================================================
// alg_top : A-group image pipeline behind the frozen pixel-stream interface.
//
//   RAW8 Bayer (BGGR)
//     -> line_buffer_3x3 -> debayer      (RAW8 -> RGB888)
//     -> grayscale                        (RGB888 -> Y8)
//     -> line_buffer_3x3 -> median3x3     (3x3 median denoise)
//     -> [CANNY] gaussian5x5              (5x5 Gaussian pre-smoothing)
//     -> line_buffer_3x3 -> sobel         (grad = |Gx|+|Gy|, gx, gy)
//     -> [CANNY] line_buffer_3x3(grad) -> canny_nms -> canny_hysteresis
//        [SOBEL] nms3x3 -> edge_link3x3
//     -> out_data = binary edge (0xFF / 0x00)
//     -> out_gray = median-filtered Y8, delayed to the same cycle
//
// EDGE_FILTER selects the Sobel input (CANNY_EN=0 path):
//   0 = raw grayscale
//   1 = plain 3x3 median
//   2 = adaptive median (only isolated outliers are replaced)
//
// CANNY_EN selects the full Canny chain (Gaussian -> Sobel -> NMS ->
// double-threshold hysteresis) instead of the plain Sobel threshold path.
// With CANNY_EN=1 the edge path always uses the Gaussian-smoothed grayscale,
// so EDGE_FILTER is ignored; the median stage still runs to feed out_gray.
//
// Port list matches rtl/alg/alg_stub.v exactly, so it is a drop-in replacement.
// de/hs/vs/x/y are delayed by LATENCY cycles so they stay aligned with data.
//==============================================================================
module alg_top #(
    parameter WIDTH   = 640,
    parameter X_BITS  = 11,
    parameter Y_BITS  = 11,
    parameter LATENCY = 12,   // 1(lb1)+1(debayer)+1(gray)+1(lb2)+3(median)+1(lb3)+4(sobel)
    parameter EDGE_FILTER = 1,
    parameter NMS_EN = 0,
    parameter LINK_EN = 0,
    parameter CANNY_EN = 0,  // 1 = Gaussian + NMS + hysteresis (Canny) edge path
    parameter CANNY_PREMEDIAN = 0,
    parameter CANNY_GAUSS3 = 0,
    parameter CANNY_SCHARR = 0,
    parameter CANNY_NMS_INTERP = 0
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
    output wire [7:0]          out_gray,
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
    // stage 3 : 3x3 window + median filter   (always on: feeds out_gray)
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

    wire [7:0] med_y, med_adaptive;
    wire       med_valid;
    median3x3 u_med (
        .clk(clk), .rst_n(rst_n),
        .w00(b00), .w01(b01), .w02(b02),
        .w10(b10), .w11(b11), .w12(b12),
        .w20(b20), .w21(b21), .w22(b22),
        .in_valid(b_valid), .med(med_y), .med_adaptive(med_adaptive),
        .out_valid(med_valid)
    );

    // Delay the median-filtered grayscale by the remaining lb3 + Sobel
    // latency (1 + 4 = 5 cycles), so out_gray is aligned with out_data.
    reg [7:0] gray_d1, gray_d2, gray_d3, gray_d4, gray_d5, gray_d6, gray_d7;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gray_d1 <= 8'd0; gray_d2 <= 8'd0; gray_d3 <= 8'd0;
            gray_d4 <= 8'd0; gray_d5 <= 8'd0; gray_d6 <= 8'd0; gray_d7 <= 8'd0;
        end else begin
            gray_d1 <= med_y;
            gray_d2 <= gray_d1;
            gray_d3 <= gray_d2;
            gray_d4 <= gray_d3;
            gray_d5 <= gray_d4;
            gray_d6 <= gray_d5;
            gray_d7 <= gray_d6;
        end
    end
    assign out_gray = (LATENCY >= 14) ? gray_d7 :
                      (LATENCY >= 13) ? gray_d6 : gray_d5;

    // Align the unfiltered grayscale with med_y at the input of lb3:
    // gray_y is 4 cycles earlier (lb2 + 3-stage median).
    reg [7:0] gray_raw_d1, gray_raw_d2, gray_raw_d3, gray_raw_d4;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gray_raw_d1 <= 8'd0; gray_raw_d2 <= 8'd0;
            gray_raw_d3 <= 8'd0; gray_raw_d4 <= 8'd0;
        end else begin
            gray_raw_d1 <= gray_y;
            gray_raw_d2 <= gray_raw_d1;
            gray_raw_d3 <= gray_raw_d2;
            gray_raw_d4 <= gray_raw_d3;
        end
    end
    wire [7:0] edge_src = (EDGE_FILTER == 2) ? med_adaptive :
                          (EDGE_FILTER == 1) ? med_y : gray_raw_d4;

    //==========================================================================
    // SOBEL EDGE PATH  (CANNY_EN = 0)
    //==========================================================================
    wire [7:0]  sob_path_data;
    wire        sob_path_valid;
    generate
        if (!CANNY_EN) begin : g_sobel
            //--------------------------------------------------------------------------
            // stage 4 : 3x3 window + sobel
            //--------------------------------------------------------------------------
            wire [7:0] c00,c01,c02,c10,c11,c12,c20,c21,c22;
            wire       c_valid;
            wire [15:0] c_x, c_y;

            line_buffer_3x3 #(.WIDTH(W-4), .DW(8)) u_lb3 (
                .clk(clk), .rst_n(rst_n),
                .din(edge_src), .din_valid(med_valid), .din_vsync(1'b0),
                .w00(c00), .w01(c01), .w02(c02),
                .w10(c10), .w11(c11), .w12(c12),
                .w20(c20), .w21(c21), .w22(c22),
                .dout_valid(c_valid), .dout_x(c_x), .dout_y(c_y)
            );

            wire [11:0] grad;
            wire        sob_valid, sob_edge;
            wire signed [10:0] sob_gx, sob_gy;
            sobel u_sob (
                .clk(clk), .rst_n(rst_n),
                .w00(c00), .w01(c01), .w02(c02),
                .w10(c10), .w11(c11), .w12(c12),
                .w20(c20), .w21(c21), .w22(c22),
                .in_valid(c_valid), .threshold({4'b0000, threshold}),
                .grad(grad), .gx(sob_gx), .gy(sob_gy),
                .edge_out(sob_edge), .out_valid(sob_valid)
            );

            // Optional NMS + local hysteresis.  The gradient-magnitude line buffer
            // adds one cycle, so the top level instantiates this path with LATENCY=13.
            wire [11:0] nms_g00, nms_g01, nms_g02, nms_g10, nms_g11, nms_g12,
                        nms_g20, nms_g21, nms_g22;
            wire        nms_g_valid, nms_edge, nms_valid;
            reg signed [10:0] nms_gx_d1, nms_gy_d1;
            wire        link_edge, link_valid;

            if (NMS_EN) begin : g_nms
                line_buffer_3x3 #(.WIDTH(W-4), .DW(12)) u_lbg (
                    .clk(clk), .rst_n(rst_n),
                    .din(grad), .din_valid(sob_valid), .din_vsync(1'b0),
                    .w00(nms_g00), .w01(nms_g01), .w02(nms_g02),
                    .w10(nms_g10), .w11(nms_g11), .w12(nms_g12),
                    .w20(nms_g20), .w21(nms_g21), .w22(nms_g22),
                    .dout_valid(nms_g_valid), .dout_x(), .dout_y()
                );

                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        nms_gx_d1 <= 11'sd0;
                        nms_gy_d1 <= 11'sd0;
                    end else begin
                        nms_gx_d1 <= sob_gx;
                        nms_gy_d1 <= sob_gy;
                    end
                end

                nms3x3 u_nms (
                    .clk(clk), .rst_n(rst_n),
                    .g00(nms_g00), .g01(nms_g01), .g02(nms_g02),
                    .g10(nms_g10), .g11(nms_g11), .g12(nms_g12),
                    .g20(nms_g20), .g21(nms_g21), .g22(nms_g22),
                    .gx(nms_gx_d1), .gy(nms_gy_d1),
                    .in_valid(nms_g_valid),
                    .high_thr(threshold), .low_thr(threshold >> 1),
                    .edge_out(nms_edge), .out_valid(nms_valid)
                );

                if (LINK_EN) begin : g_link
                    edge_link3x3 #(.WIDTH(W-4)) u_link (
                        .clk(clk), .rst_n(rst_n),
                        .in_edge(nms_edge), .in_valid(nms_valid),
                        .gx(nms_gx_d1), .gy(nms_gy_d1),
                        .out_edge(link_edge), .out_valid(link_valid)
                    );
                end else begin : g_no_link
                    assign link_edge  = 1'b0;
                    assign link_valid = 1'b0;
                end
            end else begin : g_no_nms
                assign nms_g00 = 12'd0; assign nms_g01 = 12'd0; assign nms_g02 = 12'd0;
                assign nms_g10 = 12'd0; assign nms_g11 = 12'd0; assign nms_g12 = 12'd0;
                assign nms_g20 = 12'd0; assign nms_g21 = 12'd0; assign nms_g22 = 12'd0;
                assign nms_g_valid = 1'b0;
                assign nms_edge  = 1'b0;
                assign nms_valid = 1'b0;
                assign link_edge  = 1'b0;
                assign link_valid = 1'b0;
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        nms_gx_d1 <= 11'sd0;
                        nms_gy_d1 <= 11'sd0;
                    end else begin
                        nms_gx_d1 <= sob_gx;
                        nms_gy_d1 <= sob_gy;
                    end
                end
            end

            assign sob_path_data = LINK_EN
                                 ? ((link_valid && link_edge) ? 8'hFF : 8'h00)
                                 : (NMS_EN
                                    ? ((nms_valid && nms_edge) ? 8'hFF : 8'h00)
                                    : ((sob_valid && sob_edge) ? 8'hFF : 8'h00));
            assign sob_path_valid = LINK_EN ? link_valid : (NMS_EN ? nms_valid : sob_valid);
        end else begin : g_no_sobel
            assign sob_path_data  = 8'h00;
            assign sob_path_valid = 1'b0;
        end
    endgenerate

    //==========================================================================
    // CANNY EDGE PATH  (CANNY_EN = 1)
    //   grayscale -> gaussian5x5 -> 3x3 sobel -> NMS -> hysteresis -> link
    //   Total latency: 1(lb1)+1(debayer)+1(gray)+2(gauss)+1(lb3)+4(sobel)
    //                  +1(lbg)+0(nms)+1(hyst)+1(link) = 13 cycles.
    //==========================================================================
    wire [7:0]  canny_path_data;
    wire        canny_path_valid;
    generate
        if (CANNY_EN) begin : g_canny
            localparam CANNY_SRC_W  = CANNY_PREMEDIAN ? (W - 4) : (W - 2);
            localparam GAUSS5_OUT_W = CANNY_SRC_W - 4;
            localparam LB3_IN_W     = GAUSS5_OUT_W - (CANNY_GAUSS3 ? 2 : 0);
            localparam GRAD_LB_W    = LB3_IN_W - 2;
            localparam HYST_W       = GRAD_LB_W - 2;
            localparam LINK_W       = HYST_W - 2;
            // Frame vsync follows either the raw grayscale path (3 stages) or
            // the adaptive-median path (+lb2 and three median stages).
            reg [6:0] vs_d;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) vs_d <= 7'd0;
                else         vs_d <= {vs_d[5:0], vs_act};
            end
            wire gauss_vsync = CANNY_PREMEDIAN ? vs_d[6] : vs_d[2];
            wire [7:0] canny_src = CANNY_PREMEDIAN ? med_adaptive : gray_y;
            wire       canny_src_valid = CANNY_PREMEDIAN ? med_valid : gray_valid;

            wire [7:0] gauss_y;
            wire       gauss_valid;
            gaussian5x5 #(.WIDTH(CANNY_SRC_W), .DW(8)) u_gauss (
                .clk(clk), .rst_n(rst_n),
                .din(canny_src), .din_valid(canny_src_valid), .din_vsync(gauss_vsync),
                .dout(gauss_y), .dout_valid(gauss_valid)
            );

            wire [7:0] gauss3_y;
            wire       gauss3_valid;
            if (CANNY_GAUSS3) begin : g_smooth3
                gaussian3x3 #(.WIDTH(GAUSS5_OUT_W), .DW(8)) u_gauss3 (
                    .clk(clk), .rst_n(rst_n),
                    .din(gauss_y), .din_valid(gauss_valid), .din_vsync(1'b0),
                    .dout(gauss3_y), .dout_valid(gauss3_valid)
                );
            end else begin : g_no_smooth3
                assign gauss3_y = gauss_y;
                assign gauss3_valid = gauss_valid;
            end

            wire [7:0] edge_smooth_y = CANNY_GAUSS3 ? gauss3_y : gauss_y;
            wire       edge_smooth_valid = CANNY_GAUSS3 ? gauss3_valid : gauss_valid;

            wire [7:0] c00,c01,c02,c10,c11,c12,c20,c21,c22;
            wire       c_valid;
            wire [15:0] c_x, c_y;

            line_buffer_3x3 #(.WIDTH(LB3_IN_W), .DW(8)) u_lb3c (
                .clk(clk), .rst_n(rst_n),
                .din(edge_smooth_y), .din_valid(edge_smooth_valid), .din_vsync(1'b0),
                .w00(c00), .w01(c01), .w02(c02),
                .w10(c10), .w11(c11), .w12(c12),
                .w20(c20), .w21(c21), .w22(c22),
                .dout_valid(c_valid), .dout_x(c_x), .dout_y(c_y)
            );

            wire [11:0] c_grad;
            wire        c_sob_valid, c_sob_edge;
            wire signed [10:0] c_gx, c_gy;
            if (CANNY_SCHARR) begin : g_scharr_sob
                scharr u_sob_c (
                    .clk(clk), .rst_n(rst_n),
                    .w00(c00), .w01(c01), .w02(c02),
                    .w10(c10), .w11(c11), .w12(c12),
                    .w20(c20), .w21(c21), .w22(c22),
                    .in_valid(c_valid), .threshold({4'b0000, threshold}),
                    .grad(c_grad), .gx(c_gx), .gy(c_gy),
                    .edge_out(c_sob_edge), .out_valid(c_sob_valid)
                );
            end else begin : g_sobel_sob
                sobel u_sob_c (
                    .clk(clk), .rst_n(rst_n),
                    .w00(c00), .w01(c01), .w02(c02),
                    .w10(c10), .w11(c11), .w12(c12),
                    .w20(c20), .w21(c21), .w22(c22),
                    .in_valid(c_valid), .threshold({4'b0000, threshold}),
                    .grad(c_grad), .gx(c_gx), .gy(c_gy),
                    .edge_out(c_sob_edge), .out_valid(c_sob_valid)
                );
            end

            // gradient-magnitude 3x3 window for NMS (+1 cycle)
            wire [11:0] n00,n01,n02,n10,n11,n12,n20,n21,n22;
            wire        n_valid;
            line_buffer_3x3 #(.WIDTH(GRAD_LB_W), .DW(12)) u_lbgc (
                .clk(clk), .rst_n(rst_n),
                .din(c_grad), .din_valid(c_sob_valid), .din_vsync(1'b0),
                .w00(n00), .w01(n01), .w02(n02),
                .w10(n10), .w11(n11), .w12(n12),
                .w20(n20), .w21(n21), .w22(n22),
                .dout_valid(n_valid), .dout_x(), .dout_y()
            );

            reg signed [10:0] c_gx_d1, c_gy_d1;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    c_gx_d1 <= 11'sd0;
                    c_gy_d1 <= 11'sd0;
                end else begin
                    c_gx_d1 <= c_gx;
                    c_gy_d1 <= c_gy;
                end
            end

            wire [11:0] nms_grad;
            wire        nms_valid;
            if (CANNY_NMS_INTERP) begin : g_interp_nms
                canny_nms_interp u_nms_c (
                    .g00(n00), .g01(n01), .g02(n02),
                    .g10(n10), .g11(n11), .g12(n12),
                    .g20(n20), .g21(n21), .g22(n22),
                    .gx(c_gx_d1), .gy(c_gy_d1),
                    .in_valid(n_valid),
                    .grad_out(nms_grad), .out_valid(nms_valid)
                );
            end else begin : g_sector_nms
                canny_nms u_nms_c (
                    .g00(n00), .g01(n01), .g02(n02),
                    .g10(n10), .g11(n11), .g12(n12),
                    .g20(n20), .g21(n21), .g22(n22),
                    .gx(c_gx_d1), .gy(c_gy_d1),
                    .in_valid(n_valid),
                    .grad_out(nms_grad), .out_valid(nms_valid)
                );
            end

            wire hyst_edge, hyst_valid;
            canny_hysteresis #(.WIDTH(HYST_W)) u_hyst (
                .clk(clk), .rst_n(rst_n),
                .grad(nms_grad), .in_valid(nms_valid), .din_vsync(1'b0),
                .high_thr(threshold), .low_thr(threshold >> 1),
                .edge_out(hyst_edge), .out_valid(hyst_valid)
            );

            wire link_edge, link_valid;
            if (LINK_EN) begin : g_link
                edge_link3x3 #(.WIDTH(LINK_W)) u_link_c (
                    .clk(clk), .rst_n(rst_n),
                    .in_edge(hyst_edge), .in_valid(hyst_valid),
                    .gx(c_gx_d1), .gy(c_gy_d1),
                    .out_edge(link_edge), .out_valid(link_valid)
                );
                assign canny_path_data  = (link_valid && link_edge) ? 8'hFF : 8'h00;
                assign canny_path_valid = link_valid;
            end else begin : g_no_link
                assign link_edge  = 1'b0;
                assign link_valid = 1'b0;
                assign canny_path_data  = (hyst_valid && hyst_edge) ? 8'hFF : 8'h00;
                assign canny_path_valid = hyst_valid;
            end
        end else begin : g_no_canny
            assign canny_path_data  = 8'h00;
            assign canny_path_valid = 1'b0;
        end
    endgenerate

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
    assign out_data  = CANNY_EN ? canny_path_data : sob_path_data;
    assign out_valid = CANNY_EN ? canny_path_valid : sob_path_valid;
    assign out_de    = dly_de;
    assign out_hs    = dly_hs;
    assign out_vs    = dly_vs;
    assign out_x     = (dly_x >= 11'd3) ? (dly_x - 11'd3) : {X_BITS{1'b0}};
    assign out_y     = (dly_y >= 11'd3) ? (dly_y - 11'd3) : {Y_BITS{1'b0}};

endmodule
