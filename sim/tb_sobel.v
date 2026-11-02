`timescale 1ns / 1ps
//==============================================================================
// tb_sobel : feed an image through line_buffer_3x3 + sobel and compare every
// interior magnitude against the Python golden model (sim/vectors/sobel_exp.hex).
//==============================================================================
module tb_sobel;

    localparam W = 16;
    localparam H = 8;
    localparam [11:0] THRESH = 12'd128;

    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    reg  [7:0] din = 8'd0;
    reg  din_valid = 1'b0;
    reg  din_vsync = 1'b0;

    wire [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
    wire       lb_valid;
    wire [15:0] lb_x, lb_y;
    wire [11:0] grad;
    wire        edge_out, sob_valid;

    line_buffer_3x3 #(.WIDTH(W), .DW(8)) u_lb (
        .clk(clk), .rst_n(rst_n),
        .din(din), .din_valid(din_valid), .din_vsync(din_vsync),
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22),
        .dout_valid(lb_valid), .dout_x(lb_x), .dout_y(lb_y)
    );

    sobel u_sob (
        .clk(clk), .rst_n(rst_n),
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22),
        .in_valid(lb_valid), .threshold(THRESH),
        .grad(grad), .edge_out(edge_out), .out_valid(sob_valid)
    );

    always #5 clk = ~clk;

    reg [7:0]   img [0:W*H-1];
    reg [11:0]  exp_mag [0:(W-2)*(H-2)-1];
    integer x, y, idx = 0, errors = 0;

    // Continuous checker: compare every valid output, including during the
    // blanking gaps between rows and the final pipeline drain.
    always @(negedge clk) begin
        if (rst_n && sob_valid && idx < (W-2)*(H-2)) begin
            if (grad !== exp_mag[idx]) begin
                $display("FAIL idx=%0d got grad=%0d exp=%0d", idx, grad, exp_mag[idx]);
                errors = errors + 1;
            end
            if (edge_out !== (grad >= THRESH)) begin
                $display("FAIL idx=%0d edge mismatch (grad=%0d)", idx, grad);
                errors = errors + 1;
            end
            idx = idx + 1;
        end
    end

    initial begin
        $readmemh("sim/vectors/lb_img.hex", img);
        $readmemh("sim/vectors/sobel_exp.hex", exp_mag);

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

        // drain the pipeline
        repeat (30) @(negedge clk);

        if (errors == 0 && idx == (W-2)*(H-2))
            $display("PASS: sobel verified (%0d magnitudes)", idx);
        else
            $display("FAIL: %0d error(s), got %0d outputs (expected %0d)",
                     errors, idx, (W-2)*(H-2));
        $finish;
    end

endmodule
