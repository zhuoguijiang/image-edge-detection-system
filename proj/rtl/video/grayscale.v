//==============================================================================
// grayscale : RGB888 -> Y8.   Y = (77R + 150G + 29B) >> 8
// Uses multiply by constants (DSP or shift-add); no divider.
// One pipeline stage; control signals are delayed to stay aligned with data.
//==============================================================================
module grayscale (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] r,
    input  wire [7:0] g,
    input  wire [7:0] b,
    input  wire       in_valid,
    input  wire       in_href,
    input  wire       in_vsync,
    output reg  [7:0] y,
    output reg        out_valid,
    output reg        out_href,
    output reg        out_vsync
);

    // 77 + 150 + 29 = 256, so the weighted sum fits in 16 bits (max 65280).
    wire [15:0] sum = 16'd77 * r + 16'd150 * g + 16'd29 * b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y         <= 8'd0;
            out_valid <= 1'b0;
            out_href  <= 1'b0;
            out_vsync <= 1'b0;
        end else begin
            y         <= sum[15:8];
            out_valid <= in_valid;
            out_href  <= in_href;
            out_vsync <= in_vsync;
        end
    end

endmodule
