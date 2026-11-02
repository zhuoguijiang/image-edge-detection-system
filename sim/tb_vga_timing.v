`timescale 1ns / 1ps
//==============================================================================
// tb_vga_timing : black-box self-check of the 640x480@60 timing generator.
// The expected constants below are hard-coded independently of the DUT.
//==============================================================================
module tb_vga_timing;

    reg  clk   = 1'b0;
    reg  rst_n = 1'b0;
    wire hsync, vsync, de;
    wire [9:0] hcnt, vcnt;

    // Expected standard 640x480@60 timing (active-low sync).
    integer E_H_TOTAL = 800, E_V_TOTAL = 525;
    integer E_H_SYNC  = 96,  E_V_SYNC  = 2;
    integer E_H_BACK  = 48,  E_V_BACK  = 33;
    integer E_H_ACT   = 640, E_V_ACT   = 480;

    vga_timing dut (
        .clk(clk), .rst_n(rst_n),
        .hsync(hsync), .vsync(vsync), .de(de),
        .hcnt(hcnt), .vcnt(vcnt), .x(), .y()
    );

    always #20 clk = ~clk;   // 25 MHz pixel clock

    integer errors      = 0;
    integer frames      = 0;
    integer clk_cnt     = 0;
    integer max_hcnt    = 0;
    integer max_vcnt    = 0;
    reg     vsync_prev  = 1'b0;
    integer last_vsync_rise = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            errors      = 0;
            frames      = 0;
            clk_cnt     = 0;
            max_hcnt    = 0;
            max_vcnt    = 0;
            vsync_prev  = 1'b0;
            last_vsync_rise = 0;
        end else begin
            clk_cnt = clk_cnt + 1;

            if (hcnt > max_hcnt) max_hcnt = hcnt;
            if (vcnt > max_vcnt) max_vcnt = vcnt;

            // counters stay within their totals
            if (hcnt >= E_H_TOTAL) begin
                $display("FAIL: hcnt=%0d out of range", hcnt);
                errors = errors + 1;
            end
            if (vcnt >= E_V_TOTAL) begin
                $display("FAIL: vcnt=%0d out of range", vcnt);
                errors = errors + 1;
            end

            // active-low sync: low only during the sync pulse
            if (hsync != (hcnt >= E_H_SYNC)) begin
                $display("FAIL: hsync=%b at hcnt=%0d", hsync, hcnt);
                errors = errors + 1;
            end
            if (vsync != (vcnt >= E_V_SYNC)) begin
                $display("FAIL: vsync=%b at vcnt=%0d", vsync, vcnt);
                errors = errors + 1;
            end

            // de high exactly in the active region
            if (de != ((hcnt >= (E_H_SYNC + E_H_BACK)) && (hcnt < (E_H_SYNC + E_H_BACK + E_H_ACT)) &&
                       (vcnt >= (E_V_SYNC + E_V_BACK)) && (vcnt < (E_V_SYNC + E_V_BACK + E_V_ACT)))) begin
                $display("FAIL: de=%b at hcnt=%0d vcnt=%0d", de, hcnt, vcnt);
                errors = errors + 1;
            end

            // measure frame period between consecutive vsync rising edges
            if (vsync && !vsync_prev) begin
                if (frames > 0) begin
                    if (clk_cnt - last_vsync_rise != E_H_TOTAL * E_V_TOTAL) begin
                        $display("FAIL: frame period=%0d, expected %0d",
                                 clk_cnt - last_vsync_rise, E_H_TOTAL * E_V_TOTAL);
                        errors = errors + 1;
                    end
                end
                last_vsync_rise = clk_cnt;
                frames = frames + 1;
            end
            vsync_prev <= vsync;
        end
    end

    initial begin
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        wait (frames >= 3);   // observe two complete frame periods
        repeat (4) @(posedge clk);
        if (errors == 0 && max_hcnt == E_H_TOTAL-1 && max_vcnt == E_V_TOTAL-1)
            $display("PASS: vga_timing verified (hcnt swept to %0d, vcnt swept to %0d, %0d clocks/frame)",
                     max_hcnt, max_vcnt, E_H_TOTAL * E_V_TOTAL);
        else
            $display("FAIL: %0d error(s), max_hcnt=%0d, max_vcnt=%0d", errors, max_hcnt, max_vcnt);
        $finish;
    end

endmodule
