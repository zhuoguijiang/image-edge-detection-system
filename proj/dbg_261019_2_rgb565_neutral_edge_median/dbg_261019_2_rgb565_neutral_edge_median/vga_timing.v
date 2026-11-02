//==============================================================================
// dbg_20261009_01 LOCAL COPY - adds an ELASTIC vertical frame so the display
// frame can be locked to the camera frame ("genlock").
//
//   WHY
//     The SC2210 sends 640 px lines, but its frame rate does not match the
//     display's 640x480@59.5 Hz (measured: time since vsync ~19.3 ms, i.e.
//     ~52 Hz, with irregular line spacing).  A free-running display therefore
//     keeps sliding its 480-line window through the camera frame - the picture
//     rolls.  Locking the frame boundary to the camera removes the sliding.
//
//   HOW  (new input `frame_restart`: one clk pulse per camera frame)
//     * the counter runs 0..V_TOTAL-1 as before;
//     * a restart pulse is only ACCEPTED if the current frame is already at
//       least V_TOTAL lines long - spurious/too-early pulses are ignored, so a
//       noisy vsync can no longer wreck the display timing
//       (dbg_20261009_01 reacted to every pulse and could end up re-starting
//        the frame constantly -> monitor lost sync -> black screen);
//     * after the active area, an accepted restart starts a new frame;
//     * if none arrives by the nominal end, the blanking is kept open
//       (elastic frame) up to V_MAX_LINES lines;
//     * V_MAX_LINES clamps the frame to V_TOTAL+95 = 620 lines = 19.84 ms
//       = 50.4 Hz, so the vertical rate always stays inside 50.4..59.5 Hz -
//       the monitor can always lock, worst case onto a slowly rolling picture
//       instead of a black screen.
//
//   `GENLOCK = 0` restores the original free-running behaviour exactly, so this
//   version can be rebuilt as a drop-in replacement for dbg_20260929_01.
//   The horizontal timing is untouched.
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
    parameter V_BITS   = 10,
    // dbg_20261009_01
    parameter GENLOCK  = 1,      // 1 = elastic frame locked to frame_restart
    parameter V_MAX_LINES = V_TOTAL + 95    // 620 lines = 19.84 ms = 50.4 Hz
)(
    input  wire                clk,    // 25 MHz pixel clock
    input  wire                rst_n,  // active-low reset
    input  wire                frame_restart,  // 1-clk pulse: camera frame start
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

    localparam [V_BITS-1:0] V_ACT_END = V_SYNC + V_BACK + V_ACTIVE;   // 515
    localparam [V_BITS:0]   V_MAXCNT  = V_MAX_LINES;                  // clamp
    localparam [V_BITS:0]   V_MINCNT  = V_TOTAL;                      // reject early

    reg              pending;      // camera frame start seen, alignment due
    reg [V_BITS:0]   frame_lines;  // lines counted in the current frame

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hcnt_r <= {H_BITS{1'b0}};
            vcnt_r <= {V_BITS{1'b0}};
            pending      <= 1'b0;
            frame_lines  <= {(V_BITS+1){1'b0}};
        end else if (hcnt_r == H_TOTAL - 1'b1) begin
            hcnt_r <= {H_BITS{1'b0}};
            // A restart pulse only counts as a frame boundary if this frame is
            // already long enough - this filters noisy/early vsync pulses.
            frame_lines <= frame_lines + 1'b1;
            if (GENLOCK && frame_restart && (frame_lines >= V_MINCNT)) pending <= 1'b1;

            if (GENLOCK && pending && (vcnt_r >= V_ACT_END)) begin
                // aligned: start a new display frame here
                vcnt_r      <= {V_BITS{1'b0}};
                pending     <= 1'b0;
                frame_lines <= {(V_BITS+1){1'b0}};
            end else if (GENLOCK && (vcnt_r == V_TOTAL - 1'b1) && (frame_lines >= V_MAXCNT)) begin
                // elastic blanking hit its clamp (50.4 Hz): free-run from here
                vcnt_r      <= {V_BITS{1'b0}};
                pending     <= 1'b0;
                frame_lines <= {(V_BITS+1){1'b0}};
            end else if (GENLOCK && (vcnt_r == V_TOTAL - 1'b1)) begin
                vcnt_r <= vcnt_r;              // hold in the last blanking line
            end else begin
                vcnt_r <= (vcnt_r == V_TOTAL - 1'b1) ? {V_BITS{1'b0}} : vcnt_r + 1'b1;
                if (vcnt_r == V_TOTAL - 1'b1) frame_lines <= {(V_BITS+1){1'b0}};
            end
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
