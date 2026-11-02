//==============================================================================
// colorbar_hdmi_top : HDMI color-bar bring-up top for VF-Ti60F225.
// 640x480@60 (25.2 MHz pixel clock), HDMI TMDS output via the on-chip LVDS TX.
//==============================================================================
module colorbar_hdmi_top (
    input  wire        clk_24m,         // 24 MHz crystal (PLL reference)
    output wire        sys_pll_rstn_o,  // PLL reset (active-low; drive high)
    input  wire        sys_pll_lock,    // PLL locked
    input  wire        clk_sys,         // PLL feedback clock (24 MHz, kept by PLL feedback)
    input  wire        clk_pixel,       // PLL out: 25.2 MHz pixel clock
    input  wire        clk_pixel_10x,   // PLL out: 252 MHz serializer clock

    // HDMI TMDS (10-bit parallel -> LVDS TX 10:1 serializer, wired in peri.xml)
    output wire [9:0]  hdmi_txc_o,
    output wire [9:0]  hdmi_txd0_o,
    output wire [9:0]  hdmi_txd1_o,
    output wire [9:0]  hdmi_txd2_o,
    output wire        hdmi_txc_oe,
    output wire        hdmi_txd0_oe,
    output wire        hdmi_txd1_oe,
    output wire        hdmi_txd2_oe,
    output wire        hdmi_txc_rst_o,
    output wire        hdmi_txd0_rst_o,
    output wire        hdmi_txd1_rst_o,
    output wire        hdmi_txd2_rst_o
);

    // No external reset button on the minimal bring-up.
    assign sys_pll_rstn_o = 1'b1;

    // Pixel-domain reset: asserted until the PLL locks (async reset on lock).
    reg rstn_pixel;
    always @(posedge clk_pixel or negedge sys_pll_lock) begin
        if (!sys_pll_lock) rstn_pixel <= 1'b0;
        else               rstn_pixel <= 1'b1;
    end

    wire        hsync, vsync, de;
    wire [7:0]  r, g, b;

    colorbar_top u_colorbar (
        .clk  (clk_pixel),
        .rst_n(rstn_pixel),
        .hsync(hsync),
        .vsync(vsync),
        .de   (de),
        .r    (r),
        .g    (g),
        .b    (b)
    );

    // TMDS encode: produces 10-bit parallel symbols; the hardware LVDS TX
    // (configured in colorbar.peri.xml) serializes them 10:1.
    rgb2dvi #(
        .ENABLE_OSERDES(0)
    ) u_rgb2dvi (
        .PixelClk    (clk_pixel),
        .aRst        (1'b0),
        .aRst_n      (1'b1),
        .bitflip_i   (4'b0000),
        .oe_i        (1'b1),
        .vid_pVSync  (vsync),
        .vid_pHSync  (hsync),
        .vid_pVDE    (de),
        .vid_pData   ({r, g, b}),
        .SerialClk   (1'b0),   // unused (OSERDES disabled)
        .TMDS_Clk_p  (),
        .TMDS_Clk_n  (),
        .TMDS_Data_p (),
        .TMDS_Data_n (),
        .txc_o       (hdmi_txc_o),
        .txd0_o      (hdmi_txd0_o),
        .txd1_o      (hdmi_txd1_o),
        .txd2_o      (hdmi_txd2_o)
    );

    assign hdmi_txc_oe  = 1'b1;
    assign hdmi_txd0_oe = 1'b1;
    assign hdmi_txd1_oe = 1'b1;
    assign hdmi_txd2_oe = 1'b1;

    assign hdmi_txc_rst_o  = ~rstn_pixel;
    assign hdmi_txd0_rst_o = ~rstn_pixel;
    assign hdmi_txd1_rst_o = ~rstn_pixel;
    assign hdmi_txd2_rst_o = ~rstn_pixel;

endmodule
