//==============================================================================
// threshold_reg : edge-detection threshold, adjusted by two debounced keys.
//
//   key_up   / key_down : one-clk pulses from key_debounce
//   threshold           : saturating W-bit register, reset value = INIT
//
// The register lives in the system (24 MHz) domain and is read by the pixel
// pipeline.  It changes only when a key is pressed, so a plain 2-FF
// synchroniser on the read side is enough - the value is static for millions
// of pixel clocks at a time.
//==============================================================================
module threshold_reg #(
    parameter W    = 8,
    parameter INIT = 8'd64,
    parameter STEP = 8'd4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_up,
    input  wire        key_down,
    output reg  [W-1:0] threshold
);

    wire [W:0] up_next   = {1'b0, threshold} + STEP;
    wire [W:0] down_next = {1'b0, threshold} - STEP;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            threshold <= INIT[W-1:0];
        end else if (key_up && !key_down) begin
            threshold <= up_next[W] ? {W{1'b1}} : up_next[W-1:0];
        end else if (key_down && !key_up) begin
            threshold <= down_next[W] ? {W{1'b0}} : down_next[W-1:0];
        end
    end

endmodule
