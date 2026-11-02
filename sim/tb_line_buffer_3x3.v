`timescale 1ns / 1ps
//==============================================================================
// tb_line_buffer_3x3 : feed a random image, check every valid 3x3 window
// against the source image array (the window must equal the true neighbourhood).
// Generate the image first:   python py/refmodel.py
//==============================================================================
module tb_line_buffer_3x3;

    localparam W = 16;
    localparam H = 8;

    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    reg  [7:0] din = 8'd0;
    reg  din_valid = 1'b0;
    reg  din_vsync = 1'b0;
    wire [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
    wire       dout_valid;
    wire [15:0] dout_x, dout_y;

    line_buffer_3x3 #(.WIDTH(W), .DW(8)) dut (
        .clk(clk), .rst_n(rst_n),
        .din(din), .din_valid(din_valid), .din_vsync(din_vsync),
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22),
        .dout_valid(dout_valid), .dout_x(dout_x), .dout_y(dout_y)
    );

    always #5 clk = ~clk;

    reg [7:0] img [0:W*H-1];
    integer x, y, errors = 0, nvalid = 0;
    integer cx, cy;

    task chk(input [7:0] got, input integer row, input integer col, input [8*8-1:0] tag);
        begin
            if (got !== img[row*W + col]) begin
                $display("FAIL %0s @(%0d,%0d) got=%0d exp=%0d", tag, cx, cy, got, img[row*W+col]);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $readmemh("sim/vectors/lb_img.hex", img);

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // frame sync pulse
        @(negedge clk);
        din_vsync = 1'b1; din_valid = 1'b0;
        @(posedge clk);
        @(negedge clk);
        din_vsync = 1'b0;

        for (y = 0; y < H; y = y + 1) begin
            for (x = 0; x < W; x = x + 1) begin
                din       = img[y*W + x];
                din_valid = 1'b1;
                @(posedge clk);
                @(negedge clk);
                if (dout_valid) begin
                    nvalid = nvalid + 1;
                    cx = dout_x;
                    cy = dout_y;
                    chk(w00, cy-1, cx-1, "w00");
                    chk(w01, cy-1, cx  , "w01");
                    chk(w02, cy-1, cx+1, "w02");
                    chk(w10, cy  , cx-1, "w10");
                    chk(w11, cy  , cx  , "w11");
                    chk(w12, cy  , cx+1, "w12");
                    chk(w20, cy+1, cx-1, "w20");
                    chk(w21, cy+1, cx  , "w21");
                    chk(w22, cy+1, cx+1, "w22");
                end
            end
            // end of active line
            din_valid = 1'b0;
            repeat (2) begin @(posedge clk); @(negedge clk); end
        end

        if (errors == 0)
            $display("PASS: line_buffer_3x3 verified (%0d windows, expected %0d)",
                     nvalid, (W-2)*(H-2));
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
