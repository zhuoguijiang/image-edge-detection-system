//==============================================================================
// video_source : CSI-2 packed pixel stream  ->  frozen 640x480 pixel stream
//
// WHY THIS MODULE EXISTS
//   A CSI-2 stream carries *active* pixels only - there is no horizontal or
//   vertical blanking inside it.  An HDMI monitor on the other hand needs a
//   full 800x525 timing with real sync pulses.  The display timing generator
//   therefore has to be the master of the output pixel stream:
//
//     csi_rx (64-bit packed RAW8, clk_pixel)
//        -> capture one camera line into a ping-pong line buffer (2 banks)
//        -> vga_timing master pulls 1 pixel/clk during its own DE window
//        -> frozen pixel stream (data / valid / de / hsync / vsync / x / y)
//
//   Camera and display share clk_pixel but their line phases are unrelated.
//   A published camera line is adopted in the horizontal blanking of the next
//   display line; if no new camera line is ready the previous one is repeated
//   (line_late = 1).  This keeps the picture stable without an external frame
//   buffer - a 640x480x8 frame needs 307 KB, which does not fit in the
//   Ti60F225 block RAM.
//
// LINE BUFFER
//   One array, 2**WORD_ADDR_W words per bank, two banks, 64-bit words.  It is
//   written by the capture side and read by the playback side in the same
//   clock, i.e. a plain simple-dual-port RAM, which is the only structure
//   Efinity reliably infers as block RAM.  (Two separate arrays with a
//   combinational bank mux are mapped into LUTs instead - EFX-0657.)
//
// READ TIMING
//   The RAM read port is synchronous, so the word address is issued two clocks
//   before the byte is needed:
//     - word 0 of a line : address at H_SYNC+H_BACK-2, latched at -1
//     - word n (n >= 1)  : address at x[2:0]==6,       latched at x[2:0]==7
//==============================================================================
module video_source #(
    // Display timing : 640x480@60, 25.2 MHz pixel clock (800x525 total)
    parameter H_ACTIVE   = 640,
    parameter H_FRONT    = 16,
    parameter H_SYNC     = 96,
    parameter H_BACK     = 48,
    parameter V_ACTIVE   = 480,
    parameter V_FRONT    = 10,
    parameter V_SYNC     = 2,
    parameter V_BACK     = 33,
    parameter H_BITS     = 11,
    parameter V_BITS     = 11,

    // CSI capture side
    parameter PIX_PER_CLK = 8,      // RAW8 arrives 8 pixels per 64-bit word
    parameter WORD_ADDR_W = 8,      // 256 words per bank = 2048 pixels/line
    parameter H_OFFSET    = 0       // horizontal crop offset, in input pixels
)(
    input  wire                     clk,          // pixel clock, 25.2 MHz
    input  wire                     rst_n,

    //------------------------------------------------------------------
    // CSI-2 capture side (driven by csi_rx, same clk_pixel domain)
    //------------------------------------------------------------------
    input  wire                     in_valid,     // pixel_data_valid
    input  wire [PIX_PER_CLK*8-1:0] in_data,      // pixel_data  (RAW8 packed)
    input  wire                     in_line_act,  // hsync_vc0 : line active
    input  wire                     in_frame_act, // vsync_vc0 : frame active

    //------------------------------------------------------------------
    // Frozen pixel-stream interface   (see docs/pixel_stream_if.md)
    //------------------------------------------------------------------
    output wire [7:0]               pix_data,
    output wire                     pix_valid,
    output wire                     pix_de,
    output wire                     pix_hsync,    // display HSYNC (active low)
    output wire                     pix_vsync,    // display VSYNC (active low)
    output wire [H_BITS-1:0]        pix_x,
    output wire [V_BITS-1:0]        pix_y,

    //------------------------------------------------------------------
    // Status
    //------------------------------------------------------------------
    output wire                     line_late,    // display repeated a line
    output wire                     capture_ovf   // camera line too long
);

    localparam SUB_BITS = 3;                       // log2(PIX_PER_CLK)
    localparam BANK_W   = WORD_ADDR_W;             // words per bank
    localparam LB_DEPTH = (2 * (1 << WORD_ADDR_W)); // both banks
    localparam [BANK_W-1:0] H_OFFSET_W = H_OFFSET / PIX_PER_CLK;

    //--------------------------------------------------------------------------
    // 1. Display timing master (Phase-1 generator, already simulated)
    //--------------------------------------------------------------------------
    wire              hsync, vsync, de;
    wire [H_BITS-1:0] hcnt, vcnt;
    wire [H_BITS-1:0] x;
    wire [V_BITS-1:0] y;

    vga_timing #(
        .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
        .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK),
        .H_BITS(H_BITS),     .V_BITS(V_BITS)
    ) u_timing (
        .clk(clk), .rst_n(rst_n),
        .hsync(hsync), .vsync(vsync), .de(de),
        .hcnt(hcnt), .vcnt(vcnt), .x(x), .y(y)
    );

    assign pix_de    = de;
    assign pix_hsync = hsync;
    assign pix_vsync = vsync;
    assign pix_x     = x;
    assign pix_y     = y;

    localparam [H_BITS-1:0] DE_START = H_SYNC + H_BACK;

    //--------------------------------------------------------------------------
    // 2a. Capture (write) side
    //--------------------------------------------------------------------------
    reg  [BANK_W-1:0]  wr_word;
    reg                wr_bank;
    reg                line_act_1p;
    reg  [H_BITS-1:0]  wr_pix_cnt;

    reg                pub_tog;
    reg                pub_bank;
    reg  [H_BITS-1:0]  pub_pix_len;
    reg                cap_ovf_r;

    wire line_start = in_line_act & ~line_act_1p;
    wire line_end   = ~in_line_act & line_act_1p;

    //--------------------------------------------------------------------------
    // 2b. Playback (read) side
    //--------------------------------------------------------------------------
    reg               rd_tog;
    reg               rd_bank;
    reg  [H_BITS-1:0] rd_pix_len;
    reg               line_late_r;

    wire adopt_line = (hcnt == (DE_START - 4));
    wire pre_issue  = (hcnt == (DE_START - 2));
    wire pre_latch  = (hcnt == (DE_START - 1));
    wire nxt_issue  = de & (x[SUB_BITS-1:0] == 3'd6);
    wire nxt_latch  = de & (x[SUB_BITS-1:0] == 3'd7);

    // word index inside the current line, plus one (the word after x)
    wire [BANK_W-1:0] nxt_word = x[H_BITS-1:SUB_BITS] + 1'b1;
    wire [BANK_W-1:0] mem_word = (pre_issue ? {BANK_W{1'b0}} : nxt_word)
                                 + H_OFFSET_W;

    wire              mem_we   = in_valid & in_line_act & ~cap_ovf_r;
    wire [BANK_W:0]   mem_waddr = {wr_bank, wr_word};
    wire              mem_re   = pre_issue | nxt_issue;
    wire [BANK_W:0]   mem_raddr = {rd_bank, mem_word};

    //--------------------------------------------------------------------------
    // 2c. Line buffer : simple dual port RAM, 2 banks in one array
    //--------------------------------------------------------------------------
    reg [PIX_PER_CLK*8-1:0] lbuf [0:LB_DEPTH-1];
    reg [PIX_PER_CLK*8-1:0] mem_rdata;

    always @(posedge clk) begin
        if (mem_we)
            lbuf[mem_waddr] <= in_data;
        if (mem_re)
            mem_rdata <= lbuf[mem_raddr];
    end

    // line buffer overflow : the camera line needs more than one bank
    wire ovf_now = in_valid & in_line_act & (wr_word == {BANK_W{1'b1}});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_word     <= {BANK_W{1'b0}};
            wr_bank     <= 1'b0;
            line_act_1p <= 1'b0;
            wr_pix_cnt  <= {H_BITS{1'b0}};
            pub_tog     <= 1'b0;
            pub_bank    <= 1'b0;
            pub_pix_len <= {H_BITS{1'b0}};
            cap_ovf_r   <= 1'b0;
        end else begin
            line_act_1p <= in_line_act;

            if (ovf_now) cap_ovf_r <= 1'b1;

            if (line_start) begin
                wr_word    <= {BANK_W{1'b0}};
                wr_pix_cnt <= {H_BITS{1'b0}};
                cap_ovf_r  <= 1'b0;
            end else if (in_valid & in_line_act & ~cap_ovf_r) begin
                wr_word    <= wr_word + 1'b1;
                wr_pix_cnt <= wr_pix_cnt + PIX_PER_CLK;
            end

            // a finished line becomes visible to the playback side
            if (line_end) begin
                pub_pix_len <= wr_pix_cnt;
                pub_bank    <= wr_bank;
                pub_tog     <= ~pub_tog;
                wr_bank     <= ~wr_bank;
                wr_word     <= {BANK_W{1'b0}};
                wr_pix_cnt  <= {H_BITS{1'b0}};
            end

            // new camera frame : restart capture in bank 0
            if (in_frame_act & ~in_line_act) begin
                wr_word    <= {BANK_W{1'b0}};
                wr_pix_cnt <= {H_BITS{1'b0}};
            end
        end
    end

    assign capture_ovf = cap_ovf_r;

    //--------------------------------------------------------------------------
    // 2d. Pixel shift register : 64-bit word -> 1 byte per clock
    //--------------------------------------------------------------------------
    reg [PIX_PER_CLK*8-1:0] shifter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shifter <= {PIX_PER_CLK*8{1'b0}};
        end else if (pre_latch | nxt_latch) begin
            shifter <= mem_rdata;
        end else if (de) begin
            shifter <= {{(PIX_PER_CLK*8-8){1'b0}}, shifter[PIX_PER_CLK*8-1:8]};
        end
    end

    assign pix_data  = shifter[7:0];
    assign pix_valid = de & (x < H_ACTIVE)
                       & (rd_pix_len >= (H_OFFSET + H_ACTIVE));

    //--------------------------------------------------------------------------
    // 2e. Adopt a published camera line at each display line
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_tog      <= 1'b0;
            rd_bank     <= 1'b0;
            rd_pix_len  <= {H_BITS{1'b0}};
            line_late_r <= 1'b0;
        end else if (adopt_line) begin
            if (pub_tog != rd_tog) begin
                rd_tog      <= pub_tog;
                rd_bank     <= pub_bank;
                rd_pix_len  <= pub_pix_len;
                line_late_r <= 1'b0;
            end else begin
                line_late_r <= 1'b1;    // no new line yet : repeat the last one
            end
        end
    end

    assign line_late = line_late_r;

endmodule
