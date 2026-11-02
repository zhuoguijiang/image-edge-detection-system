`timescale 1ns / 1ps
//==============================================================================
// tb_gaussian5x5 : verifies the 5x5 Gaussian blur.
//   1) a flat 128 image must stay exactly 128 (kernel sums to 256/256 = 1)
//   2) a single 255 impulse must peak at 36 (255*36/256 rounded)
//==============================================================================
module tb_gaussian5x5;

    localparam W = 16;
    localparam H = 10;

    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    reg  [7:0] din = 8'd0;
    reg  din_valid = 1'b0;
    reg  din_vsync = 1'b0;

    wire [7:0] dout;
    wire       dout_valid;

    gaussian5x5 #(.WIDTH(W)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .din(din), .din_valid(din_valid), .din_vsync(din_vsync),
        .dout(dout), .dout_valid(dout_valid)
    );

    always #5 clk = ~clk;

    reg [7:0] img [0:W*H-1];
    integer x, y;
    integer errors = 0;
    integer count  = 0;
    integer peak   = 0;
    integer peak_x = -1, peak_y = -1;
    integer px = -1, py = -1;
    reg     flat;

    // check flat outputs and track the impulse peak
    always @(negedge clk) begin
        if (rst_n && dout_valid) begin
            count = count + 1;
            // during the FLAT pass the valid output must be exactly 128
            if (flat && dout !== 8'd128) begin
                $display("FAIL flat: got %0d at out #%0d", dout, count);
                errors = errors + 1;
            end
            if (!flat && dout > peak) begin
                peak = dout;
            end
        end
    end

    task run_frame;
        input integer mode;
        begin
            // mode 0 = flat, 1 = impulse
            for (y = 0; y < H; y = y + 1)
                for (x = 0; x < W; x = x + 1)
                    img[y*W + x] = 8'd0;
            if (mode == 0) begin
                for (y = 0; y < H; y = y + 1)
                    for (x = 0; x < W; x = x + 1)
                        img[y*W + x] = 8'd128;
            end else begin
                img[5*W + 8] = 8'd255;    // impulse at (8, 5)
            end

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
        end
    endtask

    initial begin
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        flat = 1'b1;
        count = 0;
        run_frame(0);
        $display("FLAT pass: %0d valid outputs, %0d errors", count, errors);
        if (count != (H-4)*(W-4)) begin
            $display("FAIL flat count: got %0d expected %0d", count, (H-4)*(W-4));
            errors = errors + 1;
        end

        flat = 1'b0;
        peak = 0;
        run_frame(1);
        $display("IMPULSE pass: peak=%0d", peak);
        if (peak !== 8'd36) begin
            $display("FAIL impulse peak: got %0d expected 36", peak);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS: gaussian5x5");
        else             $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
