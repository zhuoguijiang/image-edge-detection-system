`timescale 1ns / 1ps
module tb_camera_line_unpack;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg in_hs = 1'b0;
    reg in_vs = 1'b0;
    reg [63:0] in_data = 64'd0;

    wire [7:0] out_data;
    wire out_valid, out_de, out_hs, out_vs;
    wire [10:0] out_x, out_y;

    camera_line_unpack dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_hs(in_hs), .in_vs(in_vs), .in_data(in_data),
        .out_data(out_data), .out_valid(out_valid), .out_de(out_de),
        .out_hs(out_hs), .out_vs(out_vs), .out_x(out_x), .out_y(out_y)
    );

    always #20 clk = ~clk;

    integer beat, j, line;
    integer nvalid = 0;
    integer errors = 0;
    integer exp_x = 0;
    integer exp_y = 0;
    integer cyc = 0;

    always @(posedge clk) begin
        cyc = cyc + 1;
        if (cyc < 20 || (cyc % 20 == 0 && nvalid == 0))
            $display("trace cyc=%0d rst=%b hs=%b vs=%b iv=%b wr_beat=%0d hs1=%b end=%b",
                     cyc, rst_n, in_hs, in_vs, in_valid, dut.wr_beat,
                     dut.hs_1p, dut.line_end_r);
        if (dut.line_end_r || dut.line_ready || dut.busy)
            $display("dbg t=%0t hs=%b hs1=%b end=%b ready=%b busy=%b wr_beat=%0d rd_beat=%0d rd_byte=%0d valid=%b x=%0d y=%0d",
                     $time, in_hs, dut.hs_1p, dut.line_end_r, dut.line_ready, dut.busy,
                     dut.wr_beat, dut.rd_beat, dut.rd_byte, dut.out_valid,
                     dut.out_x, dut.out_y);
        if (rst_n && out_valid) begin
            if (out_x !== exp_x[10:0] || out_y !== exp_y[10:0]) begin
                if (errors < 8)
                    $display("FAIL x=%0d exp_x=%0d y=%0d exp_y=%0d data=%0d",
                             out_x, exp_x, out_y, exp_y, out_data);
                errors = errors + 1;
            end
            if (out_data !== exp_x[7:0]) begin
                if (errors < 8)
                    $display("FAIL data=%0d expected=%0d x=%0d y=%0d",
                             out_data, exp_x[7:0], out_x, out_y);
                errors = errors + 1;
            end
            nvalid = nvalid + 1;
            exp_x = exp_x + 1;
            if (exp_x == 640) begin
                exp_x = 0;
                exp_y = exp_y + 1;
            end
        end
    end

    task send_line;
        begin
            in_hs = 1'b0; in_valid = 1'b0; in_data = 64'd0;
            repeat (8) @(posedge clk);
            in_hs = 1'b1;
            @(posedge clk);
            for (beat = 0; beat < 80; beat = beat + 1) begin
                for (j = 0; j < 8; j = j + 1)
                    in_data[8*j +: 8] = beat*8 + j;
                in_valid = 1'b1;
                @(posedge clk);
            end
            in_valid = 1'b0;
            in_hs = 1'b0;
            repeat (8) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        in_vs = 1'b1;
        send_line;
        repeat (800) @(posedge clk);
        send_line;
        in_vs = 1'b0;
        repeat (2000) @(posedge clk);

        $display("line_unpack: nvalid=%0d errors=%0d", nvalid, errors);
        if (nvalid != 1280 || errors != 0)
            $display("TB_CAMERA_LINE_UNPACK: FAIL");
        else
            $display("TB_CAMERA_LINE_UNPACK: PASS");
        $finish;
    end

endmodule
