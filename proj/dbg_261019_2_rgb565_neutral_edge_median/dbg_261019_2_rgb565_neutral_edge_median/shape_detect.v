`timescale 1ns / 1ps
//==============================================================================
// shape_detect : dominant-shape classifier on the Canny edge map.
//
//   A 32x24 edge-density grid (20x20 px cells, 4-bit saturating counters) is
//   built during the camera frame.  At frame end:
//     1) active cells (count > CELL_THRESH) give the bounding box;
//     2) a second pass measures how much of each bbox side is occupied;
//     3) the four corners and four side mid-points are sampled.
//
//   Classification (single dominant, mostly axis-aligned shape):
//     rectangle  : all four bbox sides occupied (also handles rounded corners
//                  such as a phone case), or 3 corners + 3 sides;
//      triangle  : right triangle (3 corners, only 2 sides) or isosceles
//                  (two base corners + opposite side mid-point);
//      circle    : near-square bbox, empty corners, 4 side mid-points,
//                  no fully occupied sides.
//
//   shape_kind: 0 = none, 1 = circle, 2 = rectangle, 3 = triangle
//==============================================================================
module shape_detect #(
    parameter H_ACTIVE  = 640,
    parameter V_ACTIVE  = 480,
    parameter GW        = 32,
    parameter GH        = 24,
    parameter CELL      = 20,
    parameter [3:0] CELL_THRESH = 4'd5
)(
    input  wire         clk,
    input  wire         rst_n,

    input  wire         edge_bit,
    input  wire         edge_de,
    input  wire         edge_vs,       // active low

    output reg  [1:0]   shape_kind,
    output reg  [10:0]  bbox_x0,
    output reg  [10:0]  bbox_x1,
    output reg  [10:0]  bbox_y0,
    output reg  [10:0]  bbox_y1,
    output reg          result_valid
);

    localparam NCELL = GW * GH;        // 768

    reg [3:0]  cellcnt [0:NCELL-1];
    reg [NCELL-1:0] active;

    reg [4:0]  cell_x, cell_y;
    reg [4:0]  x20, y20;
    reg        de_prev, seen_line;
    reg        vs_prev;

    wire [9:0] cell_idx = {cell_y, cell_x};
    wire       vs_fall  = (vs_prev == 1'b1) && (edge_vs == 1'b0);

    localparam S_IDLE    = 3'd0,
               S_ANALYZE = 3'd1,
               S_SIDES   = 3'd2,
               S_CLASS   = 3'd3,
               S_CLEAR   = 3'd4,
               S_WAIT    = 3'd5;

    reg [2:0]  state;
    reg [9:0]  scan_i;
    reg [5:0]  side_i;
    reg        side_phase;
    reg [5:0]  top_cnt, bot_cnt, left_cnt, right_cnt;
    reg        any_active;
    reg [4:0]  gx0, gx1, gy0, gy1;
    // debug latches (not needed by the hardware, held for simulation)
    reg [7:0]  dbg_pts;
    reg [2:0]  dbg_corners, dbg_mids, dbg_side_hi;
    reg        dbg_apex;

    //--------------------------------------------------------------------------
    // Pixel / cell position tracking
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x20 <= 5'd0;     y20 <= 5'd0;
            cell_x <= 5'd0;  cell_y <= 5'd0;
            de_prev <= 1'b0; seen_line <= 1'b0;
            vs_prev <= 1'b1;
        end else begin
            vs_prev <= edge_vs;
            de_prev <= edge_de;

            if (edge_vs == 1'b0) begin
                x20 <= 5'd0;  y20 <= 5'd0;
                cell_x <= 5'd0; cell_y <= 5'd0;
                seen_line <= 1'b0;
            end else if (edge_de) begin
                if (!de_prev) begin
                    x20 <= 5'd1;
                    cell_x <= 5'd0;
                    if (seen_line) begin
                        if (y20 == CELL-1) begin
                            y20 <= 5'd0;
                            if (cell_y < GH-1) cell_y <= cell_y + 5'd1;
                        end else begin
                            y20 <= y20 + 5'd1;
                        end
                    end
                    seen_line <= 1'b1;
                end else begin
                    if (x20 == CELL-1) begin
                        x20 <= 5'd0;
                        if (cell_x < GW-1) cell_x <= cell_x + 5'd1;
                    end else begin
                        x20 <= x20 + 5'd1;
                    end
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Edge density grid
    //--------------------------------------------------------------------------
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < NCELL; k = k + 1) cellcnt[k] <= 4'd0;
        end else begin
            if (state == S_IDLE && edge_vs && edge_de && edge_bit) begin
                if (cellcnt[cell_idx] < 4'd15)
                    cellcnt[cell_idx] <= cellcnt[cell_idx] + 4'd1;
            end else if (state == S_CLEAR) begin
                cellcnt[scan_i] <= 4'd0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // bbox dimensions and side-scan indices
    //--------------------------------------------------------------------------
    wire [5:0] bw = {1'b0, gx1} - {1'b0, gx0} + 6'd1;
    wire [5:0] bh = {1'b0, gy1} - {1'b0, gy0} + 6'd1;
    wire [4:0] side_col = gx0 + side_i[4:0];
    wire [4:0] side_row = gy0 + side_i[4:0];
    wire [9:0] i_top  = {gy0, side_col};
    wire [9:0] i_bot  = {gy1, side_col};
    wire [9:0] i_left = {side_row, gx0};
    wire [9:0] i_right= {side_row, gx1};

    //--------------------------------------------------------------------------
    // Frame analysis FSM
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            scan_i <= 10'd0;
            side_i <= 6'd0;
            side_phase <= 1'b0;
            top_cnt <= 6'd0; bot_cnt <= 6'd0;
            left_cnt <= 6'd0; right_cnt <= 6'd0;
            any_active <= 1'b0;
            gx0 <= 5'd31; gx1 <= 5'd0; gy0 <= 5'd23; gy1 <= 5'd0;
            shape_kind <= 2'd0;
            bbox_x0 <= 11'd0; bbox_x1 <= 11'd0;
            bbox_y0 <= 11'd0; bbox_y1 <= 11'd0;
            result_valid <= 1'b0;
        end else begin
            result_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (vs_fall) begin
                        state <= S_ANALYZE;
                        scan_i <= 10'd0;
                        any_active <= 1'b0;
                        gx0 <= 5'd31; gx1 <= 5'd0;
                        gy0 <= 5'd23; gy1 <= 5'd0;
                    end
                end

                S_ANALYZE: begin
                    if (cellcnt[scan_i] > CELL_THRESH) begin
                        active[scan_i] <= 1'b1;
                        any_active <= 1'b1;
                        if (scan_i[4:0] < gx0) gx0 <= scan_i[4:0];
                        if (scan_i[4:0] > gx1) gx1 <= scan_i[4:0];
                        if (scan_i[9:5] < gy0) gy0 <= scan_i[9:5];
                        if (scan_i[9:5] > gy1) gy1 <= scan_i[9:5];
                    end else begin
                        active[scan_i] <= 1'b0;
                    end

                    if (scan_i == NCELL-1) begin
                        if (!any_active && !(cellcnt[scan_i] > CELL_THRESH)) begin
                            shape_kind <= 2'd0;
                            result_valid <= 1'b1;
                            state <= S_CLEAR;
                            scan_i <= 10'd0;
                        end else begin
                            state <= S_SIDES;
                            side_phase <= 1'b0;
                            side_i <= 6'd0;
                            top_cnt <= 6'd0; bot_cnt <= 6'd0;
                            left_cnt <= 6'd0; right_cnt <= 6'd0;
                        end
                    end else begin
                        scan_i <= scan_i + 10'd1;
                    end
                end

                S_SIDES: begin
                    if (side_phase == 1'b0) begin
                        if (active[i_top])   top_cnt  <= top_cnt + 1'b1;
                        if (active[i_bot])   bot_cnt  <= bot_cnt + 1'b1;
                        if (side_i == bw - 1'b1) begin
                            side_phase <= 1'b1;
                            side_i <= 6'd0;
                        end else begin
                            side_i <= side_i + 1'b1;
                        end
                    end else begin
                        if (active[i_left])  left_cnt  <= left_cnt + 1'b1;
                        if (active[i_right]) right_cnt <= right_cnt + 1'b1;
                        if (side_i == bh - 1'b1) begin
                            state <= S_CLASS;
                        end else begin
                            side_i <= side_i + 1'b1;
                        end
                    end
                end

                S_CLASS: begin
                    begin : classify
                        reg [4:0] mx, my;
                        reg [5:0] w, h;
                        reg [2:0] corners, mids, side_hi;
                        reg       top_hi, bot_hi, left_hi, right_hi;
                        reg       aspect_circle, aspect_rect, aspect_tri;
                        reg       c_tl, c_tr, c_bl, c_br;
                        reg       mt, mb, ml, mr;
                        reg       apex_up, apex_down, apex_left, apex_right;
                        reg [9:0] i00, i10, i01, i11, imt, imb, iml, imr;

                        // 6-bit sums: gx0+gx1 can reach 62 on a 32-cell grid
                        mx = ({1'b0, gx0} + {1'b0, gx1}) >> 1;
                        my = ({1'b0, gy0} + {1'b0, gy1}) >> 1;
                        w  = {1'b0, gx1} - {1'b0, gx0} + 6'd1;
                        h  = {1'b0, gy1} - {1'b0, gy0} + 6'd1;

                        i00 = {gy0, gx0}; i10 = {gy0, gx1};
                        i01 = {gy1, gx0}; i11 = {gy1, gx1};
                        imt = {gy0, mx};  imb = {gy1, mx};
                        iml = {my, gx0};  imr = {my, gx1};

                        c_tl = active[i00]; c_tr = active[i10];
                        c_bl = active[i01]; c_br = active[i11];
                        mt = active[imt]; mb = active[imb];
                        ml = active[iml]; mr = active[imr];

                        corners = {2'b00, c_tl} + {2'b00, c_tr} +
                                  {2'b00, c_bl} + {2'b00, c_br};
                        mids    = {2'b00, mt} + {2'b00, mb} +
                                  {2'b00, ml} + {2'b00, mr};

                        top_hi   = ({1'b0, top_cnt}   << 1) >= w;
                        bot_hi   = ({1'b0, bot_cnt}   << 1) >= w;
                        left_hi  = ({1'b0, left_cnt}  << 1) >= h;
                        right_hi = ({1'b0, right_cnt} << 1) >= h;
                        side_hi  = {2'b00, top_hi} + {2'b00, bot_hi} +
                                   {2'b00, left_hi} + {2'b00, right_hi};

                        aspect_circle = (5*w >= 3*h) && (5*h >= 3*w);
                        aspect_rect   = (5*w >= 2*h) && (5*h >= 2*w);
                        aspect_tri    = (4*w >= h) && (4*h >= w);

                        apex_up   = c_bl & c_br & ~c_tl & ~c_tr & mt;
                        apex_down = c_tl & c_tr & ~c_bl & ~c_br & mb;
                        apex_left = c_tr & c_br & ~c_tl & ~c_bl & ml;
                        apex_right= c_tl & c_bl & ~c_tr & ~c_br & mr;

                        dbg_pts <= {c_tl, c_tr, c_bl, c_br, mt, mb, ml, mr};
                        dbg_corners <= corners;
                        dbg_mids <= mids;
                        dbg_side_hi <= side_hi;
                        dbg_apex <= apex_up | apex_down | apex_left | apex_right;

                        if (w < 6'd5 || h < 6'd5) begin
                            shape_kind <= 2'd0;
                        end else if (aspect_rect &&
                                     ((side_hi == 3'd4) ||
                                      (corners >= 3'd3 && side_hi >= 3'd3))) begin
                            shape_kind <= 2'd2;      // rectangle / rounded rectangle
                        end else if (aspect_tri &&
                                     ((corners == 3'd3 && side_hi <= 3'd2) ||
                                      apex_up || apex_down || apex_left || apex_right)) begin
                            shape_kind <= 2'd3;      // triangle
                        end else if (aspect_circle && corners <= 3'd1 &&
                                     mids >= 3'd3 && side_hi <= 3'd2) begin
                            shape_kind <= 2'd1;      // circle
                        end else begin
                            shape_kind <= 2'd0;
                        end

                        bbox_x0 <= {gx0, 4'd0} + {gx0, 2'd0};
                        bbox_x1 <= {gx1, 4'd0} + {gx1, 2'd0} + 11'd19;
                        bbox_y0 <= {gy0, 4'd0} + {gy0, 2'd0};
                        bbox_y1 <= {gy1, 4'd0} + {gy1, 2'd0} + 11'd19;
                        result_valid <= 1'b1;
                    end
                    state <= S_CLEAR;
                    scan_i <= 10'd0;
                end

                S_CLEAR: begin
                    active[scan_i] <= 1'b0;
                    if (scan_i == NCELL-1) state <= S_WAIT;
                    else scan_i <= scan_i + 10'd1;
                end

                S_WAIT: begin
                    if (edge_vs == 1'b1) state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
