`timescale 1ns / 1ps
//==============================================================================
// tb_rgb332_preview_store : drives 480 camera lines of known RGB and checks
// the display-side RGB332 expansion.
//   input R = line[7:0], G = col[7:0], B = 0
//   DDA keeps lines 59,119,...,479; horizontal keeps even columns.
//   For display (x,y): line = 59 + 60*(y/2), col = 2*(x/2).
//==============================================================================
module tb_rgb332_preview_store;

    localparam H_ACTIVE = 64;
    localparam H_BITS = 11;
    localparam V_ACTIVE = 16;
    localparam V_BITS = 11;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] in_r = 8'd0, in_g = 8'd0, in_b = 8'd0;
    reg in_valid = 1'b0;
    reg in_line_act = 1'b0;
    reg in_frame_act = 1'b0;

    wire [7:0] pix_r, pix_g, pix_b;
    wire pix_valid, pix_de, pix_hsync, pix_vsync;
    wire [H_BITS-1:0] pix_x, pix_hcnt;
    wire [V_BITS-1:0] pix_y, pix_y_act;
    wire line_late, capture_ovf, buf_written;

    rgb332_preview_store #(
        .H_ACTIVE(H_ACTIVE), .H_FRONT(4), .H_SYNC(8), .H_BACK(8),
        .V_ACTIVE(V_ACTIVE), .V_FRONT(2), .V_SYNC(1), .V_BACK(2),
        .H_BITS(H_BITS), .V_BITS(V_BITS),
        .SW(320), .SH(8), .ROW_W(40), .WORD_AW(6), .ROW_AW(3),
        .MEM_AW(14), .MEM_DEPTH(320)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .in_r(in_r), .in_g(in_g), .in_b(in_b), .in_valid(in_valid),
        .in_line_act(in_line_act), .in_frame_act(in_frame_act),
        .pix_r(pix_r), .pix_g(pix_g), .pix_b(pix_b),
        .pix_valid(pix_valid), .pix_de(pix_de),
        .pix_hsync(pix_hsync), .pix_vsync(pix_vsync),
        .pix_x(pix_x), .pix_hcnt(pix_hcnt),
        .pix_y(pix_y), .pix_y_act(pix_y_act),
        .line_late(line_late), .capture_ovf(capture_ovf),
        .buf_written(buf_written)
    );

    always #5 clk = ~clk;

    reg checking = 1'b0;
    integer cnt = 0, err = 0;
    integer line_exp, col_exp;
    reg [7:0] r332, g332, b332;
    reg [7:0] er, eg, eb;

    always @(negedge clk) begin
        if (rst_n && checking && pix_de && pix_valid) begin
            line_exp = 59 + 60*(pix_y_act >> 1);
            col_exp  = 2*(pix_x >> 1);
            r332 = line_exp[7:0];
            g332 = col_exp[7:0];
            b332 = 8'h00;
            er = {r332[7:5], r332[7:5], r332[7:6]};
            eg = {g332[7:5], g332[7:5], g332[7:6]};
            eb = 8'h00;
            if (pix_r !== er || pix_g !== eg || pix_b !== eb) begin
                if (err < 10)
                    $display("MISMATCH x=%0d y=%0d rgb=%02x/%02x/%02x exp=%02x/%02x/%02x",
                             pix_x, pix_y_act, pix_r, pix_g, pix_b, er, eg, eb);
                err = err + 1;
            end
            cnt = cnt + 1;
        end
    end

    integer line, col;
    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        in_frame_act = 1'b1;

        for (line = 0; line < 480; line = line + 1) begin
            @(negedge clk);
            in_line_act = 1'b1;
            for (col = 0; col < H_ACTIVE; col = col + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                in_r = line[7:0];
                in_g = col[7:0];
                in_b = 8'd0;
            end
            @(negedge clk);
            in_valid = 1'b0;
            in_line_act = 1'b0;
            repeat (4) @(negedge clk);
        end

        @(negedge clk);
        in_frame_act = 1'b0;

        repeat (60000) @(negedge clk);
        checking = 1'b1;
        repeat (60000) @(negedge clk);

        $display("pixels=%0d errors=%0d buf_written=%0d", cnt, err, buf_written);
        if (err == 0 && cnt > 800) $display("PASS: rgb332_preview_store");
        else                       $display("FAIL: rgb332_preview_store");
        $finish;
    end

endmodule
