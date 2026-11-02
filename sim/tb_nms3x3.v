`timescale 1ns / 1ps
module tb_nms3x3;
    reg clk = 1'b0, rst_n = 1'b0;
    reg [11:0] g00,g01,g02,g10,g11,g12,g20,g21,g22;
    reg signed [10:0] gx, gy;
    reg in_valid;
    reg [7:0] high_thr, low_thr;
    wire edge_out, out_valid;

    nms3x3 dut (
        .clk(clk), .rst_n(rst_n),
        .g00(g00), .g01(g01), .g02(g02),
        .g10(g10), .g11(g11), .g12(g12),
        .g20(g20), .g21(g21), .g22(g22),
        .gx(gx), .gy(gy), .in_valid(in_valid),
        .high_thr(high_thr), .low_thr(low_thr),
        .edge_out(edge_out), .out_valid(out_valid)
    );
    always #5 clk = ~clk;

    task check;
        input exp;
        input [127:0] name;
        begin
            #1;
            if (edge_out !== exp) begin
                $display("FAIL %0s edge=%b exp=%b", name, edge_out, exp);
                $finish;
            end
        end
    endtask

    initial begin
        g00=0; g01=0; g02=0; g10=0; g11=0; g12=0; g20=0; g21=0; g22=0;
        gx=0; gy=0; in_valid=1; high_thr=150; low_thr=75;

        // Horizontal: centre is the local maximum.
        g11=200; g10=100; g12=100; gx=100; gy=0;
        check(1'b1, "horizontal max");

        // Horizontal: left neighbour is stronger.
        g11=100; g10=200; g12=100;
        check(1'b0, "horizontal not max");

        // Vertical maximum.
        g11=200; g10=0; g12=0; g01=100; g21=100; gx=0; gy=100;
        check(1'b1, "vertical max");

        // Diagonal 45 maximum.
        g11=200; g01=0; g21=0; g00=100; g22=100; gx=100; gy=100;
        check(1'b1, "diag45 max");

        // Weak centre with no strong neighbour -> rejected.
        g11=100; g00=0; g01=0; g02=0; g10=0; g12=0; g20=0; g21=0; g22=0;
        gx=100; gy=0;
        check(1'b0, "weak isolated");

        // Weak centre with a strong neighbour -> local hysteresis keeps it.
        g10=50; g12=50; g01=200;
        check(1'b1, "weak connected");

        $display("TB_NMS3X3: PASS");
        $finish;
    end
endmodule
