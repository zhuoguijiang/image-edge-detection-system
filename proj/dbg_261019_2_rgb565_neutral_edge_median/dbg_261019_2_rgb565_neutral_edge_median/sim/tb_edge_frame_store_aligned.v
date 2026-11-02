`timescale 1ns / 1ps
//==============================================================================
// tb_edge_frame_store_aligned : verifies coordinate-addressed edge storage.
//   The source image contains a vertical edge at x=12 and a horizontal edge
//   at y=10. ALIGN_X_SUB=2 / ALIGN_Y_SUB=3 must place them at display x=10
//   and y=7. One source beat (x=6) is intentionally omitted to prove that a
//   missing data beat no longer accumulates horizontal drift.
//==============================================================================
module tb_edge_frame_store_aligned;
    localparam H_ACTIVE = 640;
    localparam V_ACTIVE = 16;
    localparam H_SYNC   = 4;
    localparam H_BACK   = 8;
    localparam DE_START = H_SYNC + H_BACK;
    localparam H_BITS   = 11;
    localparam V_BITS   = 11;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg in_bit = 1'b0;
    reg in_de = 1'b0;
    reg in_vs = 1'b1;
    reg [H_BITS-1:0] in_x = 11'd0;
    reg [V_BITS-1:0] in_y = 11'd0;
    reg disp_de = 1'b0;
    reg [H_BITS-1:0] disp_hcnt = 11'd0;
    reg [H_BITS-1:0] disp_x = 11'd0;
    reg [V_BITS-1:0] disp_y = 11'd0;

    wire out_bit, out_valid, written;
    integer x, y, errors = 0, checked = 0;
    reg expected;

    edge_frame_store #(
        .H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE),
        .H_SYNC(H_SYNC), .H_BACK(H_BACK),
        .H_BITS(H_BITS), .V_BITS(V_BITS),
        .ROW_BYTES(H_ACTIVE/8), .MEM_DEPTH((H_ACTIVE/8)*V_ACTIVE),
        .MEM_AW(11), .ALIGN_X_SUB(2), .ALIGN_Y_SUB(3)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .in_bit(in_bit), .in_de(in_de), .in_vs(in_vs),
        .in_x(in_x), .in_y(in_y),
        .disp_de(disp_de), .disp_hcnt(disp_hcnt),
        .disp_x(disp_x), .disp_y(disp_y),
        .out_bit(out_bit), .out_valid(out_valid), .written(written)
    );

    always #5 clk = ~clk;

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (y = 0; y < V_ACTIVE; y = y+1) begin
            for (x = 0; x < H_ACTIVE; x = x+1) begin
                @(negedge clk);
                if (x != 6) begin
                    in_x = x;
                    in_y = y;
                    in_de = 1'b1;
                    in_bit = ((x == 12) || (y == 10)) ? 1'b1 : 1'b0;
                end else begin
                    in_de = 1'b0;
                end
            end
            @(negedge clk);
            in_de = 1'b0;
        end

        if (!written) begin
            $display("WRITE FAIL: frame never marked written");
            errors = errors + 1;
        end

        // Check the rows that are fully written before the test ends.
        for (y = 0; y < V_ACTIVE-4; y = y+1) begin
            disp_y = y;
            @(negedge clk); disp_de = 1'b0; disp_hcnt = DE_START - 3;
            @(negedge clk); disp_hcnt = DE_START - 2;
            @(negedge clk); disp_hcnt = DE_START - 1;
            // The Canny output is not valid in the rightmost filter border;
            // those bytes are intentionally not used by the overlay.
            for (x = 0; x < H_ACTIVE-8; x = x+1) begin
                @(negedge clk);
                disp_de = 1'b1;
                disp_hcnt = DE_START + x;
                disp_x = x;
                disp_y = y;
                #1;
                expected = ((x == 10) || ((y == 7) && (x != 4)));
                if (!out_valid || out_bit !== expected) begin
                    if (errors < 20)
                        $display("MAP FAIL x=%0d y=%0d got=%b exp=%b valid=%b",
                                 x, y, out_bit, expected, out_valid);
                    errors = errors + 1;
                end
                checked = checked + 1;
            end
            @(negedge clk); disp_de = 1'b0;
        end

        $display("checked=%0d errors=%0d (filter-valid columns only)", checked, errors);
        if (errors == 0) $display("PASS: tb_edge_frame_store_aligned");
        else             $display("FAIL: tb_edge_frame_store_aligned");
        $finish;
    end
endmodule
