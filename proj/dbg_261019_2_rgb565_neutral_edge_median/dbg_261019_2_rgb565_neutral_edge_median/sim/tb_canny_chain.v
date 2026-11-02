`timescale 1ns / 1ps
//==============================================================================
// tb_canny_chain : full streaming Canny chain on a synthetic grayscale image.
//   grayscale -> gaussian5x5 -> line_buffer_3x3 -> sobel -> line_buffer_3x3
//             -> canny_nms -> canny_hysteresis -> edge_link3x3
//
//   Image (32 x 16): left 16 columns = 64, right 16 columns = 192 (a vertical
//   step), plus two isolated impulse noise pixels that must NOT produce edges.
//   The test asserts a clean 1-pixel-wide vertical edge at column 10. The
//   isolated impulses must not create additional edge pixels. The 404-cycle
//   first-output time is the streaming line-buffer fill time, not the 13-cycle
//   algorithmic alignment latency documented by alg_top.
//==============================================================================
module tb_canny_chain;

    localparam W = 32;
    localparam H = 16;
    localparam [7:0] THRESH = 8'd32;

    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    reg  [7:0] din = 8'd0;
    reg  din_valid = 1'b0;
    reg  din_vsync = 1'b0;

    // ---- gaussian ----
    wire [7:0] gauss_y; wire gauss_valid;
    gaussian5x5 #(.WIDTH(W)) u_gauss (
        .clk(clk), .rst_n(rst_n),
        .din(din), .din_valid(din_valid), .din_vsync(din_vsync),
        .dout(gauss_y), .dout_valid(gauss_valid)
    );

    // ---- 3x3 window + sobel ----
    wire [7:0] c00,c01,c02,c10,c11,c12,c20,c21,c22; wire c_valid;
    line_buffer_3x3 #(.WIDTH(W-4), .DW(8)) u_lb3 (
        .clk(clk), .rst_n(rst_n),
        .din(gauss_y), .din_valid(gauss_valid), .din_vsync(1'b0),
        .w00(c00), .w01(c01), .w02(c02),
        .w10(c10), .w11(c11), .w12(c12),
        .w20(c20), .w21(c21), .w22(c22),
        .dout_valid(c_valid), .dout_x(), .dout_y()
    );
    wire [11:0] c_grad; wire c_sob_valid, c_sob_edge;
    wire signed [10:0] c_gx, c_gy;
    sobel u_sob (
        .clk(clk), .rst_n(rst_n),
        .w00(c00), .w01(c01), .w02(c02),
        .w10(c10), .w11(c11), .w12(c12),
        .w20(c20), .w21(c21), .w22(c22),
        .in_valid(c_valid), .threshold(12'd0),
        .grad(c_grad), .gx(c_gx), .gy(c_gy),
        .edge_out(c_sob_edge), .out_valid(c_sob_valid)
    );

    // ---- gradient window + NMS ----
    wire [11:0] n00,n01,n02,n10,n11,n12,n20,n21,n22; wire n_valid;
    line_buffer_3x3 #(.WIDTH(W-6), .DW(12)) u_lbg (
        .clk(clk), .rst_n(rst_n),
        .din(c_grad), .din_valid(c_sob_valid), .din_vsync(1'b0),
        .w00(n00), .w01(n01), .w02(n02),
        .w10(n10), .w11(n11), .w12(n12),
        .w20(n20), .w21(n21), .w22(n22),
        .dout_valid(n_valid), .dout_x(), .dout_y()
    );
    reg signed [10:0] c_gx_d1, c_gy_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin c_gx_d1 <= 11'sd0; c_gy_d1 <= 11'sd0; end
        else begin c_gx_d1 <= c_gx; c_gy_d1 <= c_gy; end
    end
    wire [11:0] nms_grad; wire nms_valid;
    canny_nms u_nms (
        .g00(n00), .g01(n01), .g02(n02),
        .g10(n10), .g11(n11), .g12(n12),
        .g20(n20), .g21(n21), .g22(n22),
        .gx(c_gx_d1), .gy(c_gy_d1), .in_valid(n_valid),
        .grad_out(nms_grad), .out_valid(nms_valid)
    );

    // ---- hysteresis ----
    wire hyst_edge, hyst_valid;
    canny_hysteresis #(.WIDTH(W-8)) u_hyst (
        .clk(clk), .rst_n(rst_n),
        .grad(nms_grad), .in_valid(nms_valid), .din_vsync(1'b0),
        .high_thr(THRESH), .low_thr(THRESH >> 1),
        .edge_out(hyst_edge), .out_valid(hyst_valid)
    );

    // ---- directional 1px linking ----
    wire link_edge, link_valid;
    edge_link3x3 #(.WIDTH(W-10)) u_link (
        .clk(clk), .rst_n(rst_n),
        .in_edge(hyst_edge), .in_valid(hyst_valid),
        .gx(c_gx_d1), .gy(c_gy_d1),
        .out_edge(link_edge), .out_valid(link_valid)
    );

    always #5 clk = ~clk;

    // measure the chain latency (cycles from first input valid to first output)
    integer lat_cyc = 0;
    integer captured_latency = 0;
    reg     lat_done = 0;
    reg     saw_first_in = 0;
    always @(posedge clk) begin
        if (rst_n && !lat_done) begin
            if (din_valid) saw_first_in <= 1'b1;
            if (saw_first_in) lat_cyc <= lat_cyc + 1;
            if (link_valid) begin
                captured_latency = lat_cyc;
                lat_done <= 1'b1;
                $display("CHAIN LATENCY = %0d cycles", lat_cyc);
            end
        end
    end

    reg [7:0] img [0:W*H-1];
    integer x, y, expected_errors = 0;

    // capture the final edge map (COLS = W-14 = 18 valid columns per row)
    localparam COLS = W - 12;
    reg [0:COLS-1] edge_map [0:H-1];
    integer ex = 0, ey = 0;
    always @(negedge clk) begin
        if (rst_n && link_valid) begin
            if (ey < H) begin
                edge_map[ey][ex] = link_edge;
                if (ex == COLS-1) begin ex = 0; ey = ey + 1; end
                else             ex = ex + 1;
            end
        end
    end

    // print a row of the gaussian output for calibration
    integer gx = 0;
    reg [7:0] gauss_row [0:W-1];
    always @(negedge clk) begin
        if (rst_n && gauss_valid && (gx < W)) begin
            gauss_row[gx] = gauss_y;
            gx = gx + 1;
        end
    end

    initial begin
        for (y = 0; y < H; y = y + 1)
            for (x = 0; x < W; x = x + 1) begin
                img[y*W + x] = (x < 16) ? 8'd64 : 8'd192;
            end
        // isolated noise (should be smoothed out / not produce an edge)
        img[3*W + 3] = 8'd255;
        img[11*W + 28] = 8'd0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        din_vsync = 1'b1; din_valid = 1'b0;
        @(negedge clk);
        din_vsync = 1'b0;

        for (y = 0; y < H; y = y + 1) begin
            for (x = 0; x < W; x = x + 1) begin
                @(negedge clk);
                din       = img[y*W + x];
                din_valid = 1'b1;
            end
            @(negedge clk);
            din_valid = 1'b0;
            repeat (2) @(negedge clk);
        end
        repeat (60) @(negedge clk);

        $display("=== gaussian ramp (first captured row) ===");
        for (x = 0; x < W; x = x + 1) $write("%3d ", gauss_row[x]);
        $display("");

        $display("=== final Canny edge map (%0d cols x %0d rows) ===", COLS, ey);
        for (y = 0; y < ey; y = y + 1) begin
            $write("r%0d: ", y);
            for (x = 0; x < COLS; x = x + 1)
                $write("%s", edge_map[y][x] ? "#" : ".");
            $write("\n");
        end
        if (ey != 5) expected_errors = expected_errors + 1;
        for (y = 0; y < 5; y = y+1)
            for (x = 0; x < COLS; x = x+1)
                if (edge_map[y][x] !== (x == 10))
                    expected_errors = expected_errors + 1;
        if (!lat_done || captured_latency != 404)
            expected_errors = expected_errors + 1;

        $display("EXPECTED MAP: 5 rows x %0d cols, edge column 10, fill latency 404",
                 COLS);
        $display("EXPECTED ERRORS=%0d", expected_errors);
        if (expected_errors == 0) $display("PASS: tb_canny_chain");
        else                      $display("FAIL: tb_canny_chain");
        $finish;
    end

endmodule
