//==============================================================================
// tb_video_frame_store : self-checking test for
//                        proj/dbg_20261012_03/video_frame_store.v
//
//   The camera is modelled as a frame of V_LINES = 1112 lines x 640 px.
//   Camera line L carries, at camera pixel p, the value (p + L) mod 256, so
//   every camera pixel is a traceable tag: the display pixel at (x,y) must
//   show (x - (x mod 2) + Lk) mod 256, where Lk is the camera line that wrote
//   stored row k = y/2.
//
//   The test therefore needs no model of *which* camera lines the line DDA
//   decides to keep - it records that from the DUT's own writes - and it
//   checks both directions of the frame buffer:
//
//     write side
//       * all 240 stored rows are written, 40 words = 80 beats each
//       * the camera line recorded for row k increases with k, spacing
//         V_LINES/SH = 4.63 lines (3..6), no row left stale
//     read side (camera quiet, buffer frozen)
//       * all 480 display rows are seen (each twice -> x2 vertical upscale)
//       * EVERY active pixel equals the tag of the camera line that wrote its
//         stored row: catches wrong buffer addressing (aliasing), wrong word
//         packing, wrong byte selection on read, stale rows
//
//   run (from the repo root):
//     scripts\sim.ps1 tb_video_frame_store proj\dbg_20261012_03\video_frame_store.v `
//                     proj\dbg_20261012_03\vga_timing.v sim\tb_video_frame_store.v
//
//   (the previous, weaker version of this test - it modelled the line DDA by
//    reproducing the same recurrence, so a one-line phase difference made it
//    report false failures - is kept next to this file as
//    sim\tb_video_frame_store.v.r1)
//==============================================================================
`timescale 1ns/1ps

module tb_video_frame_store;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         in_valid = 1'b0;
    reg  [63:0] in_data = 64'd0;
    reg         in_line_act = 1'b0;
    reg         in_frame_act = 1'b0;

    wire [7:0]  pix_data;
    wire        pix_valid, pix_de, pix_hsync, pix_vsync;
    wire [10:0] pix_x, pix_y;
    wire        line_late, capture_ovf, buf_written;

    integer errors = 0;

    localparam integer V_LINES = 1112;      // real SC2210 frame length (VTS)
    localparam integer SH_ROWS = 240;       // stored rows
    localparam integer BEATS   = 80;        // 640 px / 8 px per 64-bit beat
    localparam integer WORDS   = 40;        // 64-bit buffer words per stored row

    video_frame_store dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_data(in_data),
        .in_line_act(in_line_act), .in_frame_act(in_frame_act),
        .pix_data(pix_data), .pix_valid(pix_valid), .pix_de(pix_de),
        .pix_hsync(pix_hsync), .pix_vsync(pix_vsync),
        .pix_x(pix_x), .pix_y(pix_y),
        .line_late(line_late), .capture_ovf(capture_ovf),
        .buf_written(buf_written)
    );

    always #20 clk = ~clk;          // 25 MHz pixel clock

    //--------------------------------------------------------------------------
    // camera model
    //--------------------------------------------------------------------------
    integer cur_line = 0;           // camera line currently being sent

    task send_line;
        input integer l;
        integer b, j;
        reg [7:0] byte_v;
        begin
            cur_line = l;
            @(negedge clk) in_line_act = 1'b1;      // rising edge -> line_start
            for (b = 0; b < BEATS; b = b + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                for (j = 0; j < 8; j = j + 1) begin
                    byte_v = (b * 8 + j + l) % 256;
                    in_data[j*8 +: 8] = byte_v;
                end
            end
            @(negedge clk) in_valid = 1'b0;
            @(negedge clk) in_line_act = 1'b0;      // falling edge -> line_end
            repeat (4) @(negedge clk);
        end
    endtask

    task send_frame;
        integer n;
        begin
            @(negedge clk) in_frame_act = 1'b1;     // rising edge -> new frame
            repeat (8) @(negedge clk);
            for (n = 0; n < V_LINES; n = n + 1) send_line(n);
            @(negedge clk) in_frame_act = 1'b0;
            repeat (16) @(negedge clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // write-side accounting : which camera line landed in which stored row?
    //--------------------------------------------------------------------------
    reg       wcnt_en = 1'b0;
    integer   wrow_line [0:SH_ROWS-1];
    integer   wrow_cnt  [0:SH_ROWS-1];
    integer   wtotal = 0;
    integer   k;

    always @(posedge clk) begin
        if (wcnt_en && dut.wr_en) begin
            wrow_line[dut.wr_row] = cur_line;
            wrow_cnt [dut.wr_row] = wrow_cnt[dut.wr_row] + 1;
            wtotal = wtotal + 1;
        end
    end

    //--------------------------------------------------------------------------
    // read-side check : every active pixel against the recorded tag
    //--------------------------------------------------------------------------
    reg       dchk_en = 1'b0;
    integer   dseen = 0;
    integer   dmis = 0;
    integer   kk;
    reg [7:0] exp_v;
    reg       drow_seen [0:479];
    integer   drows = 0;

    always @(posedge clk) begin
        if (dchk_en && pix_de) begin
            kk = pix_y / 2;
            exp_v = (pix_x - (pix_x % 2) + wrow_line[kk]) % 256;
            dseen = dseen + 1;
            if (dmis < 10 && (pix_data !== exp_v)) begin
                $display("      D-MIS x=%0d y=%0d got %0d want %0d (row %0d <- cam line %0d)",
                         pix_x, pix_y, pix_data, exp_v, kk, wrow_line[kk]);
                dmis = dmis + 1;
            end
            if (!drow_seen[pix_y]) begin
                drow_seen[pix_y] = 1'b1;
                drows = drows + 1;
            end
        end
    end

    initial begin : init_arrays
        for (k = 0; k < SH_ROWS; k = k + 1) begin
            wrow_line[k] = -1;
            wrow_cnt [k] = 0;
        end
        for (k = 0; k < 480; k = k + 1) drow_seen[k] = 1'b0;
    end

    //--------------------------------------------------------------------------
    // main
    //--------------------------------------------------------------------------
    integer i, miss, gapbad, orderbad, cntbad, prev, d;

    initial begin
        $display("=== tb_video_frame_store ===");
        repeat (8) @(negedge clk);
        rst_n = 1'b1;

        send_frame();               // frame 1 : teaches V_last (may be partial)
        wcnt_en = 1'b1;             // frame 2 is the one that is checked
        send_frame();
        wcnt_en = 1'b0;

        // ---- write side --------------------------------------------------
        miss = 0; cntbad = 0;
        for (i = 0; i < SH_ROWS; i = i + 1) begin
            if (wrow_cnt[i] == 0) begin
                miss = miss + 1;
                if (miss <= 6) $display("      W-MISS stored row %0d never written", i);
            end else if (wrow_cnt[i] != WORDS) begin
                cntbad = cntbad + 1;
                if (cntbad <= 6)
                    $display("      W-CNT  stored row %0d has %0d writes (expect %0d)",
                             i, wrow_cnt[i], WORDS);
            end
        end
        $display("info  frame-2 writes: %0d beats (expect %0d)",
                 wtotal, SH_ROWS * WORDS);
        if (wtotal != SH_ROWS * WORDS) begin
            $display("FAIL  write beat count wrong");
            errors = errors + 1;
        end
        if (miss != 0) begin
            $display("FAIL  %0d stored rows never written", miss);
            errors = errors + 1;
        end else if (cntbad != 0) begin
            $display("FAIL  %0d stored rows have the wrong word count", cntbad);
            errors = errors + 1;
        end else $display("ok    all %0d rows written, %0d words each", SH_ROWS, WORDS);

        // ---- line order / spacing ---------------------------------------
        orderbad = 0; gapbad = 0; prev = -1;
        for (i = 0; i < SH_ROWS; i = i + 1) begin
            if (wrow_line[i] <= prev) begin
                orderbad = orderbad + 1;
                if (orderbad <= 6)
                    $display("      W-ORDER row %0d <- cam line %0d after %0d",
                             i, wrow_line[i], prev);
            end
            if (i > 0) begin
                d = wrow_line[i] - wrow_line[i-1];
                if ((d < 3) || (d > 6)) begin
                    gapbad = gapbad + 1;
                    if (gapbad <= 6)
                        $display("      W-GAP   rows %0d..%0d <- cam lines %0d..%0d (gap %0d)",
                                 i-1, i, wrow_line[i-1], wrow_line[i], d);
                end
            end
            prev = wrow_line[i];
        end
        if (orderbad != 0 || gapbad != 0) begin
            $display("FAIL  line DDA out of order (%0d) / bad spacing (%0d)",
                     orderbad, gapbad);
            errors = errors + 1;
        end else
            $display("ok    rows keep the camera lines in order (first gap %0d, ideal %0d/240 lines)",
                     wrow_line[1]-wrow_line[0], V_LINES);

        // ---- read side : camera quiet from here on ----------------------
        repeat (1000) @(negedge clk);
        dchk_en = 1'b1;
        repeat (500_000) @(negedge clk);        // ~20 ms = 1.2 display frames
        dchk_en = 1'b0;

        $display("info  display pixels checked: %0d, distinct rows: %0d",
                 dseen, drows);
        if (dseen < 307_200) begin      // at least one full 640x480 frame
            $display("FAIL  too few display pixels checked");
            errors = errors + 1;
        end
        if (drows != 480) begin
            $display("FAIL  only %0d of 480 display rows were seen", drows);
            errors = errors + 1;
        end else $display("ok    all 480 display rows seen");
        if (dmis != 0) begin
            $display("FAIL  %0d display pixels carry the wrong value", dmis);
            errors = errors + 1;
        end else
            $display("ok    every display pixel matches the camera tag of its stored row");

        $display("");
        if (errors == 0) $display("TB_VIDEO_FRAME_STORE: PASS");
        else             $display("TB_VIDEO_FRAME_STORE: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #400_000_000;       // 400 ms watchdog
        $display("FAIL  timeout");
        $finish;
    end

endmodule
