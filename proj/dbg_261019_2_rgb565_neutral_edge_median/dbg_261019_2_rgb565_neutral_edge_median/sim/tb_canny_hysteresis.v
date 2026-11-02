`timescale 1ns / 1ps
//==============================================================================
// tb_canny_hysteresis : verifies strong/weak classification + propagation.
//
//   WIDTH = 8, four input rows are streamed.  high=128, low=64.
//   row0 : all zero
//   row1 : col2 strong(200); col3,4 weak(100); col5 none; col6 weak (isolated)
//   row2 : col3 weak -> must be confirmed via the up-right neighbour from row1
//   row3 : all zero
//
//   Expected (cols are 1..6 after the 2-column border crop):
//     output row0 (input row1): cols 2,3,4 = edge; col6 = not edge
//     output row1 (input row2): col3    = edge (down propagation)
//==============================================================================
module tb_canny_hysteresis;

    localparam W = 8;
    localparam [7:0] HIGH = 8'd128;
    localparam [7:0] LOW  = 8'd64;

    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    reg  [11:0] grad = 12'd0;
    reg  in_valid = 1'b0;
    reg  din_vsync = 1'b0;

    wire edge_out;
    wire out_valid;

    canny_hysteresis #(.WIDTH(W)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .grad(grad), .in_valid(in_valid), .din_vsync(din_vsync),
        .high_thr(HIGH), .low_thr(LOW),
        .edge_out(edge_out), .out_valid(out_valid)
    );

    always #5 clk = ~clk;

    reg [11:0] rows [0:3][0:W-1];
    integer x, y;
    integer errors = 0;

    // capture: 3 output rows x 6 valid columns
    reg [0:17] cap;
    integer cap_i = 0;
    always @(negedge clk) begin
        if (rst_n && out_valid) begin
            if (cap_i < 18) begin
                cap[cap_i] = edge_out;
                cap_i = cap_i + 1;
            end
        end
    end

    initial begin
        for (y = 0; y < 4; y = y + 1)
            for (x = 0; x < W; x = x + 1)
                rows[y][x] = 12'd0;

        rows[1][2] = 12'd200;    // strong
        rows[1][3] = 12'd100;    // weak chain
        rows[1][4] = 12'd100;
        rows[1][6] = 12'd100;    // isolated weak
        rows[2][3] = 12'd100;    // down propagation via up-right

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        din_vsync = 1'b1; in_valid = 1'b0;
        @(negedge clk);
        din_vsync = 1'b0;

        for (y = 0; y < 4; y = y + 1) begin
            for (x = 0; x < W; x = x + 1) begin
                @(negedge clk);
                grad     = rows[y][x];
                in_valid = 1'b1;
            end
            @(negedge clk);
            in_valid = 1'b0;
            repeat (2) @(negedge clk);
        end
        repeat (30) @(negedge clk);

        $display("captured=%0d", cap_i);
        // output row0 = input row1 : cols 1..6 map to cap[0..5]
        if (cap[1] !== 1'b1) begin $display("FAIL r0c2"); errors = errors + 1; end
        if (cap[2] !== 1'b1) begin $display("FAIL r0c3"); errors = errors + 1; end
        if (cap[3] !== 1'b1) begin $display("FAIL r0c4"); errors = errors + 1; end
        if (cap[5] !== 1'b0) begin $display("FAIL r0c6 isolated not dropped"); errors = errors + 1; end
        // output row1 = input row2 : col3 -> cap[6+2]
        if (cap[8] !== 1'b1) begin $display("FAIL r1c3 down propagation"); errors = errors + 1; end

        if (errors == 0) $display("PASS: canny_hysteresis");
        else             $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
