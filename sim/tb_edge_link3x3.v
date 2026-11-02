`timescale 1ns / 1ps
module tb_edge_link3x3;
    localparam W = 16;
    reg clk = 1'b0, rst_n = 1'b0;
    reg in_edge = 1'b0, in_valid = 1'b0;
    reg signed [10:0] gx = 11'sd0, gy = 11'sd100;
    wire out_edge, out_valid;

    edge_link3x3 #(.WIDTH(W)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_edge(in_edge), .in_valid(in_valid),
        .gx(gx), .gy(gy),
        .out_edge(out_edge), .out_valid(out_valid)
    );
    always #5 clk = ~clk;

    integer line, x;
    integer checked = 0, errors = 0;

    always @(negedge clk) begin
        if (rst_n && out_valid && dut.u_lb.dout_y == 2 && dut.u_lb.dout_x == 8) begin
            checked = checked + 1;
            if (out_edge !== 1'b1) begin
                $display("FAIL gap not linked at x=%0d y=%0d edge=%b e00=%b e01=%b e02=%b e10=%b e11=%b e12=%b e20=%b e21=%b e22=%b gx=%0d gy=%0d",
                         dut.u_lb.dout_x, dut.u_lb.dout_y, out_edge,
                         dut.e00, dut.e01, dut.e02, dut.e10, dut.e11, dut.e12,
                         dut.e20, dut.e21, dut.e22, gx, gy);
                errors = errors + 1;
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        in_valid = 1'b1;

        // Four lines: line 0 is a warm-up, line 2 has a single-pixel gap at
        // x=8 in an otherwise horizontal edge.  A vertical gradient means the
        // edge runs horizontally, so e10/e12 should bridge the gap.
        for (line = 0; line < 4; line = line + 1) begin
            for (x = 0; x < W; x = x + 1) begin
                in_edge = (line != 0) && !((line == 2) && (x == 8));
                @(posedge clk);
            end
        end
        in_valid = 1'b0;
        repeat (8) @(posedge clk);

        $display("edge_link: checked=%0d errors=%0d", checked, errors);
        if (checked == 0 || errors != 0) $display("TB_EDGE_LINK3X3: FAIL");
        else $display("TB_EDGE_LINK3X3: PASS");
        $finish;
    end
endmodule
