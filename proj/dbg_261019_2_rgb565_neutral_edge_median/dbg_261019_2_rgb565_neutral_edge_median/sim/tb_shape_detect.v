`timescale 1ns / 1ps
//==============================================================================
// tb_shape_detect : synthetic 640x480 edge frames -> shape classification.
//   mode 1: circle outline  (centre 320,240 radius 120, 6 px thick)
//   mode 2: rectangle outline (200..440 x 120..360)
//   mode 0: empty frame -> none
//==============================================================================
module tb_shape_detect;

    localparam W = 640;
    localparam H = 480;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg edge_bit = 1'b0;
    reg edge_de = 1'b0;
    reg edge_vs = 1'b0;          // active low

    wire [1:0]  shape_kind;
    wire [10:0] bx0, bx1, by0, by1;
    wire        result_valid;

    shape_detect #(.H_ACTIVE(W), .V_ACTIVE(H), .GW(32), .GH(24), .CELL(20)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .edge_bit(edge_bit), .edge_de(edge_de), .edge_vs(edge_vs),
        .shape_kind(shape_kind),
        .bbox_x0(bx0), .bbox_x1(bx1), .bbox_y0(by0), .bbox_y1(by1),
        .result_valid(result_valid)
    );

    always #5 clk = ~clk;

    integer mode = 0;
    integer tx = 0, ty = 0;
    integer dx, dy, dist2;

    function real seg_dist2;
        input integer ax, ay, bx, by, px, py;
        real ldx, ldy, den, t, qx, qy;
        begin
            ldx = bx - ax; ldy = by - ay;
            den = ldx*ldx + ldy*ldy;
            if (den == 0.0) t = 0.0;
            else t = ((px-ax)*ldx + (py-ay)*ldy) / den;
            if (t < 0.0) t = 0.0;
            if (t > 1.0) t = 1.0;
            qx = ax + t*ldx;
            qy = ay + t*ldy;
            seg_dist2 = (px-qx)*(px-qx) + (py-qy)*(py-qy);
        end
    endfunction

    // edge pattern combinational on the current pixel coordinates
    always @(*) begin
        dx = tx - 320;
        dy = ty - 240;
        dist2 = dx*dx + dy*dy;
        if (mode == 1)
            edge_bit = (dist2 >= 117*117) && (dist2 <= 123*123);
        else if (mode == 2)
            edge_bit = ((ty >= 120 && ty <= 360) &&
                        (tx == 200 || tx == 201 || tx == 439 || tx == 440)) ||
                       ((tx >= 200 && tx <= 440) &&
                        (ty == 120 || ty == 121 || ty == 359 || ty == 360));
        else if (mode == 3)
            edge_bit = (seg_dist2(320,120,200,360,tx,ty) <= 4.0) ||
                       (seg_dist2(320,120,440,360,tx,ty) <= 4.0) ||
                       (seg_dist2(200,360,440,360,tx,ty) <= 4.0);
        else if (mode == 4)
            edge_bit = (((ty >= 120 && ty <= 360) &&
                         (tx == 200 || tx == 201 || tx == 439 || tx == 440)) ||
                        ((tx >= 200 && tx <= 440) &&
                         (ty == 120 || ty == 121 || ty == 359 || ty == 360)))
                       && !((tx < 235 || tx > 405) && (ty < 155 || ty > 325));
        else
            edge_bit = 1'b0;
    end

    integer got_valid = 0, got_kind = 0;
    integer got_bx0=0, got_bx1=0, got_by0=0, got_by1=0;
    always @(posedge clk) begin
        if (result_valid) begin
            got_valid = got_valid + 1;
            got_kind = shape_kind;
            got_bx0 = bx0; got_bx1 = bx1;
            got_by0 = by0; got_by1 = by1;
        end
    end

    task run_frame(input integer m);
        integer x, y;
        begin
            mode = m;
            @(negedge clk); edge_vs = 1'b0; edge_de = 1'b0;
            repeat (4) @(negedge clk);
            edge_vs = 1'b1;

            for (y = 0; y < H; y = y + 1) begin
                for (x = 0; x < W; x = x + 1) begin
                    @(negedge clk);
                    tx = x; ty = y;
                    edge_de = 1'b1;
                end
                @(negedge clk);
                edge_de = 1'b0;
                repeat (3) @(negedge clk);
            end

            // frame end -> analysis + clear + wait
            @(negedge clk); edge_vs = 1'b0; edge_de = 1'b0;
            repeat (2500) @(negedge clk);
        end
    endtask

    integer errors = 0;
    task check(input integer exp_kind, input [255:0] name);
        begin
            $display("%0s : kind=%0d bbox=(%0d,%0d)-(%0d,%0d) valid=%0d",
                     name, got_kind, got_bx0, got_by0, got_bx1, got_by1, got_valid);
            $display("   DBG cells=(%0d,%0d)-(%0d,%0d) sides t/b/l/r=%0d/%0d/%0d/%0d",
                     u_dut.gx0, u_dut.gx1, u_dut.gy0, u_dut.gy1,
                     u_dut.top_cnt, u_dut.bot_cnt, u_dut.left_cnt, u_dut.right_cnt);
            $display("   PTS=%b corners=%0d mids=%0d side_hi=%0d apex=%b",
                     u_dut.dbg_pts, u_dut.dbg_corners, u_dut.dbg_mids,
                     u_dut.dbg_side_hi, u_dut.dbg_apex);
            if (got_kind !== exp_kind) begin
                $display("FAIL: expected kind %0d", exp_kind);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        got_valid = 0;
        run_frame(1);
        check(1, "CIRCLE");

        got_valid = 0;
        run_frame(2);
        check(2, "RECT  ");

        got_valid = 0;
        run_frame(0);
        check(0, "EMPTY ");

        got_valid = 0;
        run_frame(3);
        check(3, "TRIANGLE");

        got_valid = 0;
        run_frame(4);
        check(2, "ROUNDRECT");

        if (errors == 0) $display("PASS: shape_detect");
        else             $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
