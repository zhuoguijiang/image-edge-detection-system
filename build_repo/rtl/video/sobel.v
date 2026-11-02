//==============================================================================
// sobel : 3x3 Sobel edge detection on one window.
//   Gx   = (w02 + 2*w12 + w22) - (w00 + 2*w10 + w20)   (right - left)
//   Gy   = (w20 + 2*w21 + w22) - (w00 + 2*w01 + w02)   (bottom - top)
//   grad = |Gx| + |Gy|            (no sqrt; saves DSP)
//   edge = (grad >= threshold)
// Four pipeline stages (partial sums -> Gx/Gy -> |Gx|+|Gy| -> threshold).
//==============================================================================
module sobel (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  w00, w01, w02,
    input  wire [7:0]  w10, w11, w12,
    input  wire [7:0]  w20, w21, w22,
    input  wire        in_valid,
    input  wire [11:0] threshold,
    output reg  [11:0] grad,
    output reg         edge_out,
    output reg         out_valid
);

    // ---- stage 1: column / row partial sums (10-bit, max 1020) ----
    reg [9:0] s1_col_r, s1_col_l, s1_row_b, s1_row_t;
    reg       s1_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_col_r <= 10'd0; s1_col_l <= 10'd0;
            s1_row_b <= 10'd0; s1_row_t <= 10'd0;
            s1_valid <= 1'b0;
        end else begin
            s1_col_r <= {2'b00, w02} + {1'b0, w12, 1'b0} + {2'b00, w22};
            s1_col_l <= {2'b00, w00} + {1'b0, w10, 1'b0} + {2'b00, w20};
            s1_row_b <= {2'b00, w20} + {1'b0, w21, 1'b0} + {2'b00, w22};
            s1_row_t <= {2'b00, w00} + {1'b0, w01, 1'b0} + {2'b00, w02};
            s1_valid <= in_valid;
        end
    end

    // ---- stage 2: signed gradients (11-bit signed, range -1020..1020) ----
    reg signed [10:0] s2_gx, s2_gy;
    reg               s2_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_gx <= 11'sd0; s2_gy <= 11'sd0; s2_valid <= 1'b0;
        end else begin
            s2_gx <= {1'b0, s1_col_r} - {1'b0, s1_col_l};
            s2_gy <= {1'b0, s1_row_b} - {1'b0, s1_row_t};
            s2_valid <= s1_valid;
        end
    end

    // ---- stage 3: |Gx| + |Gy| (12-bit, max 2040) ----
    reg [11:0] s3_grad;
    reg        s3_valid;
    wire [10:0] agx = s2_gx[10] ? (~s2_gx + 11'd1) : s2_gx;
    wire [10:0] agy = s2_gy[10] ? (~s2_gy + 11'd1) : s2_gy;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin s3_grad <= 12'd0; s3_valid <= 1'b0; end
        else begin
            s3_grad <= {1'b0, agx} + {1'b0, agy};
            s3_valid <= s2_valid;
        end
    end

    // ---- stage 4: threshold ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            grad <= 12'd0; edge_out <= 1'b0; out_valid <= 1'b0;
        end else begin
            grad      <= s3_grad;
            edge_out  <= s3_valid && (s3_grad >= threshold);
            out_valid <= s3_valid;
        end
    end

endmodule
