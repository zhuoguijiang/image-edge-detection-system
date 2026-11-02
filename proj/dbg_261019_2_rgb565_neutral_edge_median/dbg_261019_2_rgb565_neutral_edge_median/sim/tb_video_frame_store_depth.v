`timescale 1ns / 1ps
//==============================================================================
// tb_video_frame_store_depth : checks the 9600-word preview store end-to-end.
//   Each camera line is tagged with its line number.  With the default
//   v_last=480 the DDA keeps odd lines (1,3,5,...), so display row y must show
//   the tag of camera line ((y & ~1) + 1).
//==============================================================================
module tb_video_frame_store_depth;

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg         in_valid = 1'b0;
    reg  [63:0] in_data = 64'd0;
    reg         in_line_act = 1'b0;
    reg         in_frame_act = 1'b0;

    wire [7:0]  pix_data;
    wire        pix_valid, pix_de, pix_hsync, pix_vsync;
    wire [10:0] pix_x, pix_hcnt, pix_y, pix_y_act;
    wire        line_late, capture_ovf, buf_written;

    video_frame_store u_store (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_data(in_data),
        .in_line_act(in_line_act), .in_frame_act(in_frame_act),
        .pix_data(pix_data), .pix_valid(pix_valid), .pix_de(pix_de),
        .pix_hsync(pix_hsync), .pix_vsync(pix_vsync),
        .pix_x(pix_x), .pix_hcnt(pix_hcnt), .pix_y(pix_y),
        .pix_y_act(pix_y_act),
        .line_late(line_late), .capture_ovf(capture_ovf),
        .buf_written(buf_written)
    );

    always #5 clk = ~clk;

    reg     checking = 1'b0;
    integer cnt = 0, err = 0;
    wire [10:0] exp_tag = (((pix_y_act & 11'h7FE) + 11'd1) & 11'h0FF);

    always @(negedge clk) begin
        if (rst_n && checking && pix_de && pix_valid) begin
            cnt = cnt + 1;
            if (pix_data !== exp_tag[7:0]) begin
                if (err < 10)
                    $display("MISMATCH x=%0d y=%0d got=%0d exp=%0d",
                             pix_x, pix_y_act, pix_data, exp_tag[7:0]);
                err = err + 1;
            end
        end
    end

    integer x, y;
    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        in_frame_act = 1'b1;

        for (y = 0; y < 480; y = y + 1) begin
            @(negedge clk);
            in_line_act = 1'b1;
            for (x = 0; x < 80; x = x + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                in_data  = {8{y[7:0]}};
            end
            @(negedge clk);
            in_valid = 1'b0;
            in_line_act = 1'b0;
            repeat (2) @(negedge clk);
        end

        @(negedge clk);
        in_frame_act = 1'b0;

        wait (buf_written);
        repeat (450000) @(negedge clk);   // skip the partially written display frame
        checking = 1'b1;
        repeat (450000) @(negedge clk);

        $display("pixels=%0d errors=%0d buf_written=%0d", cnt, err, buf_written);
        if (err == 0 && cnt > 300000) $display("PASS: video_frame_store depth");
        else                          $display("FAIL: video_frame_store depth");
        $finish;
    end

endmodule
