`timescale 1ns / 1ps
module tb_adaptive_median;
    reg clk = 1'b0, rst_n = 1'b0, in_valid = 1'b0;
    reg [7:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;
    wire [7:0] med, med_adaptive;
    wire out_valid;

    median3x3 #(.ADAPT_TOL(8'd12), .ADAPT_MAX_SIM(4'd1)) dut (
        .clk(clk), .rst_n(rst_n),
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22),
        .in_valid(in_valid), .med(med), .med_adaptive(med_adaptive),
        .out_valid(out_valid)
    );
    always #5 clk = ~clk;

    task drive;
        begin
            in_valid = 1'b1;
            @(posedge clk);
            in_valid = 1'b0;
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // isolated outlier: replace with median (=100)
        w00=100; w01=100; w02=100;
        w10=100; w11=255; w12=100;
        w20=100; w21=100; w22=100;
        drive;
        if (med !== 8'd100 || med_adaptive !== 8'd100) begin
            $display("FAIL outlier med=%0d adaptive=%0d", med, med_adaptive);
            $finish;
        end

        // 1-pixel vertical line: two similar vertical neighbours -> keep 200
        w00=100; w01=200; w02=100;
        w10=100; w11=200; w12=100;
        w20=100; w21=200; w22=100;
        drive;
        if (med_adaptive !== 8'd200) begin
            $display("FAIL line med=%0d adaptive=%0d", med, med_adaptive);
            $finish;
        end

        $display("TB_ADAPTIVE_MEDIAN: PASS");
        $finish;
    end
endmodule
