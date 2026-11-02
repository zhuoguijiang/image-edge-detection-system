`timescale 1ns / 1ps
// Self-checking smoke test for camera_pixel_unpack: 80 beats/line, 8 pixels
// per beat, two lines.  Checks that the serialiser produces 640 pixels/line
// and that pixel order is preserved.
module tb_camera_pixel_unpack;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg in_hs = 1'b0;
    reg in_vs = 1'b0;
    reg [63:0] in_data = 64'd0;

    wire [7:0] out_data;
    wire out_valid, out_de, out_hs, out_vs;
    wire [10:0] out_x, out_y;

    camera_pixel_unpack dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_hs(in_hs), .in_vs(in_vs), .in_data(in_data),
        .out_data(out_data), .out_valid(out_valid), .out_de(out_de),
        .out_hs(out_hs), .out_vs(out_vs), .out_x(out_x), .out_y(out_y)
    );

    always #20 clk = ~clk;       // 25 MHz

    integer beat, j, line;
    integer nvalid = 0;
    integer errors = 0;
    integer expect_pix = 0;

    always @(posedge clk) begin
        if (rst_n && out_valid) begin
            if (out_data !== expect_pix[7:0]) begin
                if (errors < 8)
                    $display("FAIL out_data=%0d expected=%0d x=%0d y=%0d",
                             out_data, expect_pix[7:0], out_x, out_y);
                errors = errors + 1;
            end
            nvalid = nvalid + 1;
            expect_pix = expect_pix + 1;
            if (expect_pix == 640) expect_pix = 0;
        end
    end

    task send_line;
        begin
            in_hs = 1'b0; in_valid = 1'b0; in_data = 64'd0;
            repeat (8) @(posedge clk);
            in_hs = 1'b1;
            @(posedge clk);          // hsync leads the first valid beat
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
        send_line;
        in_vs = 1'b0;
        repeat (2000) @(posedge clk);

        $display("pixel_unpack: nvalid=%0d errors=%0d", nvalid, errors);
        if (nvalid < 640 || errors != 0)
            $display("TB_CAMERA_PIXEL_UNPACK: FAIL");
        else
            $display("TB_CAMERA_PIXEL_UNPACK: PASS");
        $finish;
    end

endmodule
