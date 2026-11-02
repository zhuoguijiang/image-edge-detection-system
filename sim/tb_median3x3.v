`timescale 1ns / 1ps
//==============================================================================
// tb_median3x3 : feed an image through line_buffer_3x3 + median3x3 and compare
// every interior median against the Python golden model (sim/vectors/median_exp.hex).
//==============================================================================
module tb_median3x3;

    localparam W = 16;
    localparam H = 8;

    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    reg  [7:0] din = 8'd0;
    reg  din_valid = 1'b0;
    reg  din_vsync = 1'b0;

    wire [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
    wire       lb_valid;
    wire [15:0] lb_x, lb_y;
    wire [7:0] med;
    wire       med_valid;

    line_buffer_3x3 #(.WIDTH(W), .DW(8)) u_lb (
        .clk(clk), .rst_n(rst_n),
        .din(din), .din_valid(din_valid), .din_vsync(din_vsync),
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22),
        .dout_valid(lb_valid), .dout_x(lb_x), .dout_y(lb_y)
    );

    median3x3 u_med (
        .clk(clk), .rst_n(rst_n),
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22),
        .in_valid(lb_valid),
        .med(med), .out_valid(med_valid)
    );

    always #5 clk = ~clk;

    reg [7:0] img [0:W*H-1];
    reg [7:0] exp_med [0:(W-2)*(H-2)-1];
    integer x, y, idx = 0, errors = 0;

    always @(negedge clk) begin
        if (rst_n && med_valid && idx < (W-2)*(H-2)) begin
            if (med !== exp_med[idx]) begin
                $display("FAIL idx=%0d got med=%0d exp=%0d", idx, med, exp_med[idx]);
                errors = errors + 1;
            end
            idx = idx + 1;
        end
    end

    initial begin
        $readmemh("sim/vectors/lb_img.hex", img);
        $readmemh("sim/vectors/median_exp.hex", exp_med);

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

        repeat (30) @(negedge clk);

        if (errors == 0 && idx == (W-2)*(H-2))
            $display("PASS: median3x3 verified (%0d medians)", idx);
        else
            $display("FAIL: %0d error(s), got %0d outputs (expected %0d)",
                     errors, idx, (W-2)*(H-2));
        $finish;
    end

endmodule
