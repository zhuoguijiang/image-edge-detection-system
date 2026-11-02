`timescale 1ns / 1ps
// impulse at (6,5) in a 12x10 image; dump the gaussian output grid so the
// peak position can be verified against the expected output cell (2,1).
module tb_gaussian_pos;
    localparam W = 12, H = 10;
    localparam OUT_W = W - 4;       // 8
    localparam OUT_H = H - 4;       // 6

    reg clk = 0, rst_n = 0;
    reg [7:0] din = 0; reg din_valid = 0, din_vsync = 0;
    wire [7:0] dout; wire dout_valid;
    gaussian5x5 #(.WIDTH(W)) u (.clk(clk),.rst_n(rst_n),.din(din),.din_valid(din_valid),.din_vsync(din_vsync),.dout(dout),.dout_valid(dout_valid));
    always #5 clk = ~clk;

    reg [7:0] grid [0:OUT_H-1][0:OUT_W-1];
    integer rx = 0, ry = 0, done = 0;
    integer test_x, test_y, mx, my;
    integer peak = 0, nonzero = 0, symmetry_errors = 0;
    always @(negedge clk) begin
        if (rst_n && dout_valid && !done) begin
            grid[ry][rx] = dout;
            if (rx == OUT_W-1) begin rx = 0; if (ry == OUT_H-1) done = 1; else ry = ry+1; end
            else rx = rx+1;
        end
    end

    integer x, y;
    initial begin
        rst_n = 0; repeat(4) @(posedge clk); rst_n = 1;
        @(negedge clk); din_vsync = 1; din_valid = 0; @(negedge clk); din_vsync = 0;
        for (y = 0; y < H; y = y+1) begin
            for (x = 0; x < W; x = x+1) begin
                @(negedge clk);
                din = ((x == 6) && (y == 5)) ? 8'd255 : 8'd0;
                din_valid = 1;
            end
            @(negedge clk); din_valid = 0; repeat(2) @(negedge clk);
        end
        repeat(40) @(negedge clk);
        for (y = 0; y < OUT_H; y = y+1) begin
            for (x = 0; x < OUT_W; x = x+1) $write("%3d ", grid[y][x]);
            $write("\n");
        end
        for (y = 0; y < OUT_H; y = y+1)
            for (x = 0; x < OUT_W; x = x+1) begin
                if (grid[y][x] != 0) nonzero = nonzero + 1;
                if (grid[y][x] > peak) begin
                    peak = grid[y][x];
                    mx = x;
                    my = y;
                end
            end
        for (y = 1; y <= 5; y = y+1)
            for (x = 2; x <= 6; x = x+1)
                if (grid[y][x] != grid[6-y][8-x])
                    symmetry_errors = symmetry_errors + 1;

        $display("GAUSSIAN peak=%0d at (%0d,%0d) nonzero=%0d symmetry_errors=%0d",
                 peak, mx, my, nonzero, symmetry_errors);
        if (peak == 36 && mx == 4 && my == 3 && nonzero == 25 &&
            symmetry_errors == 0)
            $display("PASS: tb_gaussian_pos");
        else
            $display("FAIL: tb_gaussian_pos");
        $finish;
    end
endmodule
