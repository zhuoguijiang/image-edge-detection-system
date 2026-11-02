`timescale 1ns / 1ps
//==============================================================================
// measurement_timing : non-invasive camera frame timing observation
//
//   Runs in clk_pixel and observes the CSI-2 hsync/vsync stream. It does not
//   touch the video datapath.
//
//   frame_tick_o    : active-high pulse on every csi_vsync rising edge.
//   lines_pulse_o   : active-high pulse whose width is the previous complete
//                     frame length in hsync periods. At 25 MHz, one line
//                     period of pulse width corresponds to 40 ns.
//   frame_period_o  : previous complete frame period in clk_pixel cycles.
//   lines_frame_o   : previous complete frame length in hsync periods.
//   sample_valid_o  : one or more complete frame periods have been captured.
//
//   PULSE_CYCLES=4 at 25 MHz gives a 160 ns pulse, wider than the 100 ns
//   minimum requested for oscilloscope/logic-analyser capture.
//==============================================================================
module measurement_timing #(
    parameter PULSE_CYCLES = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        csi_vsync,
    input  wire        csi_hsync,
    output reg         frame_tick_o,
    output reg         lines_pulse_o,
    output reg  [19:0] frame_period_o,
    output reg  [12:0] lines_frame_o,
    output reg         sample_valid_o
);

    localparam [2:0] PULSE_INIT = PULSE_CYCLES - 1;
    reg        vsync_d;
    reg        hsync_d;
    reg [19:0] frame_period_cnt;
    reg [12:0] frame_line_cnt;
    reg [12:0] lines_pulse_cnt;
    reg [2:0]  pulse_cnt;

    wire vsync_rise = csi_vsync & ~vsync_d;
    wire hsync_rise = csi_hsync & ~hsync_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vsync_d        <= 1'b0;
            hsync_d        <= 1'b0;
            frame_period_o <= 20'd0;
            lines_frame_o  <= 13'd0;
            sample_valid_o <= 1'b0;
            frame_period_cnt <= 20'd0;
            frame_line_cnt   <= 13'd0;
            lines_pulse_cnt  <= 13'd0;
            pulse_cnt        <= 3'd0;
            frame_tick_o     <= 1'b0;
            lines_pulse_o    <= 1'b0;
        end else begin
            vsync_d <= csi_vsync;
            hsync_d <= csi_hsync;

            if (vsync_rise) begin
                if (frame_period_cnt != 20'd0) begin
                    frame_period_o <= frame_period_cnt;
                    lines_frame_o  <= frame_line_cnt;
                    sample_valid_o <= 1'b1;
                end
                frame_period_cnt <= 20'd0;
                frame_line_cnt   <= 13'd0;
                frame_tick_o     <= 1'b1;
                pulse_cnt        <= PULSE_INIT;
                if (frame_line_cnt != 13'd0) begin
                    lines_pulse_cnt <= frame_line_cnt - 1'b1;
                    lines_pulse_o   <= 1'b1;
                end else begin
                    lines_pulse_cnt <= 13'd0;
                    lines_pulse_o   <= 1'b0;
                end
            end else begin
                if (frame_period_cnt != 20'hFFFFF)
                    frame_period_cnt <= frame_period_cnt + 1'b1;

                if (pulse_cnt != 3'd0) begin
                    frame_tick_o <= 1'b1;
                    pulse_cnt    <= pulse_cnt - 1'b1;
                end else begin
                    frame_tick_o <= 1'b0;
                end

                if (lines_pulse_cnt != 13'd0) begin
                    lines_pulse_o   <= 1'b1;
                    lines_pulse_cnt <= lines_pulse_cnt - 1'b1;
                end else begin
                    lines_pulse_o <= 1'b0;
                end
            end

            if (hsync_rise && !vsync_rise)
                frame_line_cnt <= frame_line_cnt + 1'b1;
        end
    end

endmodule
