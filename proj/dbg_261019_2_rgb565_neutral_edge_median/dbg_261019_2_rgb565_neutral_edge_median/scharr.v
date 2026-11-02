`timescale 1ns / 1ps
//==============================================================================
// scharr : 3x3 Scharr gradient with the same output range/interface as sobel.
//
//   Gx = [3 0 -3; 10 0 -10; 3 0 -3] / 4
//   Gy = [3 10 3; 0 0 0; -3 -10 -3] / 4
//   grad = |Gx| + |Gy|
//
//   The 3/10/3 weights have better rotational symmetry than Sobel's 1/2/1,
//   improving diagonal response and reducing direction jitter. Division by 4
//   keeps the same 8-bit/Canny threshold scale and 11-bit direction range.
//==============================================================================
module scharr (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  w00, w01, w02,
    input  wire [7:0]  w10, w11, w12,
    input  wire [7:0]  w20, w21, w22,
    input  wire        in_valid,
    input  wire [11:0] threshold,
    output reg  [11:0] grad,
    output reg signed [10:0] gx,
    output reg signed [10:0] gy,
    output reg         edge_out,
    output reg         out_valid
);

    // stage 1: 3/10/3 weighted column and row sums (max 4080)
    reg [11:0] s1_col_r, s1_col_l, s1_row_b, s1_row_t;
    reg        s1_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_col_r <= 12'd0; s1_col_l <= 12'd0;
            s1_row_b <= 12'd0; s1_row_t <= 12'd0;
            s1_valid <= 1'b0;
        end else begin
            s1_col_r <= ({4'b0000, w02} << 1) + {4'b0000, w02} +
                        ({4'b0000, w12} << 3) + ({4'b0000, w12} << 1) +
                        ({4'b0000, w22} << 1) + {4'b0000, w22};
            s1_col_l <= ({4'b0000, w00} << 1) + {4'b0000, w00} +
                        ({4'b0000, w10} << 3) + ({4'b0000, w10} << 1) +
                        ({4'b0000, w20} << 1) + {4'b0000, w20};
            s1_row_b <= ({4'b0000, w20} << 1) + {4'b0000, w20} +
                        ({4'b0000, w21} << 3) + ({4'b0000, w21} << 1) +
                        ({4'b0000, w22} << 1) + {4'b0000, w22};
            s1_row_t <= ({4'b0000, w00} << 1) + {4'b0000, w00} +
                        ({4'b0000, w01} << 3) + ({4'b0000, w01} << 1) +
                        ({4'b0000, w02} << 1) + {4'b0000, w02};
            s1_valid <= in_valid;
        end
    end

    // stage 2: full-scale signed gradients
    reg signed [12:0] s2_gx, s2_gy;
    reg               s2_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_gx <= 13'sd0; s2_gy <= 13'sd0; s2_valid <= 1'b0;
        end else begin
            s2_gx <= $signed({1'b0, s1_col_r}) - $signed({1'b0, s1_col_l});
            s2_gy <= $signed({1'b0, s1_row_b}) - $signed({1'b0, s1_row_t});
            s2_valid <= s1_valid;
        end
    end

    // stage 3: divide by 4 and compute L1 magnitude
    reg signed [10:0] s3_gx, s3_gy;
    reg [11:0]        s3_grad;
    reg               s3_valid;
    wire signed [10:0] gx_q = s2_gx >>> 2;
    wire signed [10:0] gy_q = s2_gy >>> 2;
    wire [10:0] agx = gx_q[10] ? (~gx_q + 11'd1) : gx_q;
    wire [10:0] agy = gy_q[10] ? (~gy_q + 11'd1) : gy_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_gx <= 11'sd0; s3_gy <= 11'sd0;
            s3_grad <= 12'd0; s3_valid <= 1'b0;
        end else begin
            s3_gx <= gx_q;
            s3_gy <= gy_q;
            s3_grad <= {1'b0, agx} + {1'b0, agy};
            s3_valid <= s2_valid;
        end
    end

    // stage 4: threshold / output
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            grad <= 12'd0; gx <= 11'sd0; gy <= 11'sd0;
            edge_out <= 1'b0; out_valid <= 1'b0;
        end else begin
            grad      <= s3_grad;
            gx        <= s3_gx;
            gy        <= s3_gy;
            edge_out  <= s3_valid && (s3_grad >= threshold);
            out_valid <= s3_valid;
        end
    end

endmodule
