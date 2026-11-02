//==============================================================================
// pattern_gen : 8 vertical color bars for display-path bring-up (Phase 1).
//==============================================================================
module pattern_gen #(
    parameter ACTIVE_W = 640,
    parameter ACTIVE_H = 480,
    parameter X_BITS   = 10,
    parameter Y_BITS   = 10
)(
    input  wire [X_BITS-1:0] x,
    input  wire [Y_BITS-1:0] y,
    input  wire              de,
    output wire [7:0]        r,
    output wire [7:0]        g,
    output wire [7:0]        b
);

    localparam BAR_W = ACTIVE_W / 8;   // 80 pixels per bar

    reg [7:0] r_r, g_r, b_r;
    always @(*) begin
        if (!de) begin
            r_r = 8'd0; g_r = 8'd0; b_r = 8'd0;
        end else begin
            case (x / BAR_W)
                3'd0 : {r_r, g_r, b_r} = {8'd255, 8'd0,   8'd0};    // red
                3'd1 : {r_r, g_r, b_r} = {8'd255, 8'd128, 8'd0};    // orange
                3'd2 : {r_r, g_r, b_r} = {8'd255, 8'd255, 8'd0};    // yellow
                3'd3 : {r_r, g_r, b_r} = {8'd0,   8'd255, 8'd0};    // green
                3'd4 : {r_r, g_r, b_r} = {8'd0,   8'd255, 8'd255};  // cyan
                3'd5 : {r_r, g_r, b_r} = {8'd0,   8'd0,   8'd255};  // blue
                3'd6 : {r_r, g_r, b_r} = {8'd255, 8'd0,   8'd255};  // magenta
                default : {r_r, g_r, b_r} = {8'd255, 8'd255, 8'd255}; // white
            endcase
        end
    end

    assign r = r_r;
    assign g = g_r;
    assign b = b_r;

endmodule
