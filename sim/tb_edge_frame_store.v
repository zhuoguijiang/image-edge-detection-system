`timescale 1ns / 1ps
module tb_edge_frame_store;

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg in_bit = 1'b0;
    reg in_de = 1'b0;
    reg in_vs = 1'b0;

    reg disp_de = 1'b0;
    reg [10:0] disp_hcnt = 11'd0;
    reg [10:0] disp_x = 11'd0;
    reg [10:0] disp_y = 11'd0;

    wire out_bit, out_valid, written;

    edge_frame_store dut (
        .clk(clk), .rst_n(rst_n),
        .in_bit(in_bit), .in_de(in_de), .in_vs(in_vs),
        .disp_de(disp_de), .disp_hcnt(disp_hcnt),
        .disp_x(disp_x), .disp_y(disp_y),
        .out_bit(out_bit), .out_valid(out_valid), .written(written)
    );

    always #20 clk = ~clk;

    integer x, y;
    integer errors = 0;
    integer checked = 0;

    always @(posedge clk) begin
        if (rst_n && in_de && dut.wr_x == 7 && y == 0)
            $display("wr x=%0d acc=%b bit=%b mem0=%b", dut.wr_x, dut.byte_acc, in_bit, dut.mem[0]);
        if (rst_n && in_de && dut.wr_x == 127 && y == 0)
            $display("wr127 acc=%b bit=%b mem15=%b", dut.byte_acc, in_bit, dut.mem[15]);
        if (rst_n && disp_de && disp_y == 0 && disp_x >= 120 && disp_x <= 127)
            $display("rdb x=%0d byte=%b lat=%b out=%b", disp_x, dut.mem[15], dut.byte_lat, out_bit);
        if (rst_n && disp_de && disp_y == 0 && disp_x < 8)
            $display("rd x=%0d lat=%b out=%b", disp_x, dut.byte_lat, out_bit);
        if (rst_n && disp_y == 0 && disp_hcnt >= 140 && disp_hcnt <= 146)
            $display("pre h=%0d de=%b issue=%b latch=%b rd_en=%b rdat=%b lat=%b",
                     disp_hcnt, disp_de, dut.pre_issue, dut.pre_latch, dut.rd_en,
                     dut.rd_data, dut.byte_lat);
    end

    always @(negedge clk) begin
        if (rst_n && out_valid) begin
            if (out_bit !== ((disp_x == 123) ? 1'b1 : 1'b0)) begin
                if (errors < 8)
                    $display("FAIL read x=%0d y=%0d bit=%b", disp_x, disp_y, out_bit);
                errors = errors + 1;
            end
            checked = checked + 1;
        end
    end

    task write_frame;
        begin
            in_vs = 1'b1;
            for (y = 0; y < 480; y = y + 1) begin
                for (x = 0; x < 640; x = x + 1) begin
                    in_de = 1'b1;
                    in_bit = (x == 123);
                    @(posedge clk);
                end
                in_de = 1'b0;
                repeat (8) @(posedge clk);
            end
            in_vs = 1'b0;
            repeat (16) @(posedge clk);
        end
    endtask

    task read_frame;
        begin
            for (y = 0; y < 480; y = y + 1) begin
                for (x = 0; x < 800; x = x + 1) begin
                    disp_hcnt = x[10:0];
                    disp_de = (x >= 144 && x < 784);
                    disp_x = disp_de ? (x - 144) : 11'd0;
                    disp_y = y[10:0];
                    @(posedge clk);
                end
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;

        write_frame;
        if (!written) $display("FAIL written did not assert");

        read_frame;

        $display("edge_store: checked=%0d errors=%0d written=%b", checked, errors, written);
        if (checked != 640*480 || errors != 0 || !written)
            $display("TB_EDGE_FRAME_STORE: FAIL");
        else
            $display("TB_EDGE_FRAME_STORE: PASS");
        $finish;
    end

endmodule
