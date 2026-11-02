`timescale 1ns / 1ps
//==============================================================================
// tb_alg_top : drive the frozen pixel-stream interface through the real
// algorithm chain and check every valid edge pixel against the Python
// full-image reference (sim/vectors/alg_exp.hex), indexed by out_x/out_y.
//==============================================================================
module tb_alg_top;

    localparam W = 32;
    localparam H = 16;
    localparam [7:0] THRESH = 8'd128;

    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    reg  [7:0]  din = 8'd0;
    reg         din_valid = 1'b0, din_de = 1'b0, din_hs = 1'b1, din_vs = 1'b1;
    reg  [10:0] din_x = 11'd0, din_y = 11'd0;

    wire [7:0]  dout;
    wire        dvalid, dde, dhs, dvs;
    wire [10:0] dx, dy;

    alg_top #(.WIDTH(W), .X_BITS(11), .Y_BITS(11), .LATENCY(12)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_data(din), .in_valid(din_valid), .in_de(din_de),
        .in_hs(din_hs), .in_vs(din_vs),
        .in_x(din_x), .in_y(din_y),
        .threshold(THRESH),
        .out_data(dout), .out_valid(dvalid), .out_de(dde),
        .out_hs(dhs), .out_vs(dvs),
        .out_x(dx), .out_y(dy)
    );

    always #5 clk = ~clk;

    reg [7:0]  bayer   [0:W*H-1];
    reg [11:0] exp_mag [0:W*H-1];
    integer x, y, i, errors = 0, nvalid = 0;
    integer idx;
    reg [7:0] exp_byte;

    always @(negedge clk) begin
        if (rst_n && dvalid) begin
            idx = dy * W + dx;
            if (idx >= 0 && idx < W*H) begin
                exp_byte = (exp_mag[idx] >= {4'b0000, THRESH}) ? 8'hFF : 8'h00;
            end else begin
                // position outside the image -> must be blanked
                exp_byte = 8'h00;
            end
            if (dout !== exp_byte) begin
                $display("FAIL (%0d,%0d) got=%0d exp=%0d mag=%0d",
                         dx, dy, dout, exp_byte, exp_mag[idx]);
                errors = errors + 1;
            end
            nvalid = nvalid + 1;
        end
    end

    initial begin
        $readmemh("sim/vectors/pipeline_bayer.hex", bayer);
        $readmemh("sim/vectors/alg_exp.hex", exp_mag);

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // frame sync (active low)
        @(negedge clk);
        din_vs = 1'b0; din_de = 1'b0; din_valid = 1'b0; din_hs = 1'b1;
        @(negedge clk);
        @(negedge clk);
        din_vs = 1'b1;

        for (y = 0; y < H; y = y + 1) begin
            @(negedge clk);
            din_hs = 1'b0; din_de = 1'b0; din_valid = 1'b0;
            repeat (2) @(negedge clk);
            din_hs = 1'b1;
            for (x = 0; x < W; x = x + 1) begin
                @(negedge clk);
                din       = bayer[y*W + x];
                din_valid = 1'b1;
                din_de    = 1'b1;
                din_x     = x[10:0];
                din_y     = y[10:0];
            end
            @(negedge clk);
            din_valid = 1'b0; din_de = 1'b0;
            repeat (2) @(negedge clk);
        end

        repeat (60) @(negedge clk);

        if (errors == 0 && nvalid > 0)
            $display("PASS: alg_top verified (%0d valid edge pixels)", nvalid);
        else
            $display("FAIL: %0d error(s), %0d valid pixels", errors, nvalid);
        $finish;
    end

endmodule
