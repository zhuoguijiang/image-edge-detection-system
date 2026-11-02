//==============================================================================
// debayer : RAW8 Bayer (BGGR) -> RGB888, bilinear interpolation.
//
//   BGGR layout:  B G B G
//                 G R G R
// So the centre pixel colour depends on (x,y) parity. Neighbour averages:
//   havg = (left + right) / 2          vavg = (up + down) / 2
//   davg = (4 diagonals) / 4           cavg = (4 cross neighbours) / 4
//
//   (py,px)=(0,0): centre B -> R=davg G=cavg B=centre
//   (py,px)=(1,1): centre R -> R=centre G=cavg B=davg
//   (py,px)=(0,1): centre G -> R=vavg G=centre B=havg
//   (py,px)=(1,0): centre G -> R=havg G=centre B=vavg
//==============================================================================
module debayer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  w00, w01, w02,
    input  wire [7:0]  w10, w11, w12,
    input  wire [7:0]  w20, w21, w22,
    input  wire        in_valid,
    input  wire [15:0] in_x,
    input  wire [15:0] in_y,
    output reg  [7:0]  r,
    output reg  [7:0]  g,
    output reg  [7:0]  b,
    output reg         out_valid
);

    wire [9:0] sum_h = {2'b00, w10} + {2'b00, w12};
    wire [9:0] sum_v = {2'b00, w01} + {2'b00, w21};
    wire [9:0] sum_d = {2'b00, w00} + {2'b00, w02} + {2'b00, w20} + {2'b00, w22};
    wire [9:0] sum_c = {2'b00, w10} + {2'b00, w12} + {2'b00, w01} + {2'b00, w21};

    wire [7:0] havg = sum_h[8:1];
    wire [7:0] vavg = sum_v[8:1];
    wire [7:0] davg = sum_d[9:2];
    wire [7:0] cavg = sum_c[9:2];

    wire px = in_x[0];
    wire py = in_y[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r <= 8'd0; g <= 8'd0; b <= 8'd0; out_valid <= 1'b0;
        end else begin
            if (!py && !px) begin          // centre = B
                r <= davg; g <= cavg; b <= w11;
            end else if (py && px) begin   // centre = R
                r <= w11;  g <= cavg; b <= davg;
            end else if (!py && px) begin  // centre = G (R vertical, B horizontal)
                r <= vavg; g <= w11;  b <= havg;
            end else begin                 // centre = G (R horizontal, B vertical)
                r <= havg; g <= w11;  b <= vavg;
            end
            out_valid <= in_valid;
        end
    end

endmodule
