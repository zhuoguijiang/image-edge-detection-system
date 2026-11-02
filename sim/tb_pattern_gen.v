`timescale 1ns / 1ps
//==============================================================================
// tb_pattern_gen : verify the 8 vertical color bars.
//==============================================================================
module tb_pattern_gen;

    reg  [9:0] x = 10'd0;
    reg  [9:0] y = 10'd0;
    reg        de = 1'b0;
    wire [7:0] r, g, b;

    pattern_gen dut (
        .x(x), .y(y), .de(de),
        .r(r), .g(g), .b(b)
    );

    integer errors = 0;

    initial begin
        de = 1'b1;
        for (x = 0; x < 640; x = x + 1) begin
            #1;
            check;
        end

        de = 1'b0;
        #1;
        if (r !== 8'd0 || g !== 8'd0 || b !== 8'd0) begin
            $display("FAIL: RGB not zero when de=0 (%0d,%0d,%0d)", r, g, b);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: pattern_gen verified (8 bars x 80 px)");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

    task check;
        reg [7:0] er, eg, eb;
        begin
            case (x / 80)
                3'd0 : begin er = 255; eg = 0;   eb = 0;   end
                3'd1 : begin er = 255; eg = 128; eb = 0;   end
                3'd2 : begin er = 255; eg = 255; eb = 0;   end
                3'd3 : begin er = 0;   eg = 255; eb = 0;   end
                3'd4 : begin er = 0;   eg = 255; eb = 255; end
                3'd5 : begin er = 0;   eg = 0;   eb = 255; end
                3'd6 : begin er = 255; eg = 0;   eb = 255; end
                default : begin er = 255; eg = 255; eb = 255; end
            endcase
            if (r !== er || g !== eg || b !== eb) begin
                $display("FAIL: x=%0d got (%0d,%0d,%0d) expected (%0d,%0d,%0d)",
                         x, r, g, b, er, eg, eb);
                errors = errors + 1;
            end
        end
    endtask

endmodule
