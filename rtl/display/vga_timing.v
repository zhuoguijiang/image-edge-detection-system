//==============================================================================
// vga_timing : 640x480 @ 60 Hz timing generator (800 x 525 total)
//
// Pixel clock : 25 MHz (matches vendor reference "VGA_640_480_60FPS_25MHz";
//               800*525/25e6 = 59.52 Hz, within monitor tolerance).
// Sync polarity : active-low (hsync/vsync are low during the sync pulse),
//                 same convention as the vendor HDMI reference.
//==============================================================================
module vga_timing #(
    parameter H_ACTIVE = 640,
    parameter H_FRONT  = 16,
    parameter H_SYNC   = 96,
    parameter H_BACK   = 48,
    parameter V_ACTIVE = 480,
    parameter V_FRONT  = 10,
    parameter V_SYNC   = 2,
    parameter V_BACK   = 33,
    parameter H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK,  // 800
    parameter V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK,  // 525
    parameter H_BITS   = 10,
    parameter V_BITS   = 10
)(
    input  wire                clk,    // 25 MHz pixel clock
    input  wire                rst_n,  // active-low reset
    output wire                hsync,  // active-low horizontal sync
    output wire                vsync,  // active-low vertical sync
    output wire                de,     // active-area data enable
    output wire [H_BITS-1:0]   hcnt,
    output wire [V_BITS-1:0]   vcnt,
    output wire [H_BITS-1:0]   x,      // active-area column (0..H_ACTIVE-1)
    output wire [V_BITS-1:0]   y       // active-area row    (0..V_ACTIVE-1)
);

    reg [H_BITS-1:0] hcnt_r;
    reg [V_BITS-1:0] vcnt_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hcnt_r <= {H_BITS{1'b0}};
            vcnt_r <= {V_BITS{1'b0}};
        end else if (hcnt_r == H_TOTAL - 1'b1) begin
            hcnt_r <= {H_BITS{1'b0}};
            vcnt_r <= (vcnt_r == V_TOTAL - 1'b1) ? {V_BITS{1'b0}} : vcnt_r + 1'b1;
        end else begin
            hcnt_r <= hcnt_r + 1'b1;
        end
    end

    assign hcnt  = hcnt_r;
    assign vcnt  = vcnt_r;
    assign hsync = (hcnt_r >= H_SYNC);
    assign vsync = (vcnt_r >= V_SYNC);
    assign de    = (hcnt_r >= (H_SYNC + H_BACK)) && (hcnt_r < (H_SYNC + H_BACK + H_ACTIVE)) &&
                   (vcnt_r >= (V_SYNC + V_BACK)) && (vcnt_r < (V_SYNC + V_BACK + V_ACTIVE));
    assign x     = de ? (hcnt_r - (H_SYNC + H_BACK)) : {H_BITS{1'b0}};
    assign y     = de ? (vcnt_r - (V_SYNC + V_BACK)) : {V_BITS{1'b0}};

endmodule
