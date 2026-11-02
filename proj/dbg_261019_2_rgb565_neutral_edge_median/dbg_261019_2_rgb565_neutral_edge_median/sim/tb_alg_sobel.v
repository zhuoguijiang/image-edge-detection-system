`timescale 1ns / 1ps
// regression: alg_top with the original Sobel path (CANNY_EN=0) must still
// produce a vertical edge on the same synthetic image.
module tb_alg_sobel;
    localparam W = 32, H = 16;
    reg clk = 0, rst_n = 0;
    reg [7:0] in_data = 0; reg in_valid = 0, in_de = 0, in_hs = 1, in_vs = 1;
    reg [10:0] in_x = 0, in_y = 0; reg [7:0] threshold = 8'd32;
    wire [7:0] out_data, out_gray; wire out_valid, out_de, out_hs, out_vs;
    wire [10:0] out_x, out_y;

    alg_top #(
        .WIDTH(W), .LATENCY(14), .X_BITS(11), .Y_BITS(11),
        .EDGE_FILTER(2'd2), .NMS_EN(1'b1), .LINK_EN(1'b1), .CANNY_EN(1'b0)
    ) u_alg (
        .clk(clk), .rst_n(rst_n),
        .in_data(in_data), .in_valid(in_valid), .in_de(in_de),
        .in_hs(in_hs), .in_vs(in_vs), .in_x(in_x), .in_y(in_y),
        .threshold(threshold),
        .out_data(out_data), .out_gray(out_gray), .out_valid(out_valid),
        .out_de(out_de), .out_hs(out_hs), .out_vs(out_vs),
        .out_x(out_x), .out_y(out_y)
    );

    always #5 clk = ~clk;
    integer x, y, violations = 0, edge_count = 0;
    integer edge_pixels = 0, edge_errors = 0, missing_rows = 0;
    reg [0:W-1] edge_col [0:H-1];
    reg edge_seen_row [0:H-1];

    always @(negedge clk) begin
        if (rst_n && out_valid) begin
            if (!out_de) violations = violations + 1;
            if (out_y < H && out_x < W) begin
                edge_col[out_y][out_x] = out_data[7];
                edge_count = edge_count + 1;
                if (out_data[7] !=
                    ((out_x == 11'd24) && (out_y >= 11'd7) && (out_y <= 11'd11))) begin
                    $display("SOBEL MAP ERROR x=%0d y=%0d data=%02x", out_x, out_y, out_data);
                    edge_errors = edge_errors + 1;
                end
                if (out_data[7]) begin
                    edge_pixels = edge_pixels + 1;
                    edge_seen_row[out_y] = 1'b1;
                end
            end
        end
    end

    initial begin
        rst_n = 0; repeat(4) @(posedge clk); rst_n = 1;
        for (y = 0; y < H; y = y + 1) begin
            edge_seen_row[y] = 1'b0;
            for (x = 0; x < W; x = x + 1)
                edge_col[y][x] = 1'b0;
        end
        @(negedge clk); in_vs = 0; in_valid = 0; in_de = 0;
        @(negedge clk); in_vs = 1;
        for (y = 0; y < H; y = y+1) begin
            for (x = 0; x < W; x = x+1) begin
                @(negedge clk);
                in_data = (x < 16) ? 8'd64 : 8'd192;
                in_valid = 1; in_de = 1; in_x = x; in_y = y;
            end
            @(negedge clk); in_valid = 0; in_de = 0; repeat(2) @(negedge clk);
        end
        repeat(60) @(negedge clk);
        $display("SOBEL valid_pixels=%0d edge_pixels=%0d violations=%0d edge_errors=%0d",
                 edge_count, edge_pixels, violations, edge_errors);
        for (y = 0; y < H; y = y+1) begin
            $write("y%0d: ", y);
            for (x = 0; x < W; x = x+1) begin
                if (edge_col[y][x] === 1'bx) $write(" ");
                else                          $write("%s", edge_col[y][x] ? "#" : ".");
            end
            $write("\n");
        end
        for (y = 7; y <= 11; y = y + 1)
            if (!edge_seen_row[y])
                missing_rows = missing_rows + 1;

        if (violations == 0 && edge_errors == 0 && edge_pixels == 5 &&
            missing_rows == 0 && edge_count >= 100)
            $display("PASS: alg_top Sobel expected edge map");
        else
            $display("FAIL: alg_top Sobel expected edge map");
        $finish;
    end
endmodule
