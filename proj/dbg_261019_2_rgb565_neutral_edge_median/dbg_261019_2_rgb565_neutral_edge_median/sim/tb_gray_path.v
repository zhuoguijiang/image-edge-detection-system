`timescale 1ns / 1ps
// isolates the mode-1 gray path: vga timing -> luma -> line buffer -> median
// -> 12-cycle delay.  Reports how many gray pixels are valid in one frame.
module tb_gray_path;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    wire de, hsync, vsync;
    wire [10:0] hcnt, vcnt, x, y;
    vga_timing #(
        .H_ACTIVE(640), .H_FRONT(16), .H_SYNC(96), .H_BACK(48),
        .V_ACTIVE(480), .V_FRONT(10), .V_SYNC(2), .V_BACK(33),
        .H_BITS(11), .V_BITS(11), .GENLOCK(0)
    ) u_t (
        .clk(clk), .rst_n(rst_n), .frame_restart(1'b0),
        .hsync(hsync), .vsync(vsync), .de(de),
        .hcnt(hcnt), .vcnt(vcnt), .x(x), .y(y)
    );

    wire [7:0] pix_luma = 8'd128;
    wire [7:0] gm00, gm01, gm02, gm10, gm11, gm12, gm20, gm21, gm22;
    wire gm_wvalid;
    wire [15:0] gm_wx, gm_wy;
    line_buffer_3x3 #(.WIDTH(640), .DW(8)) u_lb (
        .clk(clk), .rst_n(rst_n),
        .din(pix_luma), .din_valid(de), .din_vsync(~vsync),
        .w00(gm00), .w01(gm01), .w02(gm02),
        .w10(gm10), .w11(gm11), .w12(gm12),
        .w20(gm20), .w21(gm21), .w22(gm22),
        .dout_valid(gm_wvalid), .dout_x(gm_wx), .dout_y(gm_wy)
    );

    wire [7:0] gray_med, gray_adapt;
    wire gray_valid;
    median3x3 u_med (
        .clk(clk), .rst_n(rst_n),
        .w00(gm00), .w01(gm01), .w02(gm02),
        .w10(gm10), .w11(gm11), .w12(gm12),
        .w20(gm20), .w21(gm21), .w22(gm22),
        .in_valid(gm_wvalid), .med(gray_med), .med_adaptive(gray_adapt),
        .out_valid(gray_valid)
    );

    wire [7:0] gray_d;
    wire gray_d_valid, gray_d_de, gray_d_hs, gray_d_vs;
    wire [10:0] gray_d_x, gray_d_y;
    video_delay #(.STAGES(12), .X_BITS(11), .Y_BITS(11)) u_d (
        .clk(clk), .rst_n(rst_n),
        .in_data(gray_med), .in_valid(gray_valid), .in_de(gray_valid),
        .in_hs(1'b1), .in_vs(1'b0),
        .in_x(11'd0), .in_y(11'd0),
        .out_data(gray_d), .out_valid(gray_d_valid), .out_de(gray_d_de),
        .out_hs(gray_d_hs), .out_vs(gray_d_vs),
        .out_x(gray_d_x), .out_y(gray_d_y)
    );

    integer lb_valid = 0, med_valid = 0, d_valid = 0;
    always @(negedge clk) begin
        if (rst_n && de && gm_wvalid) lb_valid = lb_valid + 1;
        if (rst_n && gray_valid) med_valid = med_valid + 1;
        if (rst_n && gray_d_valid) d_valid = d_valid + 1;
    end

    always #5 clk = ~clk;
    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (450000) @(negedge clk);
        $display("lb_valid=%0d med_valid=%0d delayed_valid=%0d gray_d=%0d",
                 lb_valid, med_valid, d_valid, gray_d);
        if (d_valid > 1000 && gray_d == 8'd128) $display("PASS: gray path");
        else $display("FAIL: gray path");
        $finish;
    end
endmodule
