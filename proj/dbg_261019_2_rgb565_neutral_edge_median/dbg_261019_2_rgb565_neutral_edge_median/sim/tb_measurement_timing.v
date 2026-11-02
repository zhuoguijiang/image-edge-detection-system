`timescale 1ns / 1ps
//==============================================================================
// tb_measurement_timing : checks the frame tick width and timing sample path.
//==============================================================================
module tb_measurement_timing;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg csi_vsync = 1'b0;
    reg csi_hsync = 1'b0;

    wire frame_tick;
    wire lines_pulse;
    wire [19:0] frame_period;
    wire [12:0] lines_frame;
    wire sample_valid;

    measurement_timing #(.PULSE_CYCLES(4)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .csi_vsync(csi_vsync), .csi_hsync(csi_hsync),
        .frame_tick_o(frame_tick),
        .lines_pulse_o(lines_pulse),
        .frame_period_o(frame_period),
        .lines_frame_o(lines_frame),
        .sample_valid_o(sample_valid)
    );

    always #10 clk = ~clk;

    integer tick_cycles = 0;
    integer lines_pulse_cycles = 0;
    integer lines_sent = 0;
    integer errors = 0;
    reg count_tick = 1'b0;
    reg count_lines_pulse = 1'b0;

    always @(posedge clk) begin
        if (rst_n && count_tick && frame_tick)
            tick_cycles = tick_cycles + 1;
        if (rst_n && count_lines_pulse && lines_pulse)
            lines_pulse_cycles = lines_pulse_cycles + 1;
    end

    task emit_line;
        begin
            @(negedge clk); csi_hsync = 1'b1;
            @(negedge clk); csi_hsync = 1'b0;
            lines_sent = lines_sent + 1;
        end
    endtask

    task emit_frame_edge;
        begin
            @(negedge clk); csi_vsync = 1'b1;
            @(negedge clk); csi_vsync = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // First edge initialises the counters but cannot form a period yet.
        emit_frame_edge();
        repeat (6) @(negedge clk);
        tick_cycles = 0;
        lines_pulse_cycles = 0;
        count_tick = 1'b1;
        count_lines_pulse = 1'b1;

        repeat (4) emit_line();
        repeat (8) @(negedge clk);
        emit_frame_edge();
        repeat (6) @(negedge clk);

        if (tick_cycles != 4) begin
            $display("TICK WIDTH FAIL: expected 4 cycles, got %0d", tick_cycles);
            errors = errors + 1;
        end
        if (!sample_valid) begin
            $display("SAMPLE VALID FAIL");
            errors = errors + 1;
        end
        if (frame_period == 0) begin
            $display("FRAME PERIOD FAIL: zero");
            errors = errors + 1;
        end
        if (lines_frame != 4) begin
            $display("LINE COUNT FAIL: expected 4, got %0d", lines_frame);
            errors = errors + 1;
        end
        if (lines_pulse_cycles != 4) begin
            $display("LINE PULSE FAIL: expected 4 cycles, got %0d", lines_pulse_cycles);
            errors = errors + 1;
        end

        $display("FRAME PERIOD=%0d cycles, LINES=%0d, TICK=%0d cycles, LINES_PULSE=%0d cycles",
                 frame_period, lines_frame, tick_cycles, lines_pulse_cycles);
        if (errors == 0) $display("PASS: measurement_timing");
        else             $display("FAIL: measurement_timing errors=%0d", errors);
        $finish;
    end

endmodule
