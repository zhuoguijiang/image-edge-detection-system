//==============================================================================
// system_top : full  camera + algorithm + split-screen + HDMI  integration
//
//   SC2210 (MIPI 4-lane RAW8)
//     -> MIPI D-PHY RX + csi_rx soft IP        (byte clk -> clk_pixel)
//     -> video_source                          (ping-pong line buffer,
//                                               640x480@60 display master)
//     -> alg_stub / alg_top + video_delay      (latency-matched branches)
//     -> split_mux                             (left = raw, right = edge)
//     -> rgb2dvi -> on-chip LVDS TX -> HDMI
//
// Keys : key_up / key_dn adjust the edge threshold at run time.
//
// NOTE ON THE CLOCK DOMAINS
//   csi_rx already contains the byte-clock -> pixel-clock dual-clock FIFO, so
//   everything downstream of csi_rx lives in clk_pixel.  The only remaining
//   asynchronous inputs are the two push buttons, which are debounced
//   directly in clk_pixel.
//==============================================================================
module system_top (
    input  wire        clk_24m,          // 24 MHz crystal (PLL reference)
    output wire        sys_pll_rstn_o,   // PLL reset, active low -> drive high
    input  wire        sys_pll_lock,     // PLL locked
    input  wire        clk_sys,          // PLL out : 24 MHz system clock
    input  wire        clk_pixel,        // PLL out : 25.2 MHz pixel clock
    input  wire        clk_pixel_10x,    // PLL out : 252 MHz serializer clock

    //------------------------------------------------------------------
    // MIPI-CSI I2C
    //------------------------------------------------------------------
    output wire        csi_scl_o,
    output wire        csi_scl_oe,
    input  wire        csi_scl_i,
    output wire        csi_sda_o,
    output wire        csi_sda_oe,
    input  wire        csi_sda_i,

    //------------------------------------------------------------------
    // MIPI-CSI RXC (clock lane)
    //------------------------------------------------------------------
    input  wire        csi_rxc_lp_p_i,
    input  wire        csi_rxc_lp_n_i,
    output wire        csi_rxc_hs_en_o,
    output wire        csi_rxc_hs_term_en_o,
    input  wire        csi_rxc_i,        // D-PHY RX byte clock (CLKOUT)

    //------------------------------------------------------------------
    // MIPI-CSI RXD0
    //------------------------------------------------------------------
    output wire        csi_rxd0_rst_o,
    output wire        csi_rxd0_hs_en_o,
    output wire        csi_rxd0_hs_term_en_o,
    input  wire        csi_rxd0_lp_p_i,
    input  wire        csi_rxd0_lp_n_i,
    input  wire [7:0]  csi_rxd0_hs_i,

    //------------------------------------------------------------------
    // MIPI-CSI RXD1
    //------------------------------------------------------------------
    output wire        csi_rxd1_rst_o,
    output wire        csi_rxd1_hs_en_o,
    output wire        csi_rxd1_hs_term_en_o,
    input  wire        csi_rxd1_lp_p_i,
    input  wire        csi_rxd1_lp_n_i,
    input  wire [7:0]  csi_rxd1_hs_i,

    //------------------------------------------------------------------
    // MIPI-CSI RXD2
    //------------------------------------------------------------------
    output wire        csi_rxd2_rst_o,
    output wire        csi_rxd2_hs_en_o,
    output wire        csi_rxd2_hs_term_en_o,
    input  wire        csi_rxd2_lp_p_i,
    input  wire        csi_rxd2_lp_n_i,
    input  wire [7:0]  csi_rxd2_hs_i,

    //------------------------------------------------------------------
    // MIPI-CSI RXD3
    //------------------------------------------------------------------
    output wire        csi_rxd3_rst_o,
    output wire        csi_rxd3_hs_en_o,
    output wire        csi_rxd3_hs_term_en_o,
    input  wire        csi_rxd3_lp_p_i,
    input  wire        csi_rxd3_lp_n_i,
    input  wire [7:0]  csi_rxd3_hs_i,

    //------------------------------------------------------------------
    // HDMI TMDS (10-bit parallel -> on-chip LVDS TX 10:1 serializer)
    //------------------------------------------------------------------
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
    output wire        hdmi_txd2_rst_o,

    //------------------------------------------------------------------
    // User IO
    //------------------------------------------------------------------
    input  wire        key_up,
    input  wire        key_dn,
    output wire        led_lock,         // PLL locked
    output wire        led_stat          // camera line longer than the buffer
);

    //--------------------------------------------------------------------------
    // Latency of the algorithm branch.  Set this to whatever A-group reports.
    //--------------------------------------------------------------------------
    localparam ALG_LATENCY = 12;
    localparam X_BITS      = 11;
    localparam Y_BITS      = 11;

    //--------------------------------------------------------------------------
    // Reset
    //--------------------------------------------------------------------------
    assign sys_pll_rstn_o = 1'b1;

    reg rst_n_pix;
    always @(posedge clk_pixel or negedge sys_pll_lock) begin
        if (!sys_pll_lock) rst_n_pix <= 1'b0;
        else               rst_n_pix <= 1'b1;
    end

    wire rst_n_sys = sys_pll_lock;

    assign led_lock = sys_pll_lock;

    //--------------------------------------------------------------------------
    // I2C : SC2210 register LUT + master  (265 entries -> 9-bit index)
    //--------------------------------------------------------------------------
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
        .I2C_FREQ(400_000),
        .IDX_W   (9)
    ) u_i2c (
        .clk             (clk_sys),
        .rst_n           (rst_n_sys),
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
    assign csi_scl_oe = 1'b1;          // SCL is always driven by the master

    //--------------------------------------------------------------------------
    // csi_rx soft IP (AXI tied off)
    //--------------------------------------------------------------------------
    wire        rxd0_fifo_rd, rxd1_fifo_rd, rxd2_fifo_rd, rxd3_fifo_rd;
    wire        rxd0_fifo_empty = 1'b0;
    wire        rxd1_fifo_empty = 1'b0;
    wire        rxd2_fifo_empty = 1'b0;
    wire        rxd3_fifo_empty = 1'b0;

    wire        csi_valid;
    wire [63:0] csi_data;
    wire        csi_hsync;
    wire        csi_vsync;
    wire [15:0] csi_word_count;
    wire [5:0]  csi_datatype;
    wire        csi_irq;

    csi_rx u_csi_rx (
        .reset_n         (rst_n_sys),
        .clk             (clk_sys),
        .reset_byte_HS_n (rst_n_sys),
        .clk_byte_HS     (csi_rxc_i),
        .reset_pixel_n   (rst_n_pix),
        .clk_pixel       (clk_pixel),

        .Rx_LP_CLK_P     (csi_rxc_lp_p_i),
        .Rx_LP_CLK_N     (csi_rxc_lp_n_i),
        .Rx_HS_enable_C  (csi_rxc_hs_en_o),
        .LVDS_termen_C   (csi_rxc_hs_term_en_o),

        .Rx_LP_D_P       ({csi_rxd3_lp_n_i, csi_rxd2_lp_n_i,
                           csi_rxd1_lp_n_i, csi_rxd0_lp_n_i}),
        .Rx_LP_D_N       ({csi_rxd3_lp_p_i, csi_rxd2_lp_p_i,
                           csi_rxd1_lp_p_i, csi_rxd0_lp_p_i}),
        .Rx_HS_D_0       (csi_rxd0_hs_i ^ 8'hff),
        .Rx_HS_D_1       (csi_rxd1_hs_i ^ 8'hff),
        .Rx_HS_D_2       (csi_rxd2_hs_i ^ 8'hff),
        .Rx_HS_D_3       (csi_rxd3_hs_i ^ 8'hff),
        .Rx_HS_D_4       (8'h00),
        .Rx_HS_D_5       (8'h00),
        .Rx_HS_D_6       (8'h00),
        .Rx_HS_D_7       (8'h00),
        .Rx_HS_enable_D  ({csi_rxd3_hs_en_o, csi_rxd2_hs_en_o,
                           csi_rxd1_hs_en_o, csi_rxd0_hs_en_o}),
        .LVDS_termen_D   ({csi_rxd3_hs_term_en_o, csi_rxd2_hs_term_en_o,
                           csi_rxd1_hs_term_en_o, csi_rxd0_hs_term_en_o}),
        .fifo_rd_enable  ({rxd3_fifo_rd, rxd2_fifo_rd,
                           rxd1_fifo_rd, rxd0_fifo_rd}),
        .fifo_rd_empty   ({rxd3_fifo_empty, rxd2_fifo_empty,
                           rxd1_fifo_empty, rxd0_fifo_empty}),
        .DLY_enable_D    (),
        .DLY_inc_D       (),
        .u_dly_enable_D  (4'b0000),
        .u_dly_inc_D     (4'b0000),

        .axi_clk         (clk_sys),
        .axi_reset_n     (rst_n_sys),
        .axi_awaddr      (6'b0),
        .axi_awvalid     (1'b0),
        .axi_awready     (),
        .axi_wdata       (32'b0),
        .axi_wvalid      (1'b0),
        .axi_wready      (),
        .axi_bvalid      (),
        .axi_bready      (1'b0),
        .axi_araddr      (6'b0),
        .axi_arvalid     (1'b0),
        .axi_arready     (),
        .axi_rdata       (),
        .axi_rvalid      (),
        .axi_rready      (1'b1),

        .vsync_vc0       (csi_vsync),
        .vsync_vc1       (), .vsync_vc2(), .vsync_vc3(),
        .vsync_vc4       (), .vsync_vc5(), .vsync_vc6(), .vsync_vc7(),
        .vsync_vc8       (), .vsync_vc9(), .vsync_vc10(), .vsync_vc11(),
        .vsync_vc12      (), .vsync_vc13(), .vsync_vc14(), .vsync_vc15(),
        .hsync_vc0       (csi_hsync),
        .hsync_vc1       (), .hsync_vc2(), .hsync_vc3(),
        .hsync_vc4       (), .hsync_vc5(), .hsync_vc6(), .hsync_vc7(),
        .hsync_vc8       (), .hsync_vc9(), .hsync_vc10(), .hsync_vc11(),
        .hsync_vc12      (), .hsync_vc13(), .hsync_vc14(), .hsync_vc15(),
        .vc              (),
        .vcx             (),
        .word_count      (csi_word_count),
        .shortpkt_data_field(),
        .datatype        (csi_datatype),
        .pixel_per_clk   (),
        .pixel_data      (csi_data),
        .pixel_data_valid(csi_valid),
        .irq             (csi_irq)
    );

    assign csi_rxd0_rst_o = ~rst_n_sys;
    assign csi_rxd1_rst_o = ~rst_n_sys;
    assign csi_rxd2_rst_o = ~rst_n_sys;
    assign csi_rxd3_rst_o = ~rst_n_sys;

    //--------------------------------------------------------------------------
    // CSI packed stream -> frozen 640x480 pixel stream
    //--------------------------------------------------------------------------
    wire [7:0]  pix_data;
    wire        pix_valid, pix_de, pix_hsync, pix_vsync;
    wire [10:0] pix_x, pix_y;
    wire        line_late, capture_ovf;

    video_source #(
        .H_ACTIVE(640), .H_FRONT(16), .H_SYNC(96), .H_BACK(48),
        .V_ACTIVE(480), .V_FRONT(10), .V_SYNC(2),  .V_BACK(33),
        .H_OFFSET(640)
    ) u_source (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .in_valid(csi_valid), .in_data(csi_data),
        .in_line_act(csi_hsync), .in_frame_act(csi_vsync),
        .pix_data(pix_data), .pix_valid(pix_valid), .pix_de(pix_de),
        .pix_hsync(pix_hsync), .pix_vsync(pix_vsync),
        .pix_x(pix_x), .pix_y(pix_y),
        .line_late(line_late), .capture_ovf(capture_ovf)
    );

    //--------------------------------------------------------------------------
    // Camera-alive detector : if the CSI stream stops, fall back to color bars.
    //--------------------------------------------------------------------------
    localparam [20:0] CAM_ALIVE_TIMEOUT = 21'd1_000_000;  // ~40 ms @25.2 MHz

    reg [20:0] cam_alive_cnt;
    reg        cam_alive;

    always @(posedge clk_pixel or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            cam_alive_cnt <= 21'd0;
            cam_alive     <= 1'b0;
        end else if (csi_valid) begin
            cam_alive_cnt <= 21'd0;
            cam_alive     <= 1'b1;
        end else if (cam_alive_cnt != CAM_ALIVE_TIMEOUT) begin
            cam_alive_cnt <= cam_alive_cnt + 1'b1;
        end else begin
            cam_alive     <= 1'b0;
        end
    end

    assign led_stat = (~cam_alive) | capture_ovf;

    //--------------------------------------------------------------------------
    // Keys -> threshold (debounced in the pixel domain)
    //--------------------------------------------------------------------------
    localparam CNT_20MS_25M2 = 504_000;   // 20 ms at 25.2 MHz

    wire key_up_p, key_dn_p;

    key_debounce #(.CNT_W(20), .CNT_MAX(CNT_20MS_25M2), .PRESS_LOW(1'b1)) u_db_up (
        .clk(clk_pixel), .rst_n(rst_n_pix), .key_in(key_up),
        .key_out(), .press(key_up_p), .released()
    );

    key_debounce #(.CNT_W(20), .CNT_MAX(CNT_20MS_25M2), .PRESS_LOW(1'b1)) u_db_dn (
        .clk(clk_pixel), .rst_n(rst_n_pix), .key_in(key_dn),
        .key_out(), .press(key_dn_p), .released()
    );

    wire [7:0] threshold;
    threshold_reg #(.W(8), .INIT(8'd64), .STEP(8'd4)) u_thr (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .key_up(key_up_p), .key_down(key_dn_p),
        .threshold(threshold)
    );

    //--------------------------------------------------------------------------
    // Algorithm branch (placeholder today, A-group's alg_top later)
    //--------------------------------------------------------------------------
    wire [7:0]  alg_data;
    wire        alg_valid, alg_de, alg_hs, alg_vs;
    wire [10:0] alg_x, alg_y;

    alg_top #(
        .WIDTH(640), .LATENCY(ALG_LATENCY), .X_BITS(X_BITS), .Y_BITS(Y_BITS)
    ) u_alg (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .in_data(pix_data), .in_valid(pix_valid), .in_de(pix_de),
        .in_hs(pix_hsync), .in_vs(pix_vsync),
        .in_x(pix_x), .in_y(pix_y),
        .threshold(threshold),
        .out_data(alg_data), .out_valid(alg_valid), .out_de(alg_de),
        .out_hs(alg_hs), .out_vs(alg_vs),
        .out_x(alg_x), .out_y(alg_y)
    );

    // Un-processed branch, delayed by exactly the same latency
    wire [7:0]  raw_data;
    wire        raw_valid, raw_de, raw_hs, raw_vs;
    wire [10:0] raw_x, raw_y;

    video_delay #(
        .STAGES(ALG_LATENCY), .X_BITS(X_BITS), .Y_BITS(Y_BITS)
    ) u_raw_delay (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .in_data(pix_data), .in_valid(pix_valid), .in_de(pix_de),
        .in_hs(pix_hsync), .in_vs(pix_vsync),
        .in_x(pix_x), .in_y(pix_y),
        .out_data(raw_data), .out_valid(raw_valid), .out_de(raw_de),
        .out_hs(raw_hs), .out_vs(raw_vs),
        .out_x(raw_x), .out_y(raw_y)
    );

    //--------------------------------------------------------------------------
    // Split-screen MUX  (left = raw, right = processed)
    //--------------------------------------------------------------------------
    wire [7:0] disp_data;
    wire       disp_valid;
    wire [7:0] disp_r = disp_data;
    wire [7:0] disp_g = disp_data;
    wire [7:0] disp_b = disp_data;

    split_mux #(
        .H_ACTIVE(640), .X_BITS(X_BITS), .SPLIT_X(320), .SPLIT_W(2)
    ) u_mux (
        .a_data(raw_data), .a_valid(raw_valid),
        .b_data(alg_data), .b_valid(alg_valid),
        .de(raw_de), .x(raw_x),
        .out_data(disp_data), .out_valid(disp_valid)
    );

    //--------------------------------------------------------------------------
    // Display source fallback : camera image, or color bars when camera absent
    //--------------------------------------------------------------------------
    wire [7:0] bar_r, bar_g, bar_b;

    pattern_gen #(
        .ACTIVE_W(640), .ACTIVE_H(480), .X_BITS(X_BITS), .Y_BITS(Y_BITS)
    ) u_bar (
        .x(raw_x), .y(raw_y), .de(raw_de),
        .r(bar_r), .g(bar_g), .b(bar_b)
    );

    wire [7:0] out_r = cam_alive ? disp_r : bar_r;
    wire [7:0] out_g = cam_alive ? disp_g : bar_g;
    wire [7:0] out_b = cam_alive ? disp_b : bar_b;

    //--------------------------------------------------------------------------
    // HDMI TMDS output
    //--------------------------------------------------------------------------
    rgb2dvi #(
        .ENABLE_OSERDES(0)
    ) u_rgb2dvi (
        .PixelClk    (clk_pixel),
        .aRst        (1'b0),
        .aRst_n      (1'b1),
        .bitflip_i   (4'b0000),
        .oe_i        (1'b1),
        .vid_pVSync  (raw_vs),
        .vid_pHSync  (raw_hs),
        .vid_pVDE    (raw_de),
        .vid_pData   ({out_r, out_g, out_b}),
        .SerialClk   (1'b0),        // unused (OSERDES disabled)
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

    assign hdmi_txc_rst_o  = ~rst_n_pix;
    assign hdmi_txd0_rst_o = ~rst_n_pix;
    assign hdmi_txd1_rst_o = ~rst_n_pix;
    assign hdmi_txd2_rst_o = ~rst_n_pix;

endmodule
