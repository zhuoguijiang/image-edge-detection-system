`timescale 1ns / 1ps
//==============================================================================
// rgb332_preview_store : full-res debayered RGB -> 320x240 RGB332 frame store
//
//   Same storage footprint as the old RAW preview store (320*240 bytes =
//   9600 x 64-bit words = exactly the same 77 RAM10 blocks), but each byte is
//   an RGB332 colour pixel:
//        byte = {R[7:5], G[7:5], B[7:6]}
//
//   Camera side : one debayered pixel per clock (638 valid per 640-px line).
//                 Every 2nd pixel is kept; the vertical DDA keeps 240 of the
//                 camera frame's lines.  Eight RGB332 pixels are packed into
//                 one 64-bit word (40 words per stored row).
//   Display side: same free-running 640x480 timing / 2x2 upscale / prefetch as
//                 video_frame_store; RGB332 is expanded back to RGB888.
//==============================================================================
module rgb332_preview_store #(
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

    parameter SW         = 320,
    parameter SH         = 240,
    parameter ROW_W      = SW / 8,       // 40
    parameter WORD_AW    = 6,
    parameter ROW_AW     = 8,
    parameter MEM_AW     = 14,
    parameter MEM_DEPTH  = ROW_W * SH    // 9600
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // camera side : debayered RGB, one pixel per clock
    input  wire [7:0]               in_r,
    input  wire [7:0]               in_g,
    input  wire [7:0]               in_b,
    input  wire                     in_valid,
    input  wire                     in_line_act,
    input  wire                     in_frame_act,

    // display side
    output wire [7:0]               pix_r,
    output wire [7:0]               pix_g,
    output wire [7:0]               pix_b,
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
    output wire                     buf_written
);

    //--------------------------------------------------------------------------
    // Free-running display timing
    //--------------------------------------------------------------------------
    wire                  de, hsync, vsync;
    wire [H_BITS-1:0]     hcnt, x;
    wire [V_BITS-1:0]     vcnt, y;

    vga_timing #(
        .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
        .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK),
        .H_BITS(H_BITS), .V_BITS(V_BITS), .GENLOCK(0)
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
    assign line_late   = 1'b0;
    assign capture_ovf = 1'b0;

    localparam [V_BITS-1:0] V_ACT_STR = V_SYNC + V_BACK;
    wire [V_BITS-1:0] y_act = (vcnt >= V_ACT_STR) ? (vcnt - V_ACT_STR)
                                                  : {V_BITS{1'b0}};
    assign pix_y_act = y_act;

    //--------------------------------------------------------------------------
    // Write side : horizontal 2:1 decimation + vertical DDA, RGB332 packing
    //--------------------------------------------------------------------------
    reg line_act_1p, frame_act_1p;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_act_1p <= 1'b0;
            frame_act_1p <= 1'b0;
        end else begin
            line_act_1p  <= in_line_act;
            frame_act_1p <= in_frame_act;
        end
    end

    wire line_start = in_line_act & ~line_act_1p;
    wire line_end   = ~in_line_act & line_act_1p;
    wire vsync_rise = in_frame_act & ~frame_act_1p;

    reg [11:0] v_cnt;
    reg [11:0] v_last;
    reg [11:0] dda;
    reg        keep_line;
    reg [7:0]  bcnt;          // 0..7 bytes accumulated
    reg [ROW_AW-1:0] wr_row;
    reg [WORD_AW-1:0] wr_word;
    reg [63:0] acc;
    reg        hphase;        // 0 = keep this pixel, 1 = skip
    reg        wr_seen;

    wire [12:0] dda_next = {1'b0, dda} + SH;
    wire        dda_keep = (dda_next >= {1'b0, v_last});

    wire [7:0] rgb332 = {in_r[7:5], in_g[7:5], in_b[7:6]};
    wire       sample = in_valid && in_line_act && keep_line && (hphase == 1'b0);
    wire       word_done = sample && (bcnt == 8'd7);
    wire       partial_flush = line_end && keep_line && (bcnt != 8'd0);

    wire [MEM_AW-1:0] wr_row_x = {{(MEM_AW-ROW_AW){1'b0}}, wr_row};
    wire [MEM_AW-1:0] wr_addr  = (wr_row_x << 5) + (wr_row_x << 3) +
                                 {{(MEM_AW-WORD_AW){1'b0}}, wr_word};

    wire        mem_wr_en  = word_done || partial_flush;
    wire [63:0] mem_wr_data = word_done ? {rgb332, acc[63:8]} : acc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_cnt     <= 12'd0;
            v_last    <= 12'd480;
            dda       <= 12'd0;
            keep_line <= 1'b0;
            bcnt      <= 8'd0;
            wr_row    <= {ROW_AW{1'b0}};
            wr_word   <= {WORD_AW{1'b0}};
            acc       <= 64'd0;
            hphase    <= 1'b0;
            wr_seen   <= 1'b0;
        end else if (vsync_rise) begin
            if ((v_cnt > 12'd200) && (v_cnt < 12'd2000)) v_last <= v_cnt;
            v_cnt     <= 12'd0;
            dda       <= 12'd0;
            wr_row    <= {ROW_AW{1'b0}};
            wr_word   <= {WORD_AW{1'b0}};
            bcnt      <= 8'd0;
            acc       <= 64'd0;
            hphase    <= 1'b0;
        end else if (line_start) begin
            v_cnt     <= v_cnt + 1'b1;
            keep_line <= dda_keep;
            dda       <= dda_keep ? (dda_next[11:0] - v_last) : dda_next[11:0];
            wr_word   <= {WORD_AW{1'b0}};
            bcnt      <= 8'd0;
            acc       <= 64'd0;
            hphase    <= 1'b0;
        end else if (line_end) begin
            if (keep_line && (wr_row != SH - 1))
                wr_row <= wr_row + 1'b1;
            wr_word <= {WORD_AW{1'b0}};
            bcnt    <= 8'd0;
            acc     <= 64'd0;
            hphase  <= 1'b0;
        end else if (in_valid && in_line_act) begin
            hphase <= ~hphase;
            if (keep_line && (hphase == 1'b0)) begin
                wr_seen <= 1'b1;
                if (bcnt == 8'd7) begin
                    bcnt <= 8'd0;
                    if (wr_word != ROW_W - 1)
                        wr_word <= wr_word + 1'b1;
                end else begin
                    bcnt <= bcnt + 1'b1;
                end
                acc <= {rgb332, acc[63:8]};
            end
        end
    end

    //--------------------------------------------------------------------------
    // Simple dual-port frame memory
    //--------------------------------------------------------------------------
    reg [63:0] mem [0:MEM_DEPTH-1];
    reg [63:0] rd_data;

    localparam [H_BITS-1:0] DE_START = H_SYNC + H_BACK;
    wire [V_BITS-2:0] row_idx = y_act[V_BITS-1:1];
    wire [MEM_AW-1:0] row_base =
        ({{(MEM_AW-V_BITS+1){1'b0}}, row_idx} << 5) +
        ({{(MEM_AW-V_BITS+1){1'b0}}, row_idx} << 3);

    wire pre_issue = (hcnt == (DE_START - 2));
    wire pre_latch = (hcnt == (DE_START - 1));
    wire nxt_issue = de & (x[3:0] == 4'd14);
    wire nxt_latch = de & (x[3:0] == 4'd15);

    wire [WORD_AW-1:0] word_nxt = {1'b0, x[10:4]} + 1'b1;
    wire [WORD_AW-1:0] word_idx = (pre_issue | pre_latch) ? {WORD_AW{1'b0}}
                                 : (word_nxt == ROW_W) ? {WORD_AW{1'b0}}
                                 : word_nxt;
    wire [MEM_AW-1:0] rd_addr = row_base + word_idx;
    wire              rd_en   = pre_issue | nxt_issue;

    always @(posedge clk) begin
        if (mem_wr_en) mem[wr_addr] <= mem_wr_data;
        if (rd_en)     rd_data      <= mem[rd_addr];
    end

    reg [63:0] word_lat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) word_lat <= 64'd0;
        else if (pre_latch | nxt_latch) word_lat <= rd_data;
    end

    wire [2:0] byte_sel = de ? x[3:1] : 3'b000;
    wire [7:0] cbyte = word_lat[{byte_sel, 3'b000} +: 8];

    // RGB332 -> RGB888 (bit replication)
    assign pix_r = {cbyte[7:5], cbyte[7:5], cbyte[7:6]};
    assign pix_g = {cbyte[4:2], cbyte[4:2], cbyte[4:3]};
    assign pix_b = {cbyte[1:0], cbyte[1:0], cbyte[1:0], cbyte[1:0]};
    assign pix_valid = de & wr_seen;
    assign buf_written = wr_seen;

endmodule
