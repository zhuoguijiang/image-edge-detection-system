`timescale 1ns/1ps

//==============================================================================
// tb_video_source : verify the conservative 1080p -> 640x480 center-crop path.
//
// The DUT receives one synthetic 1920-pixel RAW8 line.  The test checks that
// the first eight output pixels are the input pixels starting at x=640, which
// confirms the horizontal center-crop offset and the line-buffer read path.
//==============================================================================
module tb_video_source;

    localparam PIX_PER_CLK = 8;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         in_valid = 1'b0;
    reg  [63:0] in_data = 64'd0;
    reg         in_line_act = 1'b0;
    reg         in_frame_act = 1'b0;

    wire [7:0]  pix_data;
    wire        pix_valid;
    wire        pix_de;
    wire        pix_hsync;
    wire        pix_vsync;
    wire [10:0] pix_x;
    wire [10:0] pix_y;
    wire        line_late;
    wire        capture_ovf;

    integer i;
    integer errors = 0;
    integer checked = 0;
    integer timeout;

    function [63:0] make_word;
        input integer word_index;
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1)
                make_word[k*8 +: 8] = (word_index*8 + k) & 8'hff;
        end
    endfunction

    // 25.2 MHz pixel clock
    always #19.84 clk = ~clk;

    video_source #(
        .H_ACTIVE   (640),
        .H_FRONT    (16),
        .H_SYNC     (96),
        .H_BACK     (48),
        .V_ACTIVE   (480),
        .V_FRONT    (10),
        .V_SYNC     (2),
        .V_BACK     (33),
        .H_BITS     (11),
        .V_BITS     (11),
        .PIX_PER_CLK(8),
        .WORD_ADDR_W(8),
        .H_OFFSET   (640)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .in_valid     (in_valid),
        .in_data      (in_data),
        .in_line_act  (in_line_act),
        .in_frame_act (in_frame_act),
        .pix_data     (pix_data),
        .pix_valid    (pix_valid),
        .pix_de       (pix_de),
        .pix_hsync    (pix_hsync),
        .pix_vsync    (pix_vsync),
        .pix_x        (pix_x),
        .pix_y        (pix_y),
        .line_late    (line_late),
        .capture_ovf  (capture_ovf)
    );

    // Check the first eight valid output pixels against the expected center crop.
    always @(posedge clk) begin
        if (rst_n && pix_valid && pix_de && (pix_x < 8)) begin
            if (pix_data !== ((640 + pix_x) & 8'hff)) begin
                $display("FAIL: x=%0d got=0x%02x expected=0x%02x",
                         pix_x, pix_data, (640 + pix_x) & 8'hff);
                errors = errors + 1;
            end else begin
                $display("PASS: x=%0d data=0x%02x", pix_x, pix_data);
            end
            checked = checked + 1;
        end
    end

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        // One active camera line: 1920 pixels = 240 64-bit words.
        @(negedge clk);
        in_frame_act = 1'b1;
        in_line_act  = 1'b1;

        for (i = 0; i < 240; i = i + 1) begin
            @(negedge clk);
            in_valid = 1'b1;
            in_data  = make_word(i);
        end

        @(negedge clk);
        in_valid    = 1'b0;
        in_line_act = 1'b0;
        in_frame_act = 1'b1;

        // Wait for the display master to adopt the published line.
        timeout = 0;
        while ((checked < 8) && (timeout < 200000)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (checked < 8) begin
            $display("FAIL: timed out waiting for output pixels");
            errors = errors + 1;
        end

        if (capture_ovf)
            errors = errors + 1;

        if (errors == 0)
            $display("TEST PASS");
        else
            $display("TEST FAIL: %0d error(s)", errors);

        $finish;
    end

endmodule
