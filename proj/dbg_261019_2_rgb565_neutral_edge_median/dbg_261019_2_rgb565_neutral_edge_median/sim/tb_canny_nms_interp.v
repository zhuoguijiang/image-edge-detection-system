`timescale 1ns / 1ps
module tb_canny_nms_interp;
    reg [11:0] g00=0,g01=0,g02=0,g10=0,g11=0,g12=0,g20=0,g21=0,g22=0;
    reg signed [10:0] gx=0, gy=0;
    reg in_valid=0;
    wire [11:0] grad_out;
    wire out_valid;
    integer errors=0;

    canny_nms_interp u_dut (
        .g00(g00), .g01(g01), .g02(g02),
        .g10(g10), .g11(g11), .g12(g12),
        .g20(g20), .g21(g21), .g22(g22),
        .gx(gx), .gy(gy), .in_valid(in_valid),
        .grad_out(grad_out), .out_valid(out_valid)
    );

    task check;
        input [11:0] expected;
        begin
            #1;
            if (grad_out !== expected || out_valid !== in_valid) begin
                $display("NMS FAIL exp=%0d got=%0d valid=%b", expected, grad_out, out_valid);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // Cardinal horizontal ridge: diagonal values must not suppress it.
        g10=12'd80; g11=12'd100; g12=12'd80;
        g00=12'd200; g22=12'd200;
        gx=11'sd1000; gy=11'sd0; in_valid=1;
        check(12'd100);

        // Same centre with diagonal neighbours at 200 is not a local maximum
        // on its +45-degree gradient direction.
        gx=11'sd1000; gy=11'sd500;
        check(12'd0);

        // A weak diagonal neighbourhood leaves the centre intact.
        g00=12'd80; g22=12'd80;
        check(12'd100);

        // Vertical ridge.
        g00=0; g01=12'd80; g02=0;
        g10=0; g11=12'd100; g12=0;
        g20=0; g21=12'd80; g22=0;
        gx=11'sd0; gy=11'sd1000;
        check(12'd100);

        // Flat ridge is suppressed.
        g01=12'd100; g11=12'd100; g21=12'd100;
        check(12'd0);

        $display("errors=%0d", errors);
        if (errors == 0) $display("PASS: tb_canny_nms_interp");
        else             $display("FAIL: tb_canny_nms_interp");
        $finish;
    end
endmodule
