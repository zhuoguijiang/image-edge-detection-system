`timescale 1ns / 1ps
//==============================================================================
// tb_grayscale : compare grayscale RTL output against the Python golden model.
// Generate vectors first:   python py/refmodel.py
//==============================================================================
module tb_grayscale;

    localparam N = 1024;

    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    reg  [7:0] r = 8'd0, g = 8'd0, b = 8'd0;
    reg  in_valid = 1'b0, in_href = 1'b0, in_vsync = 1'b0;
    wire [7:0] y;
    wire out_valid, out_href, out_vsync;

    grayscale dut (
        .clk(clk), .rst_n(rst_n),
        .r(r), .g(g), .b(b),
        .in_valid(in_valid), .in_href(in_href), .in_vsync(in_vsync),
        .y(y), .out_valid(out_valid), .out_href(out_href), .out_vsync(out_vsync)
    );

    always #5 clk = ~clk;   // 100 MHz simulation clock

    reg [23:0] rgb_arr [0:N-1];
    reg [7:0]  exp_arr [0:N-1];
    integer i;
    integer errors = 0;

    initial begin
        $readmemh("sim/vectors/gray_rgb.hex", rgb_arr);
        $readmemh("sim/vectors/gray_exp.hex", exp_arr);

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        for (i = 0; i < N; i = i + 1) begin
            r        = rgb_arr[i][23:16];
            g        = rgb_arr[i][15:8];
            b        = rgb_arr[i][7:0];
            in_valid = 1'b1;
            in_href  = 1'b1;
            in_vsync = 1'b0;
            @(posedge clk);   // DUT registers y
            @(negedge clk);   // y stable
            if (y !== exp_arr[i]) begin
                $display("FAIL idx=%0d rgb=(%0d,%0d,%0d) got=%0d exp=%0d",
                         i, r, g, b, y, exp_arr[i]);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("PASS: grayscale verified (%0d vectors)", N);
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
