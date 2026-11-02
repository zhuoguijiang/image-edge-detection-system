`timescale 1ns / 1ps
//==============================================================================
// shape_overlay : draw the shape-recognition result on the display stream.
//
//   - a green 2-pixel bounding box around the detected shape
//   - a black label box at (16,16) with white 16x16 Chinese glyphs, scaled 2x:
//         none   -> "wei jian ce dao xing zhuang"  (6 glyphs)
//         circle -> "jian ce dao yuan xing"        (5 glyphs)
//         rect   -> "jian ce dao ju xing"          (5 glyphs)
//
//   All positions use the 640x480 display coordinate space.
//==============================================================================
module shape_overlay #(
    parameter X_BITS = 11,
    parameter Y_BITS = 11
)(
    input  wire [1:0]       shape_kind,   // 0 none, 1 circle, 2 rectangle
    input  wire [10:0]      bbox_x0,
    input  wire [10:0]      bbox_x1,
    input  wire [10:0]      bbox_y0,
    input  wire [10:0]      bbox_y1,

    input  wire             de,
    input  wire [X_BITS-1:0] x,
    input  wire [Y_BITS-1:0] y,

    input  wire [7:0]       in_r,
    input  wire [7:0]       in_g,
    input  wire [7:0]       in_b,

    output reg  [7:0]       out_r,
    output reg  [7:0]       out_g,
    output reg  [7:0]       out_b
);

    //--------------------------------------------------------------------------
    // Label layout: 6 cells of 32x32 at (16,16), glyph rendered at 2x scale.
    //--------------------------------------------------------------------------
    localparam [10:0] TX0 = 11'd16;
    localparam [10:0] TY0 = 11'd16;
    localparam [10:0] TW  = 11'd192;
    localparam [10:0] TH  = 11'd32;

    wire [10:0] tx = x - TX0;
    wire [10:0] ty = y - TY0;
    wire        in_box = de && (x >= TX0) && (x < TX0 + TW) &&
                              (y >= TY0) && (y < TY0 + TH);
    wire [2:0]  ci = tx[10:5];       // /32 : character slot
    wire [3:0]  gc = tx[4:1];        // ((x-16)>>1) & 15
    wire [3:0]  gr = ty[4:1];        // ((y-16)>>1) & 15

    reg [3:0] glyph_idx;
    reg [3:0] txt_len;
    always @(*) begin
        glyph_idx = 4'd0;
        txt_len   = 4'd0;
        case (shape_kind)
            2'd1: begin                       // circle: jian ce dao yuan xing
                txt_len = 4'd5;
                case (ci)
                    3'd0: glyph_idx = 4'd0;
                    3'd1: glyph_idx = 4'd1;
                    3'd2: glyph_idx = 4'd2;
                    3'd3: glyph_idx = 4'd3;
                    3'd4: glyph_idx = 4'd4;
                    default: glyph_idx = 4'd0;
                endcase
            end
            2'd2: begin                       // rect: jian ce dao ju xing
                txt_len = 4'd5;
                case (ci)
                    3'd0: glyph_idx = 4'd0;
                    3'd1: glyph_idx = 4'd1;
                    3'd2: glyph_idx = 4'd2;
                    3'd3: glyph_idx = 4'd5;
                    3'd4: glyph_idx = 4'd4;
                    default: glyph_idx = 4'd0;
                endcase
            end
            2'd3: begin                       // triangle: jian ce dao san jiao xing
                txt_len = 4'd6;
                case (ci)
                    3'd0: glyph_idx = 4'd0;
                    3'd1: glyph_idx = 4'd1;
                    3'd2: glyph_idx = 4'd2;
                    3'd3: glyph_idx = 4'd8;
                    3'd4: glyph_idx = 4'd9;
                    3'd5: glyph_idx = 4'd4;
                    default: glyph_idx = 4'd0;
                endcase
            end
            default: begin                    // none: wei jian ce dao xing zhuang
                txt_len = 4'd6;
                case (ci)
                    3'd0: glyph_idx = 4'd6;
                    3'd1: glyph_idx = 4'd0;
                    3'd2: glyph_idx = 4'd1;
                    3'd3: glyph_idx = 4'd2;
                    3'd4: glyph_idx = 4'd4;
                    3'd5: glyph_idx = 4'd7;
                    default: glyph_idx = 4'd0;
                endcase
            end
        endcase
    end

    wire [15:0] font_bits;
    cn_font_rom u_font (
        .ch(glyph_idx),
        .row(gr),
        .bits(font_bits)
    );

    wire glyph_on = in_box && (ci < txt_len) && font_bits[15 - gc];

    //--------------------------------------------------------------------------
    // Green bounding box (2 pixels thick)
    //--------------------------------------------------------------------------
    wire in_x  = (x >= bbox_x0) && (x <= bbox_x1);
    wire in_y  = (y >= bbox_y0) && (y <= bbox_y1);
    wire near_l = (x + 11'd2 >= bbox_x0) && (x <= bbox_x0 + 11'd2);
    wire near_r = (x + 11'd2 >= bbox_x1) && (x <= bbox_x1 + 11'd2);
    wire near_t = (y + 11'd2 >= bbox_y0) && (y <= bbox_y0 + 11'd2);
    wire near_b = (y + 11'd2 >= bbox_y1) && (y <= bbox_y1 + 11'd2);

    wire on_bbox = de && (shape_kind != 2'd0) &&
                   ((in_y && (near_l || near_r)) ||
                    (in_x && (near_t || near_b)));

    //--------------------------------------------------------------------------
    // Overlay priority: label box > bounding box > original pixel
    //--------------------------------------------------------------------------
    always @(*) begin
        out_r = in_r;
        out_g = in_g;
        out_b = in_b;

        if (in_box) begin
            if (glyph_on) begin
                out_r = 8'hFF; out_g = 8'hFF; out_b = 8'hFF;
            end else begin
                out_r = 8'h00; out_g = 8'h00; out_b = 8'h00;
            end
        end else if (on_bbox) begin
            out_r = 8'h00; out_g = 8'hFF; out_b = 8'h00;
        end
    end

endmodule
