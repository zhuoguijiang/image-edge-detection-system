// Auto-generated 16x16 Chinese glyph ROM (SimSun).
// glyph index: 0=jian 1=ce 2=dao 3=yuan 4=xing 5=ju 6=wei 7=zhuang 8=san 9=jiao
module cn_font_rom (
    input  wire [3:0]  ch,
    input  wire [3:0]  row,
    output reg  [15:0] bits
);
    always @(*) begin
        bits = 16'h0000;
        case (ch)
            4'd0: case (row)
                4'd0: bits = 16'h1040;
                4'd1: bits = 16'h1040;
                4'd2: bits = 16'h10A0;
                4'd3: bits = 16'h10A0;
                4'd4: bits = 16'hFD10;
                4'd5: bits = 16'h1208;
                4'd6: bits = 16'h35F6;
                4'd7: bits = 16'h3800;
                4'd8: bits = 16'h5488;
                4'd9: bits = 16'h5048;
                4'd10: bits = 16'h9248;
                4'd11: bits = 16'h1150;
                4'd12: bits = 16'h1110;
                4'd13: bits = 16'h1020;
                4'd14: bits = 16'h17FE;
                4'd15: bits = 16'h1000;
                default: bits = 16'h0000;
            endcase
            4'd1: case (row)
                4'd0: bits = 16'h0004;
                4'd1: bits = 16'h27C4;
                4'd2: bits = 16'h1444;
                4'd3: bits = 16'h1454;
                4'd4: bits = 16'h8554;
                4'd5: bits = 16'h4554;
                4'd6: bits = 16'h4554;
                4'd7: bits = 16'h1554;
                4'd8: bits = 16'h1554;
                4'd9: bits = 16'h2554;
                4'd10: bits = 16'hE554;
                4'd11: bits = 16'h2104;
                4'd12: bits = 16'h2284;
                4'd13: bits = 16'h2244;
                4'd14: bits = 16'h2414;
                4'd15: bits = 16'h0808;
                default: bits = 16'h0000;
            endcase
            4'd2: case (row)
                4'd0: bits = 16'h0004;
                4'd1: bits = 16'hFF84;
                4'd2: bits = 16'h0804;
                4'd3: bits = 16'h1024;
                4'd4: bits = 16'h2224;
                4'd5: bits = 16'h4124;
                4'd6: bits = 16'hFFA4;
                4'd7: bits = 16'h08A4;
                4'd8: bits = 16'h0824;
                4'd9: bits = 16'h0824;
                4'd10: bits = 16'h7F24;
                4'd11: bits = 16'h0824;
                4'd12: bits = 16'h0804;
                4'd13: bits = 16'h0F84;
                4'd14: bits = 16'hF814;
                4'd15: bits = 16'h4008;
                default: bits = 16'h0000;
            endcase
            4'd3: case (row)
                4'd0: bits = 16'h7FFC;
                4'd1: bits = 16'h4004;
                4'd2: bits = 16'h4FE4;
                4'd3: bits = 16'h4824;
                4'd4: bits = 16'h4FE4;
                4'd5: bits = 16'h4004;
                4'd6: bits = 16'h5FF4;
                4'd7: bits = 16'h5014;
                4'd8: bits = 16'h5114;
                4'd9: bits = 16'h5114;
                4'd10: bits = 16'h5294;
                4'd11: bits = 16'h4444;
                4'd12: bits = 16'h4824;
                4'd13: bits = 16'h7FFC;
                4'd14: bits = 16'h4004;
                4'd15: bits = 16'h0000;
                default: bits = 16'h0000;
            endcase
            4'd4: case (row)
                4'd0: bits = 16'h7F84;
                4'd1: bits = 16'h1204;
                4'd2: bits = 16'h1208;
                4'd3: bits = 16'h1210;
                4'd4: bits = 16'h1222;
                4'd5: bits = 16'h1202;
                4'd6: bits = 16'hFFC4;
                4'd7: bits = 16'h1208;
                4'd8: bits = 16'h1210;
                4'd9: bits = 16'h1222;
                4'd10: bits = 16'h1202;
                4'd11: bits = 16'h2204;
                4'd12: bits = 16'h2208;
                4'd13: bits = 16'h4210;
                4'd14: bits = 16'h8260;
                4'd15: bits = 16'h0000;
                default: bits = 16'h0000;
            endcase
            4'd5: case (row)
                4'd0: bits = 16'h2000;
                4'd1: bits = 16'h21FE;
                4'd2: bits = 16'h3D00;
                4'd3: bits = 16'h5100;
                4'd4: bits = 16'h9100;
                4'd5: bits = 16'h11FC;
                4'd6: bits = 16'h1104;
                4'd7: bits = 16'hFF04;
                4'd8: bits = 16'h1104;
                4'd9: bits = 16'h1104;
                4'd10: bits = 16'h11FC;
                4'd11: bits = 16'h2900;
                4'd12: bits = 16'h2500;
                4'd13: bits = 16'h4500;
                4'd14: bits = 16'h41FE;
                4'd15: bits = 16'h8000;
                default: bits = 16'h0000;
            endcase
            4'd6: case (row)
                4'd0: bits = 16'h0100;
                4'd1: bits = 16'h0100;
                4'd2: bits = 16'h0100;
                4'd3: bits = 16'h3FF8;
                4'd4: bits = 16'h0100;
                4'd5: bits = 16'h0100;
                4'd6: bits = 16'h0100;
                4'd7: bits = 16'hFFFE;
                4'd8: bits = 16'h0380;
                4'd9: bits = 16'h0540;
                4'd10: bits = 16'h0920;
                4'd11: bits = 16'h1110;
                4'd12: bits = 16'h2108;
                4'd13: bits = 16'hC106;
                4'd14: bits = 16'h0100;
                4'd15: bits = 16'h0100;
                default: bits = 16'h0000;
            endcase
            4'd7: case (row)
                4'd0: bits = 16'h0840;
                4'd1: bits = 16'h0848;
                4'd2: bits = 16'h0844;
                4'd3: bits = 16'h4844;
                4'd4: bits = 16'h2840;
                4'd5: bits = 16'h2FFE;
                4'd6: bits = 16'h0840;
                4'd7: bits = 16'h0840;
                4'd8: bits = 16'h1840;
                4'd9: bits = 16'h28A0;
                4'd10: bits = 16'hC8A0;
                4'd11: bits = 16'h0890;
                4'd12: bits = 16'h0910;
                4'd13: bits = 16'h0908;
                4'd14: bits = 16'h0A04;
                4'd15: bits = 16'h0C02;
                default: bits = 16'h0000;
            endcase
            4'd8: case (row)
                4'd0: bits = 16'h0000;
                4'd1: bits = 16'h0000;
                4'd2: bits = 16'h7FFC;
                4'd3: bits = 16'h0000;
                4'd4: bits = 16'h0000;
                4'd5: bits = 16'h0000;
                4'd6: bits = 16'h0000;
                4'd7: bits = 16'h3FF8;
                4'd8: bits = 16'h0000;
                4'd9: bits = 16'h0000;
                4'd10: bits = 16'h0000;
                4'd11: bits = 16'h0000;
                4'd12: bits = 16'h0000;
                4'd13: bits = 16'hFFFE;
                4'd14: bits = 16'h0000;
                4'd15: bits = 16'h0000;
                default: bits = 16'h0000;
            endcase
            4'd9: case (row)
                4'd0: bits = 16'h0800;
                4'd1: bits = 16'h0800;
                4'd2: bits = 16'h1FE0;
                4'd3: bits = 16'h2020;
                4'd4: bits = 16'h4040;
                4'd5: bits = 16'hBFF8;
                4'd6: bits = 16'h2108;
                4'd7: bits = 16'h2108;
                4'd8: bits = 16'h3FF8;
                4'd9: bits = 16'h2108;
                4'd10: bits = 16'h2108;
                4'd11: bits = 16'h3FF8;
                4'd12: bits = 16'h2108;
                4'd13: bits = 16'h4108;
                4'd14: bits = 16'h4128;
                4'd15: bits = 16'h8010;
                default: bits = 16'h0000;
            endcase
            default: bits = 16'h0000;
        endcase
    end
endmodule
