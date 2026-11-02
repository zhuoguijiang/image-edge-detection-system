`timescale 1ns / 1ps
//==============================================================================
// gaussian3x3 : optional second smoothing pass after gaussian5x5.
// Kernel = [1 2 1]^T x [1 2 1] / 16.
//==============================================================================
module gaussian3x3 #(
    parameter WIDTH = 636,
    parameter DW = 8
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire [DW-1:0] din,
    input  wire          din_valid,
    input  wire          din_vsync,
    output reg  [DW-1:0] dout,
    output reg           dout_valid
);

    wire [DW-1:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
    wire win_valid;

    line_buffer_3x3 #(.WIDTH(WIDTH), .DW(DW)) u_lb (
        .clk(clk), .rst_n(rst_n),
        .din(din), .din_valid(din_valid), .din_vsync(din_vsync),
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22),
        .dout_valid(win_valid), .dout_x(), .dout_y()
    );

    wire [11:0] corners = {4'b0000, w00} + {4'b0000, w02} +
                          {4'b0000, w20} + {4'b0000, w22};
    wire [11:0] edges2  = {3'b000, w01, 1'b0} + {3'b000, w10, 1'b0} +
                          {3'b000, w12, 1'b0} + {3'b000, w21, 1'b0};
    wire [11:0] centre4 = {2'b00, w11, 2'b00};
    wire [11:0] gsum = corners + edges2 + centre4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout <= {DW{1'b0}};
            dout_valid <= 1'b0;
        end else begin
            dout <= (gsum + 12'd8) >> 4;
            dout_valid <= win_valid;
        end
    end

endmodule
