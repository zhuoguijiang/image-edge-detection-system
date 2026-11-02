`timescale 1ns / 1ps
//==============================================================================
// tb_i2c_master : verify the I2C write protocol of i2c_timing_ctrl_16bit.
// Two 32-bit config entries are driven; the monitor captures the 4 bytes
// {ID, REG_HI, REG_LO, DATA} sent per entry and compares them.
//
// Also checks the sticky NACK flag (i2c_any_nack) that drives debug LED2:
//   vvp sim/tb_i2c_master.vvp              -> no slave  : NACK must latch
//   vvp sim/tb_i2c_master.vvp +SLAVE=1     -> slave ACKs: flag must stay 0
//==============================================================================
module tb_i2c_master;

    reg  clk   = 1'b0;
    reg  rst_n = 1'b0;
    wire i2c_sclk;
    wire i2c_sdat_IN;
    wire i2c_sdat_OUT;
    wire i2c_sdat_OE;
    reg  [8:0]  i2c_config_size;
    wire [8:0]  i2c_config_index;
    reg  [31:0] i2c_config_data;
    wire        i2c_config_done;
    wire        i2c_any_nack;
    wire [15:0] i2c_rdata;

    // slave present?  -1 when the sensor answers every byte (ACK = SDA low),
    // 0 when the sensor is absent / not answering (SDA stays high = NACK)
    integer slave_present = 0;

    i2c_timing_ctrl_16bit #(
        .CLK_FREQ(1_000000),  // 1 MHz (fast simulation)
        .I2C_FREQ(100_000)    // 100 kHz I2C
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i2c_sclk(i2c_sclk),
        .i2c_sdat_IN(i2c_sdat_IN),
        .i2c_sdat_OUT(i2c_sdat_OUT),
        .i2c_sdat_OE(i2c_sdat_OE),
        .i2c_config_size(i2c_config_size),
        .i2c_config_index(i2c_config_index),
        .i2c_config_data(i2c_config_data),
        .i2c_config_done(i2c_config_done),
        .i2c_any_nack(i2c_any_nack),
        .i2c_rdata(i2c_rdata)
    );

    // SDA: OE is active-high (1 = master drives OUT, 0 = released).
    // When released, a present slave pulls SDA low (ACK); an absent one lets
    // the pull-up keep it high (NACK).
    assign i2c_sdat_IN = (i2c_sdat_OE == 1'b1) ? i2c_sdat_OUT
                                               : (slave_present ? 1'b0 : 1'b1);

    always #500 clk = ~clk;   // 1 MHz

    // Two config entries: {ID, REG_HI, REG_LO, DATA}
    always @(*) begin
        case (i2c_config_index)
            9'd0 : i2c_config_data = {8'h78, 8'h01, 8'h03, 8'h01}; // reg 0x0103 = 0x01
            9'd1 : i2c_config_data = {8'h78, 8'h01, 8'h00, 8'h00}; // reg 0x0100 = 0x00
            default : i2c_config_data = 32'h0;
        endcase
    end

    // Byte-capture monitor: sample SDA on SCL rising while master drives.
    reg  [7:0] rx_shift = 8'd0;
    reg  [2:0] rx_bit   = 3'd0;
    integer    byte_idx = 0;
    reg  [7:0] captured [0:7];
    integer    scl_rise_total = 0;
    integer    scl_rise_oe1   = 0;

    always @(posedge i2c_sclk) begin
        scl_rise_total = scl_rise_total + 1;
        if (i2c_sdat_OE == 1'b1) begin
            scl_rise_oe1 = scl_rise_oe1 + 1;
            rx_shift = {rx_shift[6:0], i2c_sdat_OUT};
            rx_bit = rx_bit + 1'b1;
            if (rx_bit == 3'd0 && byte_idx < 8) begin
                captured[byte_idx] = rx_shift;
                byte_idx = byte_idx + 1;
            end
        end
    end

    integer errors = 0;
    reg     done_flag = 1'b0;

    initial begin
        slave_present = 0;
        if (!$value$plusargs("SLAVE=%d", slave_present)) slave_present = 0;
        $display("=== tb_i2c_master (slave_present=%0d) ===", slave_present);

        i2c_config_size = 9'd2;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        wait (i2c_config_done);
        done_flag = 1'b1;
        #2000;  // settle the last captures

        if (byte_idx != 8) begin
            $display("FAIL: captured %0d bytes (scl_rise_total=%0d, scl_rise_oe1=%0d), expected 8",
                     byte_idx, scl_rise_total, scl_rise_oe1);
            errors = errors + 1;
        end else begin
            if (captured[0] !== 8'h78 || captured[1] !== 8'h01 ||
                captured[2] !== 8'h03 || captured[3] !== 8'h01 ||
                captured[4] !== 8'h78 || captured[5] !== 8'h01 ||
                captured[6] !== 8'h00 || captured[7] !== 8'h00) begin
                $display("FAIL: byte sequence mismatch");
                $display("  got: %h %h %h %h | %h %h %h %h",
                    captured[0], captured[1], captured[2], captured[3],
                    captured[4], captured[5], captured[6], captured[7]);
                errors = errors + 1;
            end
        end

        if (!i2c_config_done) begin
            $display("FAIL: i2c_config_done never asserted");
            errors = errors + 1;
        end

        // sticky NACK flag: 1 when the slave never answers, 0 when it ACKs
        if (slave_present) begin
            if (i2c_any_nack !== 1'b0) begin
                $display("FAIL: i2c_any_nack set although the slave ACKed");
                errors = errors + 1;
            end else begin
                $display("ok: slave ACKed -> i2c_any_nack = 0");
            end
        end else begin
            if (i2c_any_nack !== 1'b1) begin
                $display("FAIL: i2c_any_nack not latched although no slave answered");
                errors = errors + 1;
            end else begin
                $display("ok: no slave -> i2c_any_nack = 1 (sticky)");
            end
        end

        if (errors == 0)
            $display("PASS: i2c_master sent 2 config entries correctly (slave_present=%0d)",
                     slave_present);
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

    // Watchdog: fail instead of hanging if i2c_config_done never asserts.
    initial begin
        #10_000_000;   // 10 ms timeout
        if (!done_flag) begin
            $display("FAIL: timeout waiting for i2c_config_done");
            $finish;
        end
    end

endmodule
