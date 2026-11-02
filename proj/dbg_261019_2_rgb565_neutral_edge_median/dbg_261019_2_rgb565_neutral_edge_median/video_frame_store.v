//==============================================================================
// video_frame_store : camera stream -> internal frame buffer -> display stream
//                     (new in dbg_20261012_03)
//
//   WHY
//     The SC2210 cannot be talked into 640x480@60: its VTS write is ignored
//     (the exposure pins the frame at ~1112 lines = 28 fps) and shortening the
//     exposure killed the stream.  A line-buffer design ("show the newest
//     camera line") can therefore never be stable against a 59.5 Hz display -
//     the line buffer holds 1 line, so the vertical position is whatever the
//     camera happens to be doing.
//
//     This module stores a whole decimated frame in block RAM instead:
//       camera 640x480  ->  2:1 horizontal + ~2.3:1 vertical decimation
//                       ->  320x240 x 8b frame buffer (76.8 kB, fits the
//                          Ti60F225 RAM10 budget: 61 of 133 blocks)
//                       ->  read out at the display's own 59.5 Hz timing and
//                          upscaled x2/x2 back to 640x480
//     The display position is now a fixed function of the display's own x/y,
//     so the picture cannot roll no matter what the camera does.  The camera
//     writes rows 0..239 of each of its frames, so the content refreshes at
//     ~28 fps while the display runs at 59.5 Hz - the only artefact is a
//     horizontal "tear" seam where the writer catches the reader, which drifts
//     slowly from top to bottom.
//
//   WRITE SIDE
//     line DDA : keep SH=240 camera lines per camera frame, evenly spaced over
//                V_last (the previous frame's line count, measured on the fly),
//                so the stored image always covers the full sensor field
//                regardless of the sensor's real VTS.
//     pixel    : from every 64-bit word (8 RAW8 pixels) take pixels 0,2,4,6,
//                i.e. 4 pixels; two camera words are packed into one 64-bit
//                buffer word, so 320 stored pixels per line = 40 words.
//                (64-bit words are used deliberately: with 32-bit words the
//                 tool needed 124 RAM10 blocks for the frame, with 64-bit
//                 words about half of that - RAM10 count matters, the device
//                 has only 133 and 151 do not fit.)
//
//   READ SIDE
//     word  = row(y/2) * 40 + x/16     (one word holds 8 stored pixels, each
//                                       stored pixel is shown on 2 display
//                                       pixels -> 16 display pixels per word)
//     byte  = x[3:1]                   (each stored byte is shown twice)
//     row   = y[..:1]                  (each stored row is shown twice)
//
//   OUTPUT
//     Same "frozen pixel stream" interface as video_source, so the rest of the
//     pipeline (video_delay / alg_top / split_mux / rgb2dvi) is untouched.
//     line_late and capture_ovf are always 0 here (there is no line buffer any
//     more); pix_valid is gated by "the buffer has been written at least once"
//     so the LED ladder keeps its meaning.
//
//   SIMULATION FIXES (2026-10-12, found by sim/tb_video_frame_store.v)
//     1. wr_addr used `wr_row << 5`, and a shift in Verilog is only as wide as
//        its left operand (8 bits here): row 238 -> 7616 wrapped to 192, so
//        rows 40 apart landed on the same address and the stored frame was a
//        mixture.  Both shifts are now done on a MEM_AW-bit copy of wr_row.
//     2. v_cnt started at 1 on the first line of a frame, so v_last was
//        lines+1 : the DDA then kept SH*lines/(lines+1) = 239 rows and the last
//        stored row never refreshed (it kept the previous frame's content).
//     3. The first camera beat can arrive in the very cycle in_line_act rises.
//        That cycle is now handled inside the line_start branch (counted as
//        beat 1, no write), instead of leaving wr_word/beat_sel to a second
//        always-block statement that could overwrite the just-cleared word.
//     4. wr_row saturates at SH-1 instead of wrapping, so a frame with more
//        lines than v_last can no longer overwrite row 0 with tail content.
//==============================================================================
module video_frame_store #(
    // display timing (must match the monitor mode)
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

    // stored frame
    parameter SW         = 320,          // stored pixels per row
    parameter SH         = 240,          // stored rows
    parameter ROW_W      = SW / 8,       // 64-bit words per stored row = 40
    parameter WORD_AW    = 6,            // bits for 0..ROW_W-1
    parameter ROW_AW     = 8,            // bits for 0..SH-1
    parameter MEM_AW     = 14,           // address width for 240*40 = 9600 words
    parameter MEM_DEPTH  = ROW_W * SH    // exact number of 64-bit words (9600)
)(
    input  wire                     clk,          // clk_pixel (25 MHz)
    input  wire                     rst_n,

    //------------------------------------------------------------------
    // camera side (same clock: everything lives in clk_pixel)
    //------------------------------------------------------------------
    input  wire                     in_valid,     // pixel_data_valid
    input  wire [63:0]              in_data,      // pixel_data (RAW8 packed)
    input  wire                     in_line_act,  // hsync_vc0 : line active
    input  wire                     in_frame_act, // vsync_vc0 : high in frame

    //------------------------------------------------------------------
    // display side : frozen pixel stream (video_source compatible)
    //------------------------------------------------------------------
    output wire [7:0]               pix_data,
    output wire                     pix_valid,
    output wire                     pix_de,
    output wire                     pix_hsync,
    output wire                     pix_vsync,
    output wire [H_BITS-1:0]        pix_x,
    output wire [H_BITS-1:0]        pix_hcnt,
    output wire [V_BITS-1:0]        pix_y,
    output wire [V_BITS-1:0]        pix_y_act,
    output wire                     line_late,
    output wire                     capture_ovf,
    output wire                     buf_written   // 1 = at least one frame stored
);

    //--------------------------------------------------------------------------
    // Display timing : free running, never touched by the camera
    //--------------------------------------------------------------------------
    wire                    de, hsync, vsync;
    wire [H_BITS-1:0]       hcnt, x;
    wire [V_BITS-1:0]       vcnt, y;

    vga_timing #(
        .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
        .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK),
        .H_BITS(H_BITS),     .V_BITS(V_BITS),    .GENLOCK(0)
    ) u_timing (
        .clk(clk), .rst_n(rst_n), .frame_restart(1'b0),
        .hsync(hsync), .vsync(vsync), .de(de),
        .hcnt(hcnt), .vcnt(vcnt), .x(x), .y(y)
    );

    assign pix_de    = de;
    assign pix_hsync = hsync;
    assign pix_vsync = vsync;
    assign pix_x     = x;
    assign pix_hcnt  = hcnt;
    assign pix_y     = y;
    assign line_late    = 1'b0;
    assign capture_ovf  = 1'b0;

    //--------------------------------------------------------------------------
    // 1. Write side
    //--------------------------------------------------------------------------
    reg  line_act_1p, frame_act_1p;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_act_1p  <= 1'b0;
            frame_act_1p <= 1'b0;
        end else begin
            line_act_1p  <= in_line_act;
            frame_act_1p <= in_frame_act;
        end
    end

    wire line_start = in_line_act & ~line_act_1p;
    wire line_end   = ~in_line_act & line_act_1p;
    wire vsync_rise = in_frame_act & ~frame_act_1p;   // one pulse per camera frame

    reg  [11:0] v_cnt;        // camera lines counted in the current frame
    reg  [11:0] v_last;       // line count of the previous frame
    reg  [11:0] dda;          // keep-line accumulator
    reg         keep_line;
    reg  [ROW_AW-1:0] wr_row;
    reg  [WORD_AW-1:0] wr_word;
    reg  [31:0] beat_acc;     // first camera beat of the current buffer word
    reg         beat_sel;     // 0 = first beat, 1 = second beat (write here)
    reg         wr_seen;

    // DDA : keep SH rows per V_last camera lines (SH/V_last fraction)
    wire [12:0] dda_next = {1'b0, dda} + SH;
    wire        dda_keep = (dda_next >= {1'b0, v_last});
    wire        line_beat = in_valid & in_line_act;   // a beat in this cycle
    wire        beat_keep = line_start ? dda_keep : keep_line;
    wire        beat_en   = line_beat & ~line_start & beat_keep;
    // stored pixels 0,2,4,6 of one camera word (bytes 0,2,4,6 of in_data)
    wire [31:0] keep4 = {in_data[55:48], in_data[39:32],
                         in_data[23:16], in_data[7:0]};
    wire [63:0] wr_data = {keep4, beat_acc};   // low byte = first pixel
    wire        wr_en   = beat_en & beat_sel;  // 2nd beat completes a word

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_cnt     <= 12'd0;
            v_last    <= 12'd480;      // sane start value (keep every other line)
            dda       <= 12'd0;
            keep_line <= 1'b0;
            wr_row    <= {ROW_AW{1'b0}};
            wr_word   <= {WORD_AW{1'b0}};
            beat_acc  <= 32'd0;
            beat_sel  <= 1'b0;
            wr_seen   <= 1'b0;
        end else if (vsync_rise) begin
            // A camera frame just ended: v_cnt is the number of lines it had.
            // (The sensor's real VTS is ~1112, not the 525 we program, so the
            //  DDA must follow the measured value.)  Sanity bound so that a
            //  lost/extra vsync cannot poison the DDA.
            if ((v_cnt > 12'd200) && (v_cnt < 12'd2000)) v_last <= v_cnt;
            v_cnt     <= 12'd0;
            dda       <= 12'd0;
            wr_row    <= {ROW_AW{1'b0}};      // every camera frame fills rows 0..SH-1
            wr_word   <= {WORD_AW{1'b0}};
            beat_acc  <= 32'd0;
            beat_sel  <= 1'b0;
        end else if (line_start) begin
            // v_cnt counts the lines of the frame that is *running*: it starts
            // at 0 on the frame's first line, so the value latched into v_last
            // is exactly the number of lines the frame had.  (Counting from 1
            // costs one stored row per frame - the DDA then keeps only
            // SH*lines/(lines+1) = 239 rows and the last row goes stale.)
            v_cnt     <= v_cnt + 1'b1;
            keep_line <= dda_keep;
            dda       <= dda_keep ? (dda_next[11:0] - v_last) : dda_next[11:0];
            wr_word   <= {WORD_AW{1'b0}};
            beat_acc  <= keep4;
            // The sensor's first beat comes in the very cycle in_line_act rises:
            // count it as beat 1 of the new line (no write in this cycle, the
            // 64-bit word it belongs to is not complete yet).
            beat_sel  <= line_beat;
            if (line_beat) wr_seen <= 1'b1;
        end else if (line_end && keep_line) begin
            // A kept line just ended : the next kept line goes into the next
            // row.  (line_end and beat_en cannot collide: line_end needs
            // in_line_act low, a beat needs it high.)  It saturates instead of
            // wrapping, so a frame with more lines than v_last cannot overwrite
            // row 0 with tail content.
            if (wr_row != SH[ROW_AW-1:0] - 1'b1) wr_row <= wr_row + 1'b1;
        end else if (beat_en) begin
            wr_seen  <= 1'b1;
            beat_acc <= keep4;
            beat_sel <= ~beat_sel;
            if (beat_sel && (wr_word != ROW_W[WORD_AW-1:0] - 1'b1))
                wr_word <= wr_word + 1'b1;   // 2nd beat completes a buffer word
        end
    end

    // row*40 : the shift must be done in MEM_AW bits.  `wr_row << 5` on its own
    // is only ROW_AW = 8 bits wide (a shift is sized by its left operand), so
    // row 238 -> 7616 wraps to 192 and rows 40 apart land on the same address.
    // That aliasing is what scrambled the stored frame.
    wire [MEM_AW-1:0] wr_row_x = {{(MEM_AW-ROW_AW){1'b0}}, wr_row};
    wire [MEM_AW-1:0] wr_addr  = (wr_row_x << 5) + (wr_row_x << 3) +
                                 {{(MEM_AW-WORD_AW){1'b0}}, wr_word};

    //--------------------------------------------------------------------------
    // 2. Frame buffer : 32-bit x 19200 simple dual port (simple_dual_port so it
    //    infers block RAM; a byte-wide array of 76800 entries would not fit the
    //    number of RAM10 blocks)
    //--------------------------------------------------------------------------
    // Only MEM_DEPTH words are ever addressed (wr_addr <= 9599).  Declaring the
    // exact depth lets Efinity use ~60 RAM10 blocks instead of 128.
    reg [63:0] mem [0:MEM_DEPTH-1];
    reg [63:0] rd_data;
    wire [MEM_AW-1:0] rd_addr;
    wire              rd_en;

    always @(posedge clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
        if (rd_en) rd_data      <= mem[rd_addr];
    end

    //--------------------------------------------------------------------------
    // 3. Read side : display x/y -> buffer word, 2x/2x upscale on the way out
    //--------------------------------------------------------------------------
    localparam [H_BITS-1:0] DE_START = H_SYNC + H_BACK;
    localparam [V_BITS-1:0] V_ACT_STR = V_SYNC + V_BACK;

    // active line number (0..479) even while DE is low, so the prefetch works
    wire [V_BITS-1:0] y_act = (vcnt >= V_ACT_STR) ? (vcnt - V_ACT_STR)
                                                  : {V_BITS{1'b0}};
    assign pix_y_act = y_act;
    wire [V_BITS-2:0] row_idx = y_act[V_BITS-1:1];        // row = y/2
    wire [MEM_AW-1:0] row_base =
        ({{(MEM_AW-V_BITS+1){1'b0}}, row_idx} << 5) +
        ({{(MEM_AW-V_BITS+1){1'b0}}, row_idx} << 3);      // row*40

    wire              pre_issue = (hcnt == (DE_START - 2));
    wire              pre_latch = (hcnt == (DE_START - 1));
    wire              nxt_issue = de & (x[3:0] == 4'd14);
    wire              nxt_latch = de & (x[3:0] == 4'd15);

    // Prefetch the next word while the current one is displayed.  At the last
    // word of a row x[10:4]+1 would be ROW_W (one past the row), so wrap it to
    // 0 and keep the read address inside the 9600-word array (that prefetched
    // value is never used for a visible pixel).
    wire [WORD_AW-1:0] word_nxt = {1'b0, x[10:4]} + 1'b1;
    wire [WORD_AW-1:0] word_idx = (pre_issue | pre_latch) ? {WORD_AW{1'b0}}
                                 : (word_nxt == ROW_W) ? {WORD_AW{1'b0}}
                                 : word_nxt;
    assign rd_addr = row_base + word_idx;
    assign rd_en   = pre_issue | nxt_issue;

    reg  [63:0]       word_lat;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                 word_lat <= 64'd0;
        else if (pre_latch | nxt_latch) word_lat <= rd_data;
    end

    // byte selection : x[3:1] -> each stored byte appears on two pixels
    wire [2:0] byte_sel = de ? x[3:1] : 3'b000;
    assign pix_data  = word_lat[{byte_sel, 3'b000} +: 8];
    assign pix_valid = de & wr_seen;
    assign buf_written = wr_seen;

endmodule
