//==============================================================================
// dbg_led_bank : "which stage of the camera path is broken" LED bank
//
//   Used by proj/dbg_20260924_01 (top = system_dbg_top).
//
//   BOARD POLARITY
//     The 8 board LEDs are ACTIVE LOW (Ti60_F225_Core_V1.4.pdf, sheet
//     "BANK 3.3V GPIO"): VDD3V3 -> 4.7K -> LED D1..D8 -> FPGA pin, i.e. the
//     FPGA pin sinks the current.  led[i] = 0 lights LED i.
//
//   Therefore this module is written in terms of *fault* flags:
//     dbg_fault[i] = 1  ->  LED i is LIT
//   and the LED pins get `led = ~dbg_fault`.
//
//     ALL LEDs dark  =  the camera data path is running
//     a lit LED      =  the stage it names is broken
//
//   LED   signal                        lit means
//   ---   ---------------------------   --------------------------------------
//   0     ~sys_pll_lock                 PLL not locked (no clocks yet)
//   1     ~i2c_done                     I2C has not pushed all 265 regs yet
//   2     i2c_nack (sticky)             a NACK was seen: camera not answering
//   3     ~seen_csi_valid (sticky)      no valid CSI pixel has EVER arrived
//   4     ~seen_csi_sync  (sticky)      no CSI hsync/vsync has EVER arrived
//   5     ~seen_pix_valid (sticky)      the line buffer never produced a pixel
//   6     seen_csi_valid & ~cam_alive   data arrived once, but is gone now
//   7     ovf | dt_bad    (sticky)      line-buffer overflow / not RAW8(0x2A)
//
//   CLOCK DOMAINS (important for the logic analyzer!)
//     Everything except sys_pll_lock / i2c_done / i2c_nack is registered in
//     `clk` (clk_pixel).  Those three come from the PLL and from the clk_sys
//     I2C master, so they only drive the LED pins combinationally - they must
//     never be sampled by clk-domain logic (a clk_sys -> clk_pixel probe costs
//     ~1.1 ns of setup, more than the budget; see docs/dbg_core.md).
//     dbg_fault_pix / dbg_sticky are the safe (clk-domain) vectors for the
//     debugger probes, dbg_fault_ctrl is the control-domain one.
//==============================================================================
module dbg_led_bank #(
    // Camera-alive timeout, in clk cycles.  The real design uses ~40 ms
    // (1_000_000 @ 25 MHz); a small value keeps testbenches fast.
    parameter [20:0] CAM_ALIVE_TIMEOUT = 21'd1_000_000
)(
    input  wire        clk,             // pixel clock
    input  wire        rst_n,           // reset, synchronous release to clk

    //--- observations in the clk domain --------------------------------------
    input  wire        csi_valid,       // csi_rx pixel_data_valid
    input  wire        csi_hsync,       // csi_rx hsync_vc0
    input  wire        csi_vsync,       // csi_rx vsync_vc0
    input  wire [5:0]  csi_datatype,    // csi_rx datatype (RAW8 = 0x2A)
    input  wire        pix_valid,       // video_source output valid
    input  wire        capture_ovf,     // video_source line-buffer overflow

    //--- observations in other clock domains (LED pins only) -----------------
    input  wire        sys_pll_lock,
    input  wire        i2c_done,
    input  wire        i2c_nack,

    //--- outputs -------------------------------------------------------------
    output reg         cam_alive,       // 1 = csi_valid seen within the timeout
    output wire [7:0]  led,             // active low : 0 = lit
    output wire [4:0]  dbg_fault_pix,   // clk-domain fault flags {led7..led3}
    output wire [2:0]  dbg_fault_ctrl,  // control-domain flags   {led2..led0}
    output wire [4:0]  dbg_sticky       // {seen_valid, seen_sync, seen_pix,
                                        //  ovf, dt_bad}
);

    localparam [5:0] DT_RAW8 = 6'h2A;

    //--------------------------------------------------------------------------
    // Camera-alive detector : csi_valid pulses keep the counter at zero; when
    // the stream stops for CAM_ALIVE_TIMEOUT cycles the camera counts as gone.
    //--------------------------------------------------------------------------
    reg [20:0] cam_alive_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
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

    //--------------------------------------------------------------------------
    // Sticky "have I ever seen it" flags
    //--------------------------------------------------------------------------
    reg seen_csi_valid;
    reg seen_csi_sync;
    reg seen_pix_valid;
    reg ovf_sticky;
    reg dt_bad_sticky;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seen_csi_valid <= 1'b0;
            seen_csi_sync  <= 1'b0;
            seen_pix_valid <= 1'b0;
            ovf_sticky     <= 1'b0;
            dt_bad_sticky  <= 1'b0;
        end else begin
            if (csi_valid)             seen_csi_valid <= 1'b1;
            if (csi_hsync | csi_vsync) seen_csi_sync  <= 1'b1;
            if (pix_valid)             seen_pix_valid <= 1'b1;
            if (capture_ovf)           ovf_sticky     <= 1'b1;
            // anything but RAW8 means the sensor format is not what the rest of
            // the pipeline assumes (Bayer RAW8, 8 pixels per 64-bit word)
            if (csi_valid && (csi_datatype != DT_RAW8)) dt_bad_sticky <= 1'b1;
        end
    end

    assign dbg_sticky = {seen_csi_valid, seen_csi_sync, seen_pix_valid,
                         ovf_sticky, dt_bad_sticky};

    //--------------------------------------------------------------------------
    // Fault flags : 1 = the LED is lit
    //--------------------------------------------------------------------------
    assign dbg_fault_pix  = {                       // led7 .. led3
        (ovf_sticky | dt_bad_sticky),               // 7 : overflow / wrong dt
        (seen_csi_valid & ~cam_alive),              // 6 : had data, now gone
        ~seen_pix_valid,                            // 5 : line buffer silent
        ~seen_csi_sync,                             // 4 : no hsync/vsync ever
        ~seen_csi_valid                             // 3 : no pixel ever
    };

    assign dbg_fault_ctrl = {                       // led2 .. led0
        i2c_nack,                                   // 2 : camera did not ACK
        ~i2c_done,                                  // 1 : config not finished
        ~sys_pll_lock                               // 0 : no clocks
    };

    assign led = ~{dbg_fault_pix, dbg_fault_ctrl};   // active low

endmodule
