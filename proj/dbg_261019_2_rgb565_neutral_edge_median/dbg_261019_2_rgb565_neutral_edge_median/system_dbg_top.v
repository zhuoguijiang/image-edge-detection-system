//==============================================================================
// system_dbg_top : camera-debug build of the system integration
//                  version dbg_20260927_01  (2026-09-27)
//
//   Derivative of rtl/top/system_top.v (kept for reference / rollback).
//   The datapath is identical, the differences are:
//
//     1. all 8 board LEDs (led0..led7) are used as a *fault bank* that says
//        where the camera data path stopped (see DBG LED BANK below);
//     2. the I2C master reports a sticky NACK flag (i2c_any_nack);
//     3. the MIPI LP/HS polarity is selectable with two localparams
//        (see MIPI POLARITY SWITCHES below);
//     4. NEW in this version: the csi_rx soft IP gets its own 50 MHz clock
//        (clk_csi) instead of clk_sys = 24 MHz - see CLOCKING below.
//
//   Everything downstream of `csi_valid` is unchanged, so a picture that
//   works here works in proj/system as well.
//
//------------------------------------------------------------------------------
// ALIGNED WITH THE BOARD VENDOR'S OWN SC2210 DEMO  (2026-09-27)
//
//   Reference: VF-Ti60F225_HDK_V2.1_20251009\
//              07-FPGA_HDL_Image-2023.2\04-1_Ti60_SC2210_HDMI_1080P60
//   (same board + same sensor; ships a built bitstream, so it is known good)
//
//     * MIPI data lanes stay on the vendor's pins - peri.xml:
//         csi_rxc  = GPIOR_PN_17
//         csi_rxd0 = GPIOR_PN_18     (NOT PN_15: the xlsx "MIPI_RX0" is a
//         csi_rxd1 = GPIOR_PN_19      board net name, not the D-PHY
//         csi_rxd2 = GPIOR_PN_15      block_def order used by the hard block)
//         csi_rxd3 = GPIOR_PN_16
//       static delay 17, is_fifo = false  -> same as the vendor demo.
//     * polarity INV_HS=1 / SWAP_LP=1 = vendor's CSI_RXD_INV = 4'b1111
//       ("data can be inverted with swapped LP data and flipped HS data").
//     * the camera initialisation table is the vendor's own
//       I2C_SC2210_19201080_4Lanes_Config.v, 266 writes, identical.
//
//   The vendor's demo does NOT use the Efinix csi2_rx IP - it uses its own
//   MIPIRx4LaneFre block - so the IP has to be given a sane environment:
//   both available references run the RX core clock at 96..100 MHz while
//   this project used to run it at 24 MHz.
//------------------------------------------------------------------------------
// CLOCKING  (peri.xml sys_pll, VCO = 3000 MHz)
//
//     clk_sys       24.0 MHz   I2C master + housekeeping
//     clk_pixel     25.0 MHz   video/display pipeline
//     clk_pixel_10x 250  MHz   HDMI serializer
//     clk_csi       50.0 MHz   csi_rx soft IP core clock  <-- new here
//
//   Reason: ip/csi_rx was generated with CLOCK_FREQ_MHZ = 50 (documented
//   range 40..100 MHz) but was fed clk_sys = 24 MHz, i.e. below the minimum.
//   The IP converts its LP timing constants with this number, so feeding a
//   clock that matches the parameter is the parameter-consistent setting.
//   If a future experiment shows the IP wants the references' 96..100 MHz,
//   only the clk_csi out_divider in the peri.xml has to change (60 -> 30).
//
//   Domain split: csi_rx uses clk_csi for `clk`/`axi_clk`, csi_rxc_i (the
//   D-PHY byte clock, ~31 MHz) for `clk_byte_HS`, and clk_pixel for the pixel
//   side.  Everything downstream is still clk_pixel only.
//------------------------------------------------------------------------------
//
// KEYS
//   key_up : increase the Sobel threshold (as before).
//   key_dn : short press cycles the display mode
//              0 raw -> 1 grayscale -> 2 edge -> 3 split
//              -> 4 red-edge overlay -> 0 ...
//            hold 1 s toggles the LED fault/timing panel.
//   Power-on mode is 3 (the legacy split view).
//
// NOTE ON THE CLOCK DOMAINS
//   csi_rx already contains the byte-clock -> pixel-clock dual-clock FIFO, so
//   everything downstream of csi_rx lives in clk_pixel.  The only remaining
//   asynchronous inputs are the two push buttons, which are debounced
//   directly in clk_pixel.
//==============================================================================
module system_dbg_top (
    input  wire        clk_24m,          // 24 MHz crystal (PLL reference)
    output wire        sys_pll_rstn_o,   // PLL reset, active low -> drive high
    input  wire        sys_pll_lock,     // PLL locked
    input  wire        clk_sys,          // PLL out : 24 MHz system clock
    input  wire        clk_pixel,        // PLL out : 25.0 MHz pixel clock
    input  wire        clk_pixel_10x,    // PLL out : 250 MHz serializer clock
    input  wire        clk_csi,          // PLL out : 50 MHz csi_rx core clock

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
    // User IO : 2 keys + the 8 board LEDs
    //------------------------------------------------------------------
    input  wire        key_up,
    input  wire        key_dn,
    output wire [7:0]  led            // LED0..LED7, ACTIVE LOW (0 = lit)
);

    //--------------------------------------------------------------------------
    // Latency of the algorithm branch.
    //--------------------------------------------------------------------------
    localparam ALG_LATENCY = 12;
    localparam X_BITS      = 11;
    localparam Y_BITS      = 11;

    //--------------------------------------------------------------------------
    // Full-resolution edge algorithm selector.
    //   0 = original Sobel + NMS + local hysteresis (baseline, LATENCY 14)
    //   1 = Canny : Gaussian -> Sobel -> NMS -> hysteresis -> linking (LATENCY 13)
    // Rebuild with EDGE_ALGO=0 to fall back to the baseline bitstream for an
    // on-the-bench A/B comparison.
    //--------------------------------------------------------------------------
    localparam EDGE_ALGO        = 1;
    localparam EDGE_PREMEDIAN   = 1;
    localparam EDGE_GAUSS3      = 0;
    localparam EDGE_SCHARR      = 0;
    localparam EDGE_INTERP_NMS  = 0;
    localparam EDGE_ALIGN_X     = 3;
    localparam EDGE_ALIGN_Y     = 4;
    localparam ALG_LATENCY_FULL = (EDGE_ALGO == 1)
                                ? (13 + (EDGE_PREMEDIAN ? 4 : 0) + (EDGE_GAUSS3 ? 2 : 0))
                                : 14;

    //--------------------------------------------------------------------------
    // MIPI POLARITY SWITCHES  (Debug.md 4.2 - "suspect #1")
    //
    //   The vendor example and rtl/camera/camera_top.v pass LP_P->LP_P,
    //   LP_N->LP_N and the HS bytes un-inverted.  The old system_top.v passed
    //   them swapped / inverted *without a comment*.  Both variants are
    //   available here; only one can be right for this board.
    //
    //   Sweep order (change one letter, rebuild, watch LED3 + LED6):
    //     INV_HS=1, SWAP_LP=1   <- default, identical to the old system_top.v
    //     INV_HS=0, SWAP_LP=0   <- identical to the vendor example
    //     INV_HS=1, SWAP_LP=0
    //     INV_HS=0, SWAP_LP=1
    //--------------------------------------------------------------------------
    localparam INV_HS  = 1'b1;   // 1 = invert the received HS byte
    localparam SWAP_LP = 1'b1;   // 1 = swap LP P/N

    wire [7:0] hs0 = INV_HS ? (csi_rxd0_hs_i ^ 8'hff) : csi_rxd0_hs_i;
    wire [7:0] hs1 = INV_HS ? (csi_rxd1_hs_i ^ 8'hff) : csi_rxd1_hs_i;
    wire [7:0] hs2 = INV_HS ? (csi_rxd2_hs_i ^ 8'hff) : csi_rxd2_hs_i;
    wire [7:0] hs3 = INV_HS ? (csi_rxd3_hs_i ^ 8'hff) : csi_rxd3_hs_i;

    wire [3:0] lp_p = SWAP_LP ? {csi_rxd3_lp_n_i, csi_rxd2_lp_n_i,
                                 csi_rxd1_lp_n_i, csi_rxd0_lp_n_i}
                              : {csi_rxd3_lp_p_i, csi_rxd2_lp_p_i,
                                 csi_rxd1_lp_p_i, csi_rxd0_lp_p_i};
    wire [3:0] lp_n = SWAP_LP ? {csi_rxd3_lp_p_i, csi_rxd2_lp_p_i,
                                 csi_rxd1_lp_p_i, csi_rxd0_lp_p_i}
                              : {csi_rxd3_lp_n_i, csi_rxd2_lp_n_i,
                                 csi_rxd1_lp_n_i, csi_rxd0_lp_n_i};

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

    //--------------------------------------------------------------------------
    // I2C : SC2210 register LUT + master  (265 entries -> 9-bit index)
    //--------------------------------------------------------------------------
    wire [8:0]  i2c_index;
    wire [23:0] i2c_lut;
    wire [8:0]  i2c_size;
    wire        i2c_done;
    wire        i2c_nack;

    // dbg_20260928_01: local 640x480 (VGA60) table - the sensor now outputs the
    // 640x480 centre crop directly at 59.52 Hz / 31.25 kHz lines, so the display
    // can show it 1:1 (see the file header for the register derivation).
    I2C_SC2210_640x480_4Lanes_Config u_sc2210_cfg (
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
        .i2c_any_nack    (i2c_nack),
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
        .clk             (clk_csi),        // 50 MHz (was clk_sys = 24 MHz)
        .reset_byte_HS_n (rst_n_sys),
        .clk_byte_HS     (csi_rxc_i),
        .reset_pixel_n   (rst_n_pix),
        .clk_pixel       (clk_pixel),

        .Rx_LP_CLK_P     (csi_rxc_lp_p_i),
        .Rx_LP_CLK_N     (csi_rxc_lp_n_i),
        .Rx_HS_enable_C  (csi_rxc_hs_en_o),
        .LVDS_termen_C   (csi_rxc_hs_term_en_o),

        .Rx_LP_D_P       (lp_p),
        .Rx_LP_D_N       (lp_n),
        .Rx_HS_D_0       (hs0),
        .Rx_HS_D_1       (hs1),
        .Rx_HS_D_2       (hs2),
        .Rx_HS_D_3       (hs3),
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

        .axi_clk         (clk_csi),
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
    wire [7:0]  pix_r, pix_g, pix_b;
    wire        pix_valid, pix_de, pix_hsync, pix_vsync;
    wire [10:0] pix_x, pix_y, pix_hcnt, pix_y_act;
    wire        line_late, capture_ovf;

    //--------------------------------------------------------------------------
    // dbg_20261012_03 : FRAME BUFFER instead of the 1-line ping-pong buffer.
    //   A 320x240x8b frame (76.8 kB in block RAM) is filled from the camera and
    //   read out by the display's own free-running 640x480@59.5 Hz timing, so
    //   the picture position no longer depends on the camera's VTS/frame rate
    //   at all - that is what finally removes the rolling (the sensor turned
    //   out to be stuck at ~1112-line frames, i.e. ~28 fps, and refuses to be
    //   programmed to 60 fps).
    //   Same output interface as video_source, so everything downstream is
    //   unchanged.  line_late / capture_ovf are tied low inside the module.
    //--------------------------------------------------------------------------
    wire        store_written;      // 1 = the frame buffer has been filled at least once

    // The colour preview store is instantiated after camera_line_unpack (it
    // needs the full-resolution pixel stream for debayering).

    //--------------------------------------------------------------------------
    // Full-resolution camera pixel stream (64-bit CSI beats -> 1 pixel/clk)
    //--------------------------------------------------------------------------
    wire [7:0]  cam_pix_data;
    wire        cam_pix_valid, cam_pix_de, cam_pix_hs, cam_pix_vs;
    wire [10:0] cam_pix_x, cam_pix_y;

    camera_line_unpack u_cam_unpack (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .in_valid(csi_valid), .in_hs(csi_hsync), .in_vs(csi_vsync),
        .in_data(csi_data),
        .out_data(cam_pix_data), .out_valid(cam_pix_valid),
        .out_de(cam_pix_de), .out_hs(cam_pix_hs), .out_vs(cam_pix_vs),
        .out_x(cam_pix_x), .out_y(cam_pix_y)
    );

    //--------------------------------------------------------------------------
    // Colour preview: full-res RAW -> 3x3 window -> debayer -> RGB332 store.
    // The store has the same 320x240x8b footprint as the old RAW preview, so
    // mode 0 becomes a colour image without spending extra memory blocks.
    //--------------------------------------------------------------------------
    wire [7:0] cb00, cb01, cb02, cb10, cb11, cb12, cb20, cb21, cb22;
    wire       cb_valid;
    wire [15:0] cb_x, cb_y;

    line_buffer_3x3 #(.WIDTH(640), .DW(8)) u_cam_lb (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .din(cam_pix_data), .din_valid(cam_pix_valid), .din_vsync(~cam_pix_vs),
        .w00(cb00), .w01(cb01), .w02(cb02),
        .w10(cb10), .w11(cb11), .w12(cb12),
        .w20(cb20), .w21(cb21), .w22(cb22),
        .dout_valid(cb_valid), .dout_x(cb_x), .dout_y(cb_y)
    );

    wire [7:0] cam_r, cam_g, cam_b;
    wire       cam_rgb_valid;
    debayer u_cam_db (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .w00(cb00), .w01(cb01), .w02(cb02),
        .w10(cb10), .w11(cb11), .w12(cb12),
        .w20(cb20), .w21(cb21), .w22(cb22),
        .in_valid(cb_valid), .in_x(cb_x), .in_y(cb_y),
        .r(cam_r), .g(cam_g), .b(cam_b), .out_valid(cam_rgb_valid)
    );

    // line / frame activity aligned with the debayer output (lb 1 + debayer 1)
    reg [1:0] cam_hs_d, cam_vs_d;
    always @(posedge clk_pixel or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            cam_hs_d <= 2'd0;
            cam_vs_d <= 2'd0;
        end else begin
            cam_hs_d <= {cam_hs_d[0], cam_pix_hs};
            cam_vs_d <= {cam_vs_d[0], cam_pix_vs};
        end
    end

    // White balance for the colour preview.  Tuned from on-board feedback:
    // no WB -> green, R/B 1.5x -> slightly red.  New balance: R x1.25 and
    // B x1.625 (G unchanged), which also reduces R-channel highlight clipping.
    // The two gains are the tuning knobs: change the shifts here if needed.
    wire [8:0] cam_r_wb9 = {1'b0, cam_r} + {2'b00, cam_r[7:2]};                    // 1.25x
    wire [8:0] cam_b_wb9 = {1'b0, cam_b} + {2'b00, cam_b[7:1]} + {4'b0000, cam_b[7:3]}; // 1.625x
    wire [7:0] cam_r_wb  = cam_r_wb9[8] ? 8'hFF : cam_r_wb9[7:0];
    wire [7:0] cam_b_wb  = cam_b_wb9[8] ? 8'hFF : cam_b_wb9[7:0];

    rgb565_preview_store #(
        .H_ACTIVE(640), .H_FRONT(16), .H_SYNC(96), .H_BACK(48),
        .V_ACTIVE(480), .V_FRONT(10), .V_SYNC(2), .V_BACK(33),
        .BILINEAR_H(0), .SAT_EN(0)
    ) u_color_store (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .in_r(cam_r_wb), .in_g(cam_g), .in_b(cam_b_wb), .in_valid(cam_rgb_valid),
        .in_line_act(cam_hs_d[1]), .in_frame_act(cam_vs_d[1]),
        .pix_r(pix_r), .pix_g(pix_g), .pix_b(pix_b),
        .pix_valid(pix_valid), .pix_de(pix_de),
        .pix_hsync(pix_hsync), .pix_vsync(pix_vsync),
        .pix_x(pix_x), .pix_hcnt(pix_hcnt), .pix_y(pix_y),
        .pix_y_act(pix_y_act),
        .line_late(line_late), .capture_ovf(capture_ovf),
        .buf_written(store_written)
    );

    //==========================================================================
    // DEBUG LED BANK  (camera data validity)
    //
    //   All 8 board LEDs are driven by rtl/dbg/dbg_led_bank.v, which owns the
    //   camera-alive detector, the sticky "have I ever seen it" flags and the
    //   LED polarity.  Read the table at the top of that file - the one line
    //   version is:
    //
    //         所有 LED 全灭  =  相机数据正在流动（数据通路是通的）
    //         哪一盏亮      =  卡在哪一级（LED0..LED7 = PLL/I2C/CSI/…）
    //
    //   cam_alive also selects the display source (camera image vs color bars).
    //
    //   NOTE: the fault flags are split by clock domain.  The clk_pixel logic
    //   analyzer may only sample dbg_fault_pix / dbg_sticky; probing the I2C /
    //   PLL flags from it costs a clk_sys -> clk_pixel setup path (~1.1 ns,
    //   measured) - those live in dbg_fault_ctrl and are probed by a second LA
    //   core clocked by clk_sys (see dbg_core.selection.json).
    //==========================================================================
    wire        cam_alive;
    wire [4:0]  dbg_fault_pix;
    wire [2:0]  dbg_fault_ctrl;
    wire [4:0]  dbg_sticky;
    wire [7:0]  led_ladder;     // fault-ladder pattern from dbg_led_bank

    dbg_led_bank #(
        .CAM_ALIVE_TIMEOUT(21'd1_000_000)          // ~40 ms @25.0 MHz
    ) u_dbg_leds (
        .clk           (clk_pixel),
        .rst_n         (rst_n_pix),
        .csi_valid     (csi_valid),
        .csi_hsync     (csi_hsync),
        .csi_vsync     (csi_vsync),
        .csi_datatype  (csi_datatype),
        .pix_valid     (pix_valid),
        .capture_ovf   (capture_ovf),
        .sys_pll_lock  (sys_pll_lock),
        .i2c_done      (i2c_done),
        .i2c_nack      (i2c_nack),
        .cam_alive     (cam_alive),
        .led           (led_ladder),        // dbg_20261009_01: panel mux below
        .dbg_fault_pix (dbg_fault_pix),
        .dbg_fault_ctrl(dbg_fault_ctrl),
        .dbg_sticky    (dbg_sticky)
    );

    //==========================================================================
    // DIAGNOSTIC TIMING COUNTERS  (new in dbg_20260929_01)
    //
    //   Three numbers that settle whether the sensor accepted the geometry
    //   (HTS/VTS) writes in I2C_SC2210_640x480_4Lanes_Config.v.  Read them with
    //   the Efinity Debugger (they are probes la0_probe13..15), no trigger
    //   needed - just Run Immediate and read the values:
    //
    //     dbg_t_hsync        clk_pixel cycles (40 ns) since the last hsync edge
    //                          ~800  (32.0 us) -> HTS took effect (31.25 kHz)
    //                          ~539  (21.6 us) -> HTS did NOT take effect (66.7 kHz, 1080p value)
    //                          other           -> neither: sensor ignored both writes
    //     dbg_lines_vsync    hsync pulses since the last vsync edge
    //                          525  -> VTS took effect (59.5 Hz frame)
    //                          1112 -> VTS did NOT take effect (1080p value)
    //     dbg_t_vsync        clk_pixel cycles since the last vsync edge
    //                          line_period * lines_vsync (consistency check,
    //                          and it gives the real frame rate directly)
    //
    //   Rule of thumb: for a picture that does not slide we need
    //   dbg_t_hsync == 800 and dbg_lines_vsync == 525.
    //==========================================================================
    reg  [19:0] dbg_t_vsync;      // up to 41.9 ms @25 MHz
    reg  [15:0] dbg_t_hsync;      // up to 2.6 ms
    reg  [12:0] dbg_lines_vsync;  // up to 8191 lines
    reg         csi_vsync_1p, csi_hsync_1p;

    // values latched at the sync edges -> stable, usable for the LED panel
    reg  [15:0] dbg_line_period_lat;   // previous line period  [clk_pixel]
    reg  [12:0] dbg_lines_frame_lat;   // previous frame length [lines]
    reg  [19:0] dbg_frame_period_lat;  // previous frame period [clk_pixel]

    always @(posedge clk_pixel or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            dbg_t_vsync     <= 20'd0;
            dbg_t_hsync     <= 16'd0;
            dbg_lines_vsync <= 13'd0;
            csi_vsync_1p    <= 1'b0;
            csi_hsync_1p    <= 1'b0;
            dbg_line_period_lat  <= 16'd0;
            dbg_lines_frame_lat  <= 13'd0;
            dbg_frame_period_lat <= 20'd0;
        end else begin
            csi_vsync_1p <= csi_vsync;
            csi_hsync_1p <= csi_hsync;

            // vertical sync edge : start a new frame, latch the finished one
            if (csi_vsync & ~csi_vsync_1p) begin
                dbg_frame_period_lat <= (dbg_t_vsync == 20'd0) ? dbg_frame_period_lat
                                                               : dbg_t_vsync;
                dbg_lines_frame_lat  <= (dbg_lines_vsync == 13'd0) ? dbg_lines_frame_lat
                                                                   : dbg_lines_vsync;
                dbg_t_vsync     <= 20'd0;
                dbg_lines_vsync <= 13'd0;
            end else if (dbg_t_vsync != 20'hFFFFF) begin
                dbg_t_vsync     <= dbg_t_vsync + 1'b1;
            end

            // horizontal sync edge : one more line
            if (csi_hsync & ~csi_hsync_1p) begin
                if (dbg_t_hsync != 16'd0) dbg_line_period_lat <= dbg_t_hsync;
                dbg_t_hsync     <= 16'd0;
                dbg_lines_vsync <= (csi_vsync & ~csi_vsync_1p) ? 13'd1
                                                               : (dbg_lines_vsync + 1'b1);
            end else if (dbg_t_hsync != 16'hFFFF) begin
                dbg_t_hsync     <= dbg_t_hsync + 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // vsync sanity flag  (new in dbg_20261012_01)
    //   The first genlock build reacted to EVERY csi_vsync rising edge.  If the
    //   camera's vsync carries extra pulses (or is much faster than a frame),
    //   that restarts the display frame constantly and the monitor loses sync -
    //   which is exactly the "all LEDs dark + black screen" we saw.
    //   Here any two rising edges closer than 2 ms set a sticky flag, and the
    //   flag is refreshed every ~1.34 s, so the LED shows "recently" rather
    //   than "ever".  The genlock itself only accepts edges that are at least
    //   one full frame apart (see vga_timing V_MINCNT).
    //--------------------------------------------------------------------------
    localparam [19:0] VSYNC_MIN_INT = 20'd50000;    // 2 ms @ 25 MHz

    reg        dbg_vsync_bad;        // 1 = two vsync edges were < 2 ms apart
    reg [24:0] dbg_vsync_bad_clr;    // refresh window, ~1.34 s

    always @(posedge clk_pixel or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            dbg_vsync_bad     <= 1'b0;
            dbg_vsync_bad_clr <= 25'd0;
        end else begin
            dbg_vsync_bad_clr <= dbg_vsync_bad_clr + 1'b1;
            if (dbg_vsync_bad_clr == 25'd0) dbg_vsync_bad <= 1'b0;
            if ((csi_vsync & ~csi_vsync_1p) && (dbg_t_vsync < VSYNC_MIN_INT))
                dbg_vsync_bad <= 1'b1;
        end
    end


    //--------------------------------------------------------------------------
    // Keys (debounced in the pixel domain)
    //
    //   key_up : Sobel threshold up (unchanged)
    //   key_dn : short press -> cycle display mode
    //            hold 1 s    -> toggle the LED fault/timing panel
    //--------------------------------------------------------------------------
    localparam CNT_20MS_25M = 500_000;   // 20 ms at 25.0 MHz

    wire key_up_p;
    wire key_dn_level, key_dn_press, key_dn_release;

    key_debounce #(.CNT_W(20), .CNT_MAX(CNT_20MS_25M), .PRESS_LOW(1'b1)) u_db_up (
        .clk(clk_pixel), .rst_n(rst_n_pix), .key_in(key_up),
        .key_out(), .press(key_up_p), .released()
    );

    key_debounce #(.CNT_W(20), .CNT_MAX(CNT_20MS_25M), .PRESS_LOW(1'b1)) u_db_dn (
        .clk(clk_pixel), .rst_n(rst_n_pix), .key_in(key_dn),
        .key_out(key_dn_level), .press(key_dn_press), .released(key_dn_release)
    );

    wire [7:0] threshold;
    // INIT was 64 for the plain Sobel path.  The Canny path smooths the image
    // with a 5x5 Gaussian first, which lowers the gradient magnitudes, so the
    // high threshold starts lower (32); the low threshold is threshold>>1.
    // key_up still raises it in +4 steps (saturating at 255).
    threshold_reg #(.W(8), .INIT(8'd32), .STEP(8'd4)) u_thr (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .key_up(key_up_p), .key_down(1'b0),
        .threshold(threshold)
    );

    // Display mode:
    //   0 = raw camera stream
    //   1 = median-filtered grayscale
    //   2 = binary edge map
    //   3 = legacy split view (raw | edge)
    //   4 = red edge overlay on the original image (PDF high-level challenge)
    // Power-on default is 3 so the first picture matches the previous build.
    reg [2:0] disp_mode;

    // 1 s at 25 MHz.  A short press cycles disp_mode on release; a long hold
    // toggles the LED panel and does NOT also change the display mode.
    localparam [24:0] DN_LONG_CNT = 25'd25_000_000;
    reg [24:0] dn_hold_cnt;
    reg        dn_long_done;
    reg        led_mode;      // 0 = fault ladder, 1 = timing dial

    always @(posedge clk_pixel or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            disp_mode   <= 3'd3;
            dn_hold_cnt <= 25'd0;
            dn_long_done <= 1'b0;
            led_mode    <= 1'b0;
        end else begin
            if (key_dn_press) begin
                dn_hold_cnt  <= 25'd0;
                dn_long_done <= 1'b0;
            end else if (key_dn_level && !dn_long_done) begin
                if (dn_hold_cnt >= DN_LONG_CNT - 1'b1) begin
                    dn_long_done <= 1'b1;
                    led_mode     <= ~led_mode;
                end else begin
                    dn_hold_cnt <= dn_hold_cnt + 1'b1;
                end
            end

            if (key_dn_release) begin
                // 6 modes (0..5), wrap 5 -> 0
                if (!dn_long_done) disp_mode <= (disp_mode == 3'd4)
                                              ? 3'd0 : disp_mode + 3'd1;
                dn_hold_cnt  <= 25'd0;
                dn_long_done <= 1'b0;
            end
        end
    end

    //==========================================================================
    // LED PANEL with isolation-build measurement probe
    //
    //   Two instruments share the 8 LEDs; hold key_dn for 1 s to switch:
    //
    //     mode 0 (power-on default) : the camera fault ladder, exactly as
    //                                 before (all LEDs dark = data flowing)
    //     mode 1                    : the CAMERA TIMING DIAL - the numbers we
    //                                 have to watch to make the picture stop
    //                                 rolling.  A lit LED means "yes" for its
    //                                 row; the target combinations are marked.
    //
    //   DIAL (mode 1)                          lit means
    //   LED0  line period < 760 clk  ( <33 kHz)  line rate too FAST
    //   LED1  line period 760..840   (~31.25 kHz) LINE RATE OK  <-- target
    //   LED2  line period > 840 clk  ( <30 kHz)  line rate too SLOW
    //   LED3  at least one complete frame period has been captured
    //   LED4  no complete frame period captured yet
    //   LED5  MEASUREMENT PROBE: active-low 4-clock pulse on each vsync
    //         rising edge. At 25 MHz the low pulse is 160 ns. Probe LED5 /
    //         GPIO P13; this output is independent of the LED panel mode.
    //   LED6  vsync edges < 2 ms apart (sticky)  csi_vsync carries extra pulses
    //   LED7  cam_alive & store_written          camera flowing AND the frame
    //                                            buffer has been filled at least
    //                                            once (dbg_20261012_03: capture_ovf
    //                                            no longer exists, so this row now
    //                                            watches the frame store instead)
    //
    //   The old "fps_ok 370k..470k" and "vts_ok 483..567 lines" claims were
    //   removed because they contradicted the recorded ~28 fps / 1112-line
    //   camera behavior. They were debug hypotheses, not measurement evidence.
    //   LED5 now provides a calibrated pulse suitable for external counting.
    //==========================================================================
    wire line_fast = (dbg_line_period_lat != 16'd0) && (dbg_line_period_lat < 16'd760);
    wire line_ok   = (dbg_line_period_lat >= 16'd760) && (dbg_line_period_lat <= 16'd840);
    wire line_slow = (dbg_line_period_lat >  16'd840);

    wire        measure_frame_tick;
    wire        measure_lines_pulse;
    wire [19:0] measure_frame_period;
    wire [12:0] measure_frame_lines;
    wire        measure_sample_valid;

    measurement_timing #(.PULSE_CYCLES(4)) u_measure (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .csi_vsync(csi_vsync), .csi_hsync(csi_hsync),
        .frame_tick_o(measure_frame_tick),
        .lines_pulse_o(measure_lines_pulse),
        .frame_period_o(measure_frame_period),
        .lines_frame_o(measure_frame_lines),
        .sample_valid_o(measure_sample_valid)
    );

    wire [7:0] led_dial = {                   // 1 = this LED is lit
        (cam_alive & store_written),          // LED7 : data flowing + buffer filled
        dbg_vsync_bad,                        // LED6 : csi_vsync has extra pulses
        measure_frame_tick,                   // LED5 : measurement pulse
        ~measure_sample_valid,                // LED4 : no complete period yet
        measure_sample_valid,                 // LED3 : complete period captured
        line_slow,                            // LED2 : line rate too slow
        line_ok,                              // LED1 : line rate ~31.25 kHz ok
        line_fast                             // LED0 : line rate too fast
    };

    // LEDs are active-low. LED5 gives a 160 ns frame-start pulse. LED3 gives a
    // low pulse whose width equals lines/frame * 40 ns. Both override the
    // normal panel for the duration of the pulse, without entering video logic.
    wire [7:0] led_panel = led_mode ? ~led_dial : led_ladder;
    wire [7:0] measure_override =
        (measure_frame_tick ? 8'b0010_0000 : 8'b0000_0000) |
        (measure_lines_pulse ? 8'b0000_1000 : 8'b0000_0000);
    assign led = led_panel & ~measure_override;

    //--------------------------------------------------------------------------
    // Colour preview delay: 16 cycles = 12 (edge alignment) + 4 (median)
    //--------------------------------------------------------------------------
    wire [7:0]  raw_r, raw_g, raw_b;
    wire        raw_valid, raw_de, raw_hs, raw_vs;
    wire [10:0] raw_x, raw_y;

    rgb_video_delay #(
        .STAGES(16), .X_BITS(X_BITS), .Y_BITS(Y_BITS)
    ) u_rgb_delay (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .in_r(pix_r), .in_g(pix_g), .in_b(pix_b),
        .in_valid(pix_valid), .in_de(pix_de),
        .in_hs(pix_hsync), .in_vs(pix_vsync),
        .in_x(pix_x), .in_y(pix_y),
        .out_r(raw_r), .out_g(raw_g), .out_b(raw_b),
        .out_valid(raw_valid), .out_de(raw_de),
        .out_hs(raw_hs), .out_vs(raw_vs),
        .out_x(raw_x), .out_y(raw_y)
    );

    //--------------------------------------------------------------------------
    // Median-filtered grayscale preview (mode 1) from the colour luma.
    //   luma at pix timing -> 3x3 median (4 cycles) -> 12-cycle delay = 16,
    //   aligned with raw_r/g/b and edge_data.
    //--------------------------------------------------------------------------
    // 16-bit products: 8-bit constants here would truncate each product to
    // 8 bits and then the >>8 would make the whole luma zero (black mode 1).
    wire [15:0] pix_luma_sum = 16'd77 * pix_r + 16'd150 * pix_g + 16'd29 * pix_b;
    wire [7:0]  pix_luma     = pix_luma_sum[15:8];
    // Debug-core compatibility: la0 still samples the old "pix_data" probe.
    // Keep an 8-bit alias (the colour luma) at the top level.
    wire [7:0] pix_data = pix_luma;
    wire [7:0] gm00, gm01, gm02, gm10, gm11, gm12, gm20, gm21, gm22;
    wire       gm_wvalid;
    wire [15:0] gm_wx, gm_wy;

    line_buffer_3x3 #(.WIDTH(640), .DW(8)) u_gray_lb (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .din(pix_luma), .din_valid(pix_de), .din_vsync(~pix_vsync),
        .w00(gm00), .w01(gm01), .w02(gm02),
        .w10(gm10), .w11(gm11), .w12(gm12),
        .w20(gm20), .w21(gm21), .w22(gm22),
        .dout_valid(gm_wvalid), .dout_x(gm_wx), .dout_y(gm_wy)
    );

    wire [7:0] gray_med, gray_adapt;
    wire       gray_valid;
    median3x3 u_gray_med (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .w00(gm00), .w01(gm01), .w02(gm02),
        .w10(gm10), .w11(gm11), .w12(gm12),
        .w20(gm20), .w21(gm21), .w22(gm22),
        .in_valid(gm_wvalid), .med(gray_med), .med_adaptive(gray_adapt),
        .out_valid(gray_valid)
    );

    wire [7:0]  gray_d;
    wire        gray_d_valid, gray_d_de, gray_d_hs, gray_d_vs;
    wire [10:0] gray_d_x, gray_d_y;
    video_delay #(
        .STAGES(12), .X_BITS(X_BITS), .Y_BITS(Y_BITS)
    ) u_gray_dly (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .in_data(gray_med), .in_valid(gray_valid), .in_de(gray_valid),
        .in_hs(1'b1), .in_vs(1'b0),
        .in_x({X_BITS{1'b0}}), .in_y({Y_BITS{1'b0}}),
        .out_data(gray_d), .out_valid(gray_d_valid), .out_de(gray_d_de),
        .out_hs(gray_d_hs), .out_vs(gray_d_vs),
        .out_x(gray_d_x), .out_y(gray_d_y)
    );

    //--------------------------------------------------------------------------
    // Full-resolution edge branch: camera pixels -> NMS/hysteresis -> 1-bit
    // frame store.  This path does NOT go through the 320x240 preview store,
    // so edge detail is not lost by the 2:1 decimation.
    //--------------------------------------------------------------------------
    wire [7:0]  edge_full_data;
    wire        edge_full_valid, edge_full_de, edge_full_hs, edge_full_vs;
    wire [10:0] edge_full_x, edge_full_y;

    alg_top #(
        .WIDTH(640), .LATENCY(ALG_LATENCY_FULL), .X_BITS(X_BITS), .Y_BITS(Y_BITS),
        .EDGE_FILTER(2'd2), .NMS_EN(EDGE_ALGO == 0), .LINK_EN(1'b1),
        .CANNY_EN(EDGE_ALGO == 1),
        .CANNY_PREMEDIAN(EDGE_PREMEDIAN), .CANNY_GAUSS3(EDGE_GAUSS3),
        .CANNY_SCHARR(EDGE_SCHARR), .CANNY_NMS_INTERP(EDGE_INTERP_NMS)
    ) u_alg_full (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .in_data(cam_pix_data), .in_valid(cam_pix_valid), .in_de(cam_pix_de),
        .in_hs(cam_pix_hs), .in_vs(cam_pix_vs),
        .in_x(cam_pix_x), .in_y(cam_pix_y),
        .threshold(threshold),
        .out_data(edge_full_data), .out_gray(),
        .out_valid(edge_full_valid), .out_de(edge_full_de),
        .out_hs(edge_full_hs), .out_vs(edge_full_vs),
        .out_x(edge_full_x), .out_y(edge_full_y)
    );

    wire        edge_bit, edge_valid, edge_written;

    edge_frame_store #(
        .H_ACTIVE(640), .V_ACTIVE(480),
        .H_SYNC(96), .H_BACK(48),
        .H_BITS(X_BITS), .V_BITS(Y_BITS),
        .ALIGN_X_SUB(EDGE_ALIGN_X), .ALIGN_Y_SUB(EDGE_ALIGN_Y)
    ) u_edge_store (
        .clk(clk_pixel), .rst_n(rst_n_pix),
        .in_bit(edge_full_data[7]), .in_de(edge_full_de), .in_vs(edge_full_vs),
        .in_x(edge_full_x), .in_y(edge_full_y),
        .disp_de(pix_de), .disp_hcnt(pix_hcnt),
        .disp_x(pix_x), .disp_y(pix_y_act),
        .out_bit(edge_bit), .out_valid(edge_valid), .written(edge_written)
    );

    // Align the 1-bit edge readout with the 16-cycle colour/median delay.
    reg [15:0] edge_bit_dly;
    always @(posedge clk_pixel or negedge rst_n_pix) begin
        if (!rst_n_pix) edge_bit_dly <= 16'd0;
        else             edge_bit_dly <= {edge_bit_dly[14:0], edge_bit};
    end
    wire [7:0] edge_data = edge_bit_dly[15] ? 8'hFF : 8'h00;

    // Shape recognition removed in this version (no mode 5, no shape hardware).

    //--------------------------------------------------------------------------
    // Five display modes (24-bit), all streams aligned to raw_de (16 cycles):
    //   0 colour original, 1 median grayscale, 2 edge, 3 split (gray|edge),
    //   4 colour + red edges.
    //--------------------------------------------------------------------------
    wire edge_on    = edge_data[7];
    wire split_left = (raw_x < 11'd320);

    reg [7:0] base_r, base_g, base_b;
    always @(*) begin
        case (disp_mode)
            3'd0: begin
                base_r = raw_r; base_g = raw_g; base_b = raw_b;
            end
            3'd1: begin
                if (gray_d_valid) begin
                    base_r = gray_d; base_g = gray_d; base_b = gray_d;
                end else begin
                    base_r = 8'h00; base_g = 8'h00; base_b = 8'h00;
                end
            end
            3'd2: begin
                base_r = edge_data; base_g = edge_data; base_b = edge_data;
            end
            3'd3: begin
                if (split_left) begin
                    if (gray_d_valid) begin
                        base_r = gray_d; base_g = gray_d; base_b = gray_d;
                    end else begin
                        base_r = 8'h00; base_g = 8'h00; base_b = 8'h00;
                    end
                end else begin
                    base_r = edge_data; base_g = edge_data; base_b = edge_data;
                end
            end
            default: begin      // 3'd4 : red edges over the colour image
                base_r = edge_on ? 8'hFF : raw_r;
                base_g = edge_on ? 8'h00 : raw_g;
                base_b = edge_on ? 8'h00 : raw_b;
            end
        endcase
    end

    wire [7:0] disp_r = base_r;
    wire [7:0] disp_g = base_g;
    wire [7:0] disp_b = base_b;

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
