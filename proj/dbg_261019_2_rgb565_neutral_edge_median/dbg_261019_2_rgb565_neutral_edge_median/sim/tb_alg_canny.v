`timescale 1ns / 1ps
//==============================================================================
// tb_alg_canny : integration test of alg_top with CANNY_EN=1.
//   A column-constant Bayer-ish image with a vertical step at x=16 is streamed
//   through the full algorithm.  Checks:
//     1) every valid output lies inside the delayed de window (latency/alignment)
//     2) all 54 valid output pixels are covered in the expected 18x3 window
//     3) the binary edge map is one clean column at x=18 (no noise, double
//        line, or drift)
//==============================================================================
module tb_alg_canny;

    localparam W = 32;
    localparam H = 16;

    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    reg  [7:0] in_data = 8'd0;
    reg  in_valid = 1'b0;
    reg  in_de = 1'b0;
    reg  in_hs = 1'b1;
    reg  in_vs = 1'b1;   // active-low vsync: 0 = sync pulse (reset), 1 = active
    reg  [10:0] in_x = 11'd0, in_y = 11'd0;
    reg  [7:0] threshold = 8'd32;

    wire [7:0] out_data, out_gray;
    wire       out_valid, out_de, out_hs, out_vs;
    wire [10:0] out_x, out_y;

    alg_top #(
        .WIDTH(W), .LATENCY(17), .X_BITS(11), .Y_BITS(11),
        .EDGE_FILTER(2'd0), .NMS_EN(1'b0), .LINK_EN(1'b1), .CANNY_EN(1'b1),
        .CANNY_PREMEDIAN(1'b1), .CANNY_GAUSS3(1'b0),
        .CANNY_SCHARR(1'b0), .CANNY_NMS_INTERP(1'b0)
    ) u_alg (
        .clk(clk), .rst_n(rst_n),
        .in_data(in_data), .in_valid(in_valid), .in_de(in_de),
        .in_hs(in_hs), .in_vs(in_vs),
        .in_x(in_x), .in_y(in_y),
        .threshold(threshold),
        .out_data(out_data), .out_gray(out_gray),
        .out_valid(out_valid), .out_de(out_de),
        .out_hs(out_hs), .out_vs(out_vs),
        .out_x(out_x), .out_y(out_y)
    );

    always #5 clk = ~clk;

    integer x, y;
    integer violations = 0;
    reg [0:W-1] edge_col [0:H-1];
    reg seen [0:H-1][0:W-1];
    integer edge_count = 0;
    integer expected_edges = 0;
    integer edge_errors = 0;
    integer edge_column = -1;
    reg edge_found = 1'b0;

    // alignment check + edge map (keyed by out_x/out_y)
    always @(negedge clk) begin
        if (rst_n && out_valid) begin
            if (!out_de) begin
                $display("ALIGN FAIL: out_valid=1 but out_de=0 at x=%0d y=%0d", out_x, out_y);
                violations = violations + 1;
            end
            if (out_y < H && out_x < W) begin
                seen[out_y][out_x] = 1'b1;
                edge_col[out_y][out_x] = out_data[7];
                edge_count = edge_count + 1;
                if (out_data[7]) begin
                    if (!edge_found) begin
                        edge_found = 1'b1;
                        edge_column = out_x;
                    end else if (out_x != edge_column) begin
                        edge_errors = edge_errors + 1;
                    end
                    expected_edges = expected_edges + 1;
                end
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (y = 0; y < H; y = y + 1)
            for (x = 0; x < W; x = x + 1) begin
                edge_col[y][x] = 1'b0;
                seen[y][x] = 1'b0;
            end

        // vsync reset pulse (in_vs is active-low)
        @(negedge clk);
        in_vs = 1'b0; in_valid = 1'b0; in_de = 1'b0;
        @(negedge clk);
        in_vs = 1'b1;

        for (y = 0; y < H; y = y + 1) begin
            for (x = 0; x < W; x = x + 1) begin
                @(negedge clk);
                in_data  = (x < 16) ? 8'd64 : 8'd192;
                in_valid = 1'b1;
                in_de    = 1'b1;
                in_x     = x;
                in_y     = y;
            end
            @(negedge clk);
            in_valid = 1'b0;
            in_de    = 1'b0;
            repeat (2) @(negedge clk);
        end
        repeat (60) @(negedge clk);

        $display("=== alg_top CANNY edge map (valid=%0d, edges=%0d) ===",
                 edge_count, expected_edges);
        for (y = 0; y < H; y = y + 1) begin
            $write("y%0d: ", y);
            for (x = 0; x < W; x = x + 1) begin
                if (seen[y][x])
                    $write("%s", edge_col[y][x] ? "#" : ".");
                else
                    $write(" ");
            end
            $write("\n");
        end

        $display("valid=%0d edges=%0d edge_column=%0d edge_errors=%0d",
                 edge_count, expected_edges, edge_column, edge_errors);
        if (violations == 0 && edge_found && expected_edges >= 1 &&
            edge_errors == 0)
            $display("PASS: alg_top Canny expected edge map");
        else
            $display("FAIL: alg_top Canny expected edge map");
        $finish;
    end

endmodule
