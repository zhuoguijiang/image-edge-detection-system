`timescale 1ns / 1ps
//==============================================================================
// rgb565_preview_store : full-res debayered RGB -> 320x240 RGB565 frame store
//
//   byte budget: 320*240*16 = 1,228,800 bits = 120 RAM10.
//   write: one debayered pixel/clock, every 2nd pixel kept, 4 RGB565 pixels
//          packed into one 64-bit word (80 words per stored row).
//   read : free-running 640x480 timing, 2x2 upscale, RGB565 -> RGB888.
//
//   BILINEAR_H=1 : average the current and next stored pixel on odd display
//                  columns (smoother vertical edges; no extra line buffer).
//   SAT_EN=1     : 1.25x saturation around the luma (vivid comparison variant).
//==============================================================================
module rgb565_preview_store #(
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
    parameter ROW_W      = SW / 4,       // 80
    parameter WORD_AW    = 7,
    parameter ROW_AW     = 8,
    parameter MEM_AW     = 15,
    parameter MEM_DEPTH  = ROW_W * SH,   // 19200
    parameter BILINEAR_H = 0,
    parameter SAT_EN     = 0
)(
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire [7:0]               in_r,
    input  wire [7:0]               in_g,
    input  wire [7:0]               in_b,
    input  wire                     in_valid,
    input  wire                     in_line_act,
    input  wire                     in_frame_act,

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
    // Display timing
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
    // Write side: 2:1 horizontal sampling, vertical DDA, 4 pixels / 64-bit word
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
    reg [2:0]  bcnt;          // 0..3
    reg [ROW_AW-1:0] wr_row;
    reg [WORD_AW-1:0] wr_word;
    reg [63:0] acc;
    reg        hphase;
    reg        wr_seen;

    wire [12:0] dda_next = {1'b0, dda} + SH;
    wire        dda_keep = (dda_next >= {1'b0, v_last});

    wire [15:0] rgb565 = {in_r[7:3], in_g[7:2], in_b[7:3]};
    wire        sample = in_valid && in_line_act && keep_line && (hphase == 1'b0);
    wire        word_done = sample && (bcnt == 3'd3);
    wire        partial_flush = line_end && keep_line && (bcnt != 3'd0);

    wire [MEM_AW-1:0] wr_row_x = {{(MEM_AW-ROW_AW){1'b0}}, wr_row};
    wire [MEM_AW-1:0] wr_addr  = (wr_row_x << 6) + (wr_row_x << 4) +
                                 {{(MEM_AW-WORD_AW){1'b0}}, wr_word};

    wire        mem_wr_en   = word_done || partial_flush;
    wire [63:0] mem_wr_data = word_done ? {rgb565, acc[63:16]} : acc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_cnt     <= 12'd0;
            v_last    <= 12'd480;
            dda       <= 12'd0;
            keep_line <= 1'b0;
            bcnt      <= 3'd0;
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
            bcnt      <= 3'd0;
            acc       <= 64'd0;
            hphase    <= 1'b0;
        end else if (line_start) begin
            v_cnt     <= v_cnt + 1'b1;
            keep_line <= dda_keep;
            dda       <= dda_keep ? (dda_next[11:0] - v_last) : dda_next[11:0];
            wr_word   <= {WORD_AW{1'b0}};
            bcnt      <= 3'd0;
            acc       <= 64'd0;
            hphase    <= 1'b0;
        end else if (line_end) begin
            if (keep_line && (wr_row != SH - 1))
                wr_row <= wr_row + 1'b1;
            wr_word <= {WORD_AW{1'b0}};
            bcnt    <= 3'd0;
            acc     <= 64'd0;
            hphase  <= 1'b0;
        end else if (in_valid && in_line_act) begin
            hphase <= ~hphase;
            if (keep_line && (hphase == 1'b0)) begin
                wr_seen <= 1'b1;
                if (bcnt == 3'd3) begin
                    bcnt <= 3'd0;
                    if (wr_word != ROW_W - 1)
                        wr_word <= wr_word + 1'b1;
                end else begin
                    bcnt <= bcnt + 1'b1;
                end
                acc <= {rgb565, acc[63:16]};
            end
        end
    end

    //--------------------------------------------------------------------------
    // Frame memory
    //--------------------------------------------------------------------------
    reg [63:0] mem [0:MEM_DEPTH-1];
    reg [63:0] rd_data;

    localparam [H_BITS-1:0] DE_START = H_SYNC + H_BACK;
    wire [V_BITS-2:0] row_idx = y_act[V_BITS-1:1];
    wire [MEM_AW-1:0] row_base =
        ({{(MEM_AW-V_BITS+1){1'b0}}, row_idx} << 6) +
        ({{(MEM_AW-V_BITS+1){1'b0}}, row_idx} << 4);

    wire pre_issue = (hcnt == (DE_START - 2));
    wire pre_latch = (hcnt == (DE_START - 1));
    wire nxt_issue = de & (x[2:0] == 3'd6);
    wire nxt_latch = de & (x[2:0] == 3'd7);

    wire [WORD_AW-1:0] word_nxt = {1'b0, x[9:3]} + 1'b1;
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

    wire [1:0] pidx = de ? x[2:1] : 2'd0;
    reg [15:0] pix16_cur, pix16_nxt;
    always @(*) begin
        case (pidx)
            2'd0: begin pix16_cur = word_lat[15:0];  pix16_nxt = word_lat[31:16]; end
            2'd1: begin pix16_cur = word_lat[31:16]; pix16_nxt = word_lat[47:32]; end
            2'd2: begin pix16_cur = word_lat[47:32]; pix16_nxt = word_lat[63:48]; end
            default: begin pix16_cur = word_lat[63:48]; pix16_nxt = word_lat[63:48]; end
        endcase
    end

    wire [15:0] pix16 = (BILINEAR_H && x[0]) ? (({1'b0,pix16_cur} + {1'b0,pix16_nxt}) >> 1)
                                              : pix16_cur;

    wire [4:0] r5 = pix16[15:11];
    wire [5:0] g6 = pix16[10:5];
    wire [4:0] b5 = pix16[4:0];
    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6, g6[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};

    // optional 1.25x saturation around luma
    wire [15:0] ysum = 16'd77 * r8 + 16'd150 * g8 + 16'd29 * b8;
    wire [7:0]  y8   = ysum[15:8];

    wire signed [9:0] dr = $signed({2'b00, r8}) - $signed({2'b00, y8});
    wire signed [9:0] dg = $signed({2'b00, g8}) - $signed({2'b00, y8});
    wire signed [9:0] db = $signed({2'b00, b8}) - $signed({2'b00, y8});
    wire signed [9:0] drs = dr + (dr >>> 2);
    wire signed [9:0] dgs = dg + (dg >>> 2);
    wire signed [9:0] dbs = db + (db >>> 2);
    wire signed [10:0] rs = $signed({3'b000, y8}) + drs;
    wire signed [10:0] gs = $signed({3'b000, y8}) + dgs;
    wire signed [10:0] bs = $signed({3'b000, y8}) + dbs;

    wire [7:0] rv = (rs < 0) ? 8'd0 : (rs > 11'sd255) ? 8'd255 : rs[7:0];
    wire [7:0] gv = (gs < 0) ? 8'd0 : (gs > 11'sd255) ? 8'd255 : gs[7:0];
    wire [7:0] bv = (bs < 0) ? 8'd0 : (bs > 11'sd255) ? 8'd255 : bs[7:0];

    assign pix_r = SAT_EN ? rv : r8;
    assign pix_g = SAT_EN ? gv : g8;
    assign pix_b = SAT_EN ? bv : b8;
    assign pix_valid = de & wr_seen;
    assign buf_written = wr_seen;

endmodule
