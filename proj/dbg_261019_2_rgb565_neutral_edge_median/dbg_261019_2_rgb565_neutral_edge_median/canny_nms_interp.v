`timescale 1ns / 1ps
//==============================================================================
// canny_nms_interp : direction-interpolated non-maximum suppression.
//
// The old canny_nms quantised every gradient into four sectors. This version
// blends the cardinal and diagonal neighbours in eight ratio bands, so shallow
// diagonals compare against a value on the actual gradient direction. The
// output remains a 1-pixel ridge and uses no division or frame buffer.
//==============================================================================
module canny_nms_interp #(
    parameter DW = 12
)(
    input  wire [DW-1:0]      g00, g01, g02,
    input  wire [DW-1:0]      g10, g11, g12,
    input  wire [DW-1:0]      g20, g21, g22,
    input  wire signed [10:0] gx,
    input  wire signed [10:0] gy,
    input  wire               in_valid,
    output wire [DW-1:0]      grad_out,
    output wire               out_valid
);

    wire [10:0] ax = gx[10] ? (~gx + 11'd1) : gx;
    wire [10:0] ay = gy[10] ? (~gy + 11'd1) : gy;

    // Eight ratio bands. mix=0 is a cardinal neighbour, mix=8 a diagonal.
    reg [3:0] mix;
    always @(*) begin
        if (ax >= ay) begin
            if      (({2'b00, ay} << 2) <= {2'b00, ax})      mix = 4'd0;
            else if (({2'b00, ay} << 1) <= {2'b00, ax})      mix = 4'd2;
            else if (({2'b00, ay} + {2'b00, ay} + {2'b00, ay}) <=
                     ({2'b00, ax} << 1))                     mix = 4'd4;
            else if (({2'b00, ay} << 2) <=
                     ({2'b00, ax} + ({2'b00, ax} << 1)))     mix = 4'd6;
            else                                              mix = 4'd8;
        end else begin
            if      (({2'b00, ax} << 2) <= {2'b00, ay})      mix = 4'd0;
            else if (({2'b00, ax} << 1) <= {2'b00, ay})      mix = 4'd2;
            else if (({2'b00, ax} + {2'b00, ax} + {2'b00, ax}) <=
                     ({2'b00, ay} << 1))                     mix = 4'd4;
            else if (({2'b00, ax} << 2) <=
                     ({2'b00, ay} + ({2'b00, ay} << 1)))     mix = 4'd6;
            else                                              mix = 4'd8;
        end
    end

    reg [DW-1:0] prev_card, prev_diag, next_card, next_diag;
    always @(*) begin
        if (ax >= ay) begin
            prev_card = g10;
            next_card = g12;
            if (gy[10]) begin
                prev_diag = g20;
                next_diag = g02;
            end else begin
                prev_diag = g00;
                next_diag = g22;
            end
        end else begin
            prev_card = g01;
            next_card = g21;
            if (gx[10]) begin
                prev_diag = g02;
                next_diag = g20;
            end else begin
                prev_diag = g00;
                next_diag = g22;
            end
        end
    end

    wire [DW+3:0] prev_mix =
        (prev_card * (8 - mix) + prev_diag * mix + 4) >> 3;
    wire [DW+3:0] next_mix =
        (next_card * (8 - mix) + next_diag * mix + 4) >> 3;
    wire [DW+3:0] g11x = {{4{1'b0}}, g11};

    wire nms_ok = (g11x >= prev_mix) && (g11x > next_mix);

    assign grad_out  = nms_ok ? g11 : {DW{1'b0}};
    assign out_valid = in_valid;

endmodule
