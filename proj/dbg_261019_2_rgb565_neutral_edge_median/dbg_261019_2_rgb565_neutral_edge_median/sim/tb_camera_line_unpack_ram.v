`timescale 1ns / 1ps
//==============================================================================
// tb_camera_line_unpack_ram : 3 lines x 80 beats -> 1920 pixels, checks the
// exact byte order and (x,y) coordinates after the single-RAM conversion.
//   line L, beat b, byte k carries (L*128 + b*8 + k) & 0xFF, so the expected
//   pixel at (x,y) is (y*128 + x) & 0xFF.
//==============================================================================
module tb_camera_line_unpack_ram;

    localparam H_ACTIVE = 640;
    localparam H_BEATS  = 80;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg in_hs = 1'b0;
    reg in_vs = 1'b1;          // active low
    reg [63:0] in_data = 64'd0;

    wire [7:0]  out_data;
    wire        out_valid, out_de, out_hs, out_vs;
    wire [10:0] out_x, out_y;

    camera_line_unpack u_dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_hs(in_hs), .in_vs(in_vs), .in_data(in_data),
        .out_data(out_data), .out_valid(out_valid), .out_de(out_de),
        .out_hs(out_hs), .out_vs(out_vs),
        .out_x(out_x), .out_y(out_y)
    );

    always #5 clk = ~clk;

    integer exp_x = 0, exp_y = 0, checked = 0, err = 0;
    always @(negedge clk) begin
        if (rst_n && out_valid && out_de) begin
            if (out_x !== exp_x || out_y !== exp_y) begin
                if (err < 10)
                    $display("COORD x=%0d y=%0d exp (%0d,%0d)", out_x, out_y, exp_x, exp_y);
                err = err + 1;
            end
            if (out_data !== ((exp_y * 128 + exp_x) & 8'hFF)) begin
                if (err < 10)
                    $display("DATA got=%0d exp=%0d at (%0d,%0d)",
                             out_data, ((exp_y * 128 + exp_x) & 8'hFF), exp_x, exp_y);
                err = err + 1;
            end
            checked = checked + 1;
            if (exp_x == H_ACTIVE-1) begin
                exp_x = 0;
                exp_y = exp_y + 1;
            end else begin
                exp_x = exp_x + 1;
            end
        end
    end

    integer line, b, k;
    initial begin
        rst_n = 1'b0;
        in_vs = 1'b0;             // active-low reset of the frame state
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(negedge clk);
        in_vs = 1'b1;

        for (line = 0; line < 3; line = line + 1) begin
            @(negedge clk);
            in_hs = 1'b1;
            for (b = 0; b < H_BEATS; b = b + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                for (k = 0; k < 8; k = k + 1)
                    in_data[k*8 +: 8] = (line*128 + b*8 + k) & 8'hFF;
            end
            @(negedge clk);
            in_valid = 1'b0;
            in_hs = 1'b0;
            repeat (700) @(negedge clk);
        end

        repeat (800) @(negedge clk);
        in_vs = 1'b0;

        $display("checked=%0d errors=%0d rows=%0d", checked, err, exp_y);
        if (err == 0 && checked == 3*H_ACTIVE)
            $display("PASS: camera_line_unpack single RAM");
        else
            $display("FAIL: camera_line_unpack single RAM");
        $finish;
    end

endmodule
