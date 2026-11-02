//==============================================================================
// camera_top : SC2210 MIPI CSI-2 capture top (Phase 2 skeleton).
// Port names match the SC2210 reference peri.xml MIPI D-PHY gen_pin names.
//==============================================================================
module camera_top (
    input  wire        clk_sys,         // 24 MHz system clock (PLL feedback)
    input  wire        clk_pixel,       // 25 MHz pixel clock (PLL)
    output wire        sys_pll_rstn_o,  // PLL reset (drive high)
    input  wire        sys_pll_lock,    // PLL locked

    // MIPI-CSI I2C
    output wire        csi_scl_o,
    output wire        csi_scl_oe,
    input  wire        csi_scl_i,
    output wire        csi_sda_o,
    output wire        csi_sda_oe,
    input  wire        csi_sda_i,

    // MIPI-CSI RXC (clock lane)
    input  wire        csi_rxc_lp_p_i,
    input  wire        csi_rxc_lp_n_i,
    output wire        csi_rxc_hs_en_o,
    output wire        csi_rxc_hs_term_en_o,
    input  wire        csi_rxc_i,       // D-PHY RX byte clock (CLKOUT)

    // MIPI-CSI RXD0
    output wire        csi_rxd0_rst_o,
    output wire        csi_rxd0_hs_en_o,
    output wire        csi_rxd0_hs_term_en_o,
    input  wire        csi_rxd0_lp_p_i,
    input  wire        csi_rxd0_lp_n_i,
    input  wire [7:0]  csi_rxd0_hs_i,

    // MIPI-CSI RXD1
    output wire        csi_rxd1_rst_o,
    output wire        csi_rxd1_hs_en_o,
    output wire        csi_rxd1_hs_term_en_o,
    input  wire        csi_rxd1_lp_p_i,
    input  wire        csi_rxd1_lp_n_i,
    input  wire [7:0]  csi_rxd1_hs_i,

    // MIPI-CSI RXD2
    output wire        csi_rxd2_rst_o,
    output wire        csi_rxd2_hs_en_o,
    output wire        csi_rxd2_hs_term_en_o,
    input  wire        csi_rxd2_lp_p_i,
    input  wire        csi_rxd2_lp_n_i,
    input  wire [7:0]  csi_rxd2_hs_i,

    // MIPI-CSI RXD3
    output wire        csi_rxd3_rst_o,
    output wire        csi_rxd3_hs_en_o,
    output wire        csi_rxd3_hs_term_en_o,
    input  wire        csi_rxd3_lp_p_i,
    input  wire        csi_rxd3_lp_n_i,
    input  wire [7:0]  csi_rxd3_hs_i,

    // Raw pixel stream passthrough
    output wire        pixel_valid,
    output wire [63:0] pixel_data,
    output wire        pixel_vsync,
    output wire        pixel_hsync
);

    assign sys_pll_rstn_o = 1'b1;
    wire rst_n = sys_pll_lock;   // active-low reset released after PLL lock

    //-------------------------------------------------------------------------
    // I2C config: SC2210 register LUT + master. Config = {8'h60, LUT[23:0]}.
    //-------------------------------------------------------------------------
    wire [8:0]  i2c_index;
    wire [23:0] i2c_lut;
    wire [8:0]  i2c_size;
    wire        i2c_done;

    I2C_SC2210_19201080_4Lanes_Config u_sc2210_cfg (
        .LUT_INDEX(i2c_index),
        .LUT_DATA (i2c_lut),
        .LUT_SIZE (i2c_size)
    );

    i2c_timing_ctrl_16bit #(
        .CLK_FREQ(24_000000),
        .I2C_FREQ(400_000)
    ) u_i2c (
        .clk             (clk_sys),
        .rst_n           (rst_n),
        .i2c_sclk        (csi_scl_o),
        .i2c_sdat_IN     (csi_sda_i),
        .i2c_sdat_OUT    (csi_sda_o),
        .i2c_sdat_OE     (csi_sda_oe),
        .i2c_config_size (i2c_size),
        .i2c_config_index(i2c_index),
        .i2c_config_data ({8'h60, i2c_lut}),
        .i2c_config_done (i2c_done),
        .i2c_rdata       ()
    );
    assign csi_scl_oe = 1'b1;   // SCL always driven by the master

    //-------------------------------------------------------------------------
    // csi_rx soft IP (SystemVerilog). AXI tied off.
    //-------------------------------------------------------------------------
    wire        csi_rxd0_fifo_rd_o;
    wire        csi_rxd1_fifo_rd_o;
    wire        csi_rxd2_fifo_rd_o;
    wire        csi_rxd3_fifo_rd_o;
    wire        csi_rxd0_fifo_empty_i = 1'b0;
    wire        csi_rxd1_fifo_empty_i = 1'b0;
    wire        csi_rxd2_fifo_empty_i = 1'b0;
    wire        csi_rxd3_fifo_empty_i = 1'b0;
    wire [15:0] rx_word_count;
    wire [5:0]  rx_datatype;
    wire        rx_irq;

    csi_rx u_csi_rx (
        .reset_n        (rst_n),
        .clk            (clk_sys),
        .reset_byte_HS_n(rst_n),
        .clk_byte_HS    (csi_rxc_i),
        .reset_pixel_n  (rst_n),
        .clk_pixel      (clk_pixel),

        .Rx_LP_CLK_P    (csi_rxc_lp_p_i),
        .Rx_LP_CLK_N    (csi_rxc_lp_n_i),
        .Rx_HS_enable_C (csi_rxc_hs_en_o),
        .LVDS_termen_C  (csi_rxc_hs_term_en_o),

        .Rx_LP_D_P      ({csi_rxd3_lp_p_i, csi_rxd2_lp_p_i, csi_rxd1_lp_p_i, csi_rxd0_lp_p_i}),
        .Rx_LP_D_N      ({csi_rxd3_lp_n_i, csi_rxd2_lp_n_i, csi_rxd1_lp_n_i, csi_rxd0_lp_n_i}),
        .Rx_HS_D_0      (csi_rxd0_hs_i),
        .Rx_HS_D_1      (csi_rxd1_hs_i),
        .Rx_HS_D_2      (csi_rxd2_hs_i),
        .Rx_HS_D_3      (csi_rxd3_hs_i),
        .Rx_HS_D_4      (8'h00),
        .Rx_HS_D_5      (8'h00),
        .Rx_HS_D_6      (8'h00),
        .Rx_HS_D_7      (8'h00),
        .Rx_HS_enable_D ({csi_rxd3_hs_en_o, csi_rxd2_hs_en_o, csi_rxd1_hs_en_o, csi_rxd0_hs_en_o}),
        .LVDS_termen_D  ({csi_rxd3_hs_term_en_o, csi_rxd2_hs_term_en_o, csi_rxd1_hs_term_en_o, csi_rxd0_hs_term_en_o}),
        .fifo_rd_enable ({csi_rxd3_fifo_rd_o, csi_rxd2_fifo_rd_o, csi_rxd1_fifo_rd_o, csi_rxd0_fifo_rd_o}),
        .fifo_rd_empty  ({csi_rxd3_fifo_empty_i, csi_rxd2_fifo_empty_i, csi_rxd1_fifo_empty_i, csi_rxd0_fifo_empty_i}),
        .DLY_enable_D   (),
        .DLY_inc_D      (),
        .u_dly_enable_D (),
        .u_dly_inc_D    (),

        .axi_clk        (clk_sys),
        .axi_reset_n    (rst_n),
        .axi_awaddr     (6'b0),
        .axi_awvalid    (1'b0),
        .axi_awready    (),
        .axi_wdata      (32'b0),
        .axi_wvalid     (1'b0),
        .axi_wready     (),
        .axi_bvalid     (),
        .axi_bready     (1'b0),
        .axi_araddr     (6'b0),
        .axi_arvalid    (1'b0),
        .axi_arready    (),
        .axi_rdata      (),
        .axi_rvalid     (),
        .axi_rready     (1'b1),

        .vsync_vc0      (pixel_vsync),
        .vsync_vc1      (), .vsync_vc2(), .vsync_vc3(),
        .vsync_vc4      (), .vsync_vc5(), .vsync_vc6(), .vsync_vc7(),
        .vsync_vc8      (), .vsync_vc9(), .vsync_vc10(), .vsync_vc11(),
        .vsync_vc12     (), .vsync_vc13(), .vsync_vc14(), .vsync_vc15(),
        .hsync_vc0      (pixel_hsync),
        .hsync_vc1      (), .hsync_vc2(), .hsync_vc3(),
        .hsync_vc4      (), .hsync_vc5(), .hsync_vc6(), .hsync_vc7(),
        .hsync_vc8      (), .hsync_vc9(), .hsync_vc10(), .hsync_vc11(),
        .hsync_vc12     (), .hsync_vc13(), .hsync_vc14(), .hsync_vc15(),
        .vc             (),
        .vcx            (),
        .word_count     (rx_word_count),
        .shortpkt_data_field(),
        .datatype       (rx_datatype),
        .pixel_per_clk  (),
        .pixel_data     (pixel_data),
        .pixel_data_valid(pixel_valid),
        .irq            (rx_irq)
    );

    assign csi_rxd0_rst_o = ~rst_n;
    assign csi_rxd1_rst_o = ~rst_n;
    assign csi_rxd2_rst_o = ~rst_n;
    assign csi_rxd3_rst_o = ~rst_n;

endmodule
