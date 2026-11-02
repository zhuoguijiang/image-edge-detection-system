//==============================================================================
// tb_dbg_led_bank : self-checking test for rtl/dbg/dbg_led_bank.v
//
//   Verifies the LED contract of the camera-debug build:
//     * the board LEDs are ACTIVE LOW:  led == ~{dbg_fault_pix, dbg_fault_ctrl}
//     * each "fault" LED lights exactly when its fault happens
//     * sticky flags stay set, cam_alive times out, LED6 means
//       "data arrived once, then went away"
//
//   run:
//     scripts\sim.ps1 tb_dbg_led_bank rtl/dbg/dbg_led_bank.v sim/tb_dbg_led_bank.v
//==============================================================================
`timescale 1ns/1ps

module tb_dbg_led_bank;

    // small timeout so the cam_alive test stays short
    localparam [20:0] TIMEOUT = 21'd16;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        csi_valid = 1'b0;
    reg        csi_hsync = 1'b0;
    reg        csi_vsync = 1'b0;
    reg  [5:0] csi_datatype = 6'h2A;
    reg        pix_valid = 1'b0;
    reg        capture_ovf = 1'b0;
    reg        sys_pll_lock = 1'b0;
    reg        i2c_done = 1'b0;
    reg        i2c_nack = 1'b0;

    wire       cam_alive;
    wire [7:0] led;
    wire [4:0] dbg_fault_pix;
    wire [2:0] dbg_fault_ctrl;
    wire [4:0] dbg_sticky;

    integer errors = 0;

    dbg_led_bank #(.CAM_ALIVE_TIMEOUT(TIMEOUT)) dut (
        .clk(clk), .rst_n(rst_n),
        .csi_valid(csi_valid), .csi_hsync(csi_hsync), .csi_vsync(csi_vsync),
        .csi_datatype(csi_datatype), .pix_valid(pix_valid),
        .capture_ovf(capture_ovf),
        .sys_pll_lock(sys_pll_lock), .i2c_done(i2c_done), .i2c_nack(i2c_nack),
        .cam_alive(cam_alive), .led(led),
        .dbg_fault_pix(dbg_fault_pix), .dbg_fault_ctrl(dbg_fault_ctrl),
        .dbg_sticky(dbg_sticky)
    );

    always #10 clk = ~clk;                  // 50 MHz is enough for logic checks

    wire [7:0] fault = {dbg_fault_pix, dbg_fault_ctrl};

    // One LED: expect_fault=1 -> the fault flag must be 1 AND the pin must be
    // LOW (lit).  This checks the data and the active-low polarity together.
    task check_led;
        input [2:0] idx;
        input       expect_fault;
        input [3:0] step;
        begin
            if (fault[idx] !== expect_fault || led[idx] !== ~expect_fault) begin
                $display("FAIL  step %0d : LED%0d should be %0s (fault=%b led=%b)",
                         step, idx, expect_fault ? "LIT" : "dark",
                         fault[idx], led[idx]);
                errors = errors + 1;
            end else begin
                $display("ok    step %0d : LED%0d %0s", step, idx,
                         expect_fault ? "lit" : "dark");
            end
        end
    endtask

    task check_led_vec;
        input [7:0] expect_led;
        input [3:0] step;
        begin
            if (led !== expect_led) begin
                $display("FAIL  step %0d : led=%b expected %b (fault=%b)",
                         step, led, expect_led, fault);
                errors = errors + 1;
            end else begin
                $display("ok    step %0d : led=%b", step, led);
            end
        end
    endtask

    task pulse_csi_valid;
        begin
            @(negedge clk); csi_valid = 1'b1;
            @(negedge clk); csi_valid = 1'b0;
        end
    endtask

    initial begin
        $display("=== tb_dbg_led_bank ===");

        //------------------------------------------------------------ step 0
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // nothing is up yet: LED0 (PLL), LED1 (i2c), LED3/4/5 (never seen) lit
        check_led(3'd0, 1'b1, 4'd0);
        check_led(3'd1, 1'b1, 4'd0);
        check_led(3'd2, 1'b0, 4'd0);
        check_led(3'd3, 1'b1, 4'd0);
        check_led(3'd4, 1'b1, 4'd0);
        check_led(3'd5, 1'b1, 4'd0);
        check_led(3'd6, 1'b0, 4'd0);
        check_led(3'd7, 1'b0, 4'd0);
        // fault = 00111_011 (LED0,1,3,4,5 lit) -> led = ~fault
        check_led_vec(8'b1100_0100, 4'd0);

        //------------------------------------------------------------ step 1
        @(negedge clk) sys_pll_lock = 1'b1;
        @(negedge clk);
        check_led(3'd0, 1'b0, 4'd1);

        //------------------------------------------------------------ step 2
        @(negedge clk) i2c_done = 1'b1;
        @(negedge clk);
        check_led(3'd1, 1'b0, 4'd2);

        //------------------------------------------------------------ step 3
        // i2c_nack is latched by the I2C master itself (i2c_any_nack, see
        // tb_i2c_master), so here it simply stays asserted: LED2 follows it.
        @(negedge clk) i2c_nack = 1'b1;
        @(negedge clk);
        check_led(3'd2, 1'b1, 4'd3);

        //------------------------------------------------------------ step 4
        @(negedge clk) csi_datatype = 6'h2A;   // RAW8: no fault
        @(negedge clk);
        pulse_csi_valid;
        check_led(3'd3, 1'b0, 4'd4);
        if (dbg_sticky[4] !== 1'b1) begin
            $display("FAIL  step 4 : sticky seen_csi_valid not set");
            errors = errors + 1;
        end
        check_led(3'd6, 1'b0, 4'd4);           // data present -> LED6 dark

        //------------------------------------------------------------ step 5
        @(negedge clk) csi_hsync = 1'b1;
        @(negedge clk) csi_hsync = 1'b0;
        @(negedge clk) csi_vsync = 1'b1;
        @(negedge clk) csi_vsync = 1'b0;
        @(negedge clk);
        check_led(3'd4, 1'b0, 4'd5);

        //------------------------------------------------------------ step 6
        @(negedge clk) pix_valid = 1'b1;
        @(negedge clk) pix_valid = 1'b0;
        @(negedge clk);
        check_led(3'd5, 1'b0, 4'd6);

        //------------------------------------------------------------ step 7
        // wrong data type (RAW10 = 0x2B) must latch LED7
        @(negedge clk) csi_datatype = 6'h2B;
        pulse_csi_valid;
        @(negedge clk) csi_datatype = 6'h2A;
        @(negedge clk);
        check_led(3'd7, 1'b1, 4'd7);
        // fault = 1000_0100 (LED2 + LED7 lit) -> led = ~fault
        check_led_vec(8'b0111_1011, 4'd7);

        //------------------------------------------------------------ step 8
        // stream disappears -> cam_alive times out -> LED6 lights
        repeat (TIMEOUT + 3) @(negedge clk);
        check_led(3'd6, 1'b1, 4'd8);
        if (cam_alive !== 1'b0) begin
            $display("FAIL  step 8 : cam_alive should have timed out");
            errors = errors + 1;
        end

        //------------------------------------------------------------ step 9
        pulse_csi_valid;
        check_led(3'd6, 1'b0, 4'd9);           // data back -> LED6 clears

        //----------------------------------------------------------- step 10
        @(negedge clk) capture_ovf = 1'b1;
        @(negedge clk) capture_ovf = 1'b0;
        @(negedge clk);
        check_led(3'd7, 1'b1, 4'd10);

        //----------------------------------------------------------- step 11
        // the debug vector split relies on this invariant:
        // led must always be exactly the inverted fault vector
        check_led_vec(~{dbg_fault_pix, dbg_fault_ctrl}, 4'd11);

        $display("");
        if (errors == 0) $display("TB_DBG_LED_BANK: PASS");
        else             $display("TB_DBG_LED_BANK: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL  timeout");
        $finish;
    end

endmodule
