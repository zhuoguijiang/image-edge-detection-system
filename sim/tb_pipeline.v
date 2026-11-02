`timescale 1ns / 1ps
//==============================================================================
// tb_pipeline : full algorithm chain.
//   bayer -> [lb1 -> debayer] -> grayscale -> [lb2 -> median3x3]
//         -> [lb3 -> sobel] -> edge
// Compares the final magnitude against the Python end-to-end reference.
// Generate vectors first:   python py/refmodel.py
//==============================================================================
module tb_pipeline;

    localparam W1 = 32;   // full frame width
    localparam W2 = W1 - 2;
    localparam W3 = W1 - 4;
    localparam H  = 16;
    localparam [11:0] THRESH = 12'd128;
    localparam NOUT = (W1 - 6) * (H - 6);   // region x in [3,W-4], y in [3,H-4]

    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    reg  [7:0] din = 8'd0;
    reg  din_valid = 1'b0;
    reg  din_vsync = 1'b0;

    // stage 1: line buffer + debayer -> RGB
    wire [7:0] a00,a01,a02,a10,a11,a12,a20,a21,a22;
    wire       a_valid;
    wire [15:0] a_x, a_y;
    wire [7:0] dr, dg, db;
    wire       db_valid;

    line_buffer_3x3 #(.WIDTH(W1)) u_lb1 (
        .clk(clk), .rst_n(rst_n), .din(din), .din_valid(din_valid), .din_vsync(din_vsync),
        .w00(a00),.w01(a01),.w02(a02),.w10(a10),.w11(a11),.w12(a12),.w20(a20),.w21(a21),.w22(a22),
        .dout_valid(a_valid), .dout_x(a_x), .dout_y(a_y)
    );
    debayer u_db (
        .clk(clk), .rst_n(rst_n),
        .w00(a00),.w01(a01),.w02(a02),.w10(a10),.w11(a11),.w12(a12),.w20(a20),.w21(a21),.w22(a22),
        .in_valid(a_valid), .in_x(a_x), .in_y(a_y),
        .r(dr), .g(dg), .b(db), .out_valid(db_valid)
    );

    // stage 2: grayscale -> line buffer + median -> Y filtered
    wire [7:0] y_gray;
    wire       y_valid, y_href, y_vsync;
    grayscale u_gray (
        .clk(clk), .rst_n(rst_n),
        .r(dr), .g(dg), .b(db),
        .in_valid(db_valid), .in_href(1'b1), .in_vsync(1'b0),
        .y(y_gray), .out_valid(y_valid), .out_href(y_href), .out_vsync(y_vsync)
    );

    wire [7:0] b00,b01,b02,b10,b11,b12,b20,b21,b22;
    wire       b_valid;
    wire [15:0] b_x, b_y;
    line_buffer_3x3 #(.WIDTH(W2)) u_lb2 (
        .clk(clk), .rst_n(rst_n), .din(y_gray), .din_valid(y_valid), .din_vsync(1'b0),
        .w00(b00),.w01(b01),.w02(b02),.w10(b10),.w11(b11),.w12(b12),.w20(b20),.w21(b21),.w22(b22),
        .dout_valid(b_valid), .dout_x(b_x), .dout_y(b_y)
    );
    wire [7:0] med;
    wire       med_valid;
    median3x3 u_med (
        .clk(clk), .rst_n(rst_n),
        .w00(b00),.w01(b01),.w02(b02),.w10(b10),.w11(b11),.w12(b12),.w20(b20),.w21(b21),.w22(b22),
        .in_valid(b_valid), .med(med), .out_valid(med_valid)
    );

    // stage 3: line buffer + sobel -> edge magnitude
    wire [7:0] c00,c01,c02,c10,c11,c12,c20,c21,c22;
    wire       c_valid;
    wire [15:0] c_x, c_y;
    line_buffer_3x3 #(.WIDTH(W3)) u_lb3 (
        .clk(clk), .rst_n(rst_n), .din(med), .din_valid(med_valid), .din_vsync(1'b0),
        .w00(c00),.w01(c01),.w02(c02),.w10(c10),.w11(c11),.w12(c12),.w20(c20),.w21(c21),.w22(c22),
        .dout_valid(c_valid), .dout_x(c_x), .dout_y(c_y)
    );
    wire [11:0] grad;
    wire        sob_valid, sob_edge;
    sobel u_sob (
        .clk(clk), .rst_n(rst_n),
        .w00(c00),.w01(c01),.w02(c02),.w10(c10),.w11(c11),.w12(c12),.w20(c20),.w21(c21),.w22(c22),
        .in_valid(c_valid), .threshold(THRESH),
        .grad(grad), .edge_out(sob_edge), .out_valid(sob_valid)
    );

    always #5 clk = ~clk;

    reg [7:0]  bayer [0:W1*H-1];
    reg [11:0] exp_mag [0:NOUT-1];
    integer x, y, idx = 0, errors = 0;

    always @(negedge clk) begin
        if (rst_n && sob_valid && idx < NOUT) begin
            if (grad !== exp_mag[idx]) begin
                $display("FAIL idx=%0d got=%0d exp=%0d", idx, grad, exp_mag[idx]);
                errors = errors + 1;
            end
            idx = idx + 1;
        end
    end

    initial begin
        $readmemh("sim/vectors/pipeline_bayer.hex", bayer);
        $readmemh("sim/vectors/pipeline_exp.hex", exp_mag);

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        din_vsync = 1'b1; din_valid = 1'b0;
        @(negedge clk);
        din_vsync = 1'b0;

        for (y = 0; y < H; y = y + 1) begin
            for (x = 0; x < W1; x = x + 1) begin
                @(negedge clk);
                din       = bayer[y*W1 + x];
                din_valid = 1'b1;
            end
            @(negedge clk);
            din_valid = 1'b0;
            repeat (2) @(negedge clk);
        end

        repeat (40) @(negedge clk);

        if (errors == 0 && idx == NOUT)
            $display("PASS: pipeline verified (%0d edge magnitudes end-to-end)", idx);
        else
            $display("FAIL: %0d error(s), got %0d outputs (expected %0d)",
                     errors, idx, NOUT);
        $finish;
    end

endmodule
