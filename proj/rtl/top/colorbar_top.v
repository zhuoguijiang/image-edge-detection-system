//==============================================================================
// colorbar_top : Phase-1 display bring-up top (timing + color bar generator).
// Outputs parallel RGB + sync. The HDMI TMDS wrapper is added in a later phase.
//==============================================================================
module colorbar_top (
    input  wire       clk,    // 25 MHz pixel clock
    input  wire       rst_n,  // active-low reset
    output wire       hsync,
    output wire       vsync,
    output wire       de,
    output wire [7:0] r,
    output wire [7:0] g,
    output wire [7:0] b
);

    wire [9:0] hcnt, vcnt, x, y;

    vga_timing #(
        .H_ACTIVE(640), .H_FRONT(16), .H_SYNC(96), .H_BACK(48),
        .V_ACTIVE(480), .V_FRONT(10), .V_SYNC(2),  .V_BACK(33)
    ) u_vga (
        .clk(clk), .rst_n(rst_n),
        .hsync(hsync), .vsync(vsync), .de(de),
        .hcnt(hcnt), .vcnt(vcnt), .x(x), .y(y)
    );

    pattern_gen #(
        .ACTIVE_W(640), .ACTIVE_H(480), .X_BITS(10), .Y_BITS(10)
    ) u_pat (
        .x(x), .y(y), .de(de), .r(r), .g(g), .b(b)
    );

endmodule
