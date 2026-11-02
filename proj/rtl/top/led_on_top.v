//==============================================================================
// led_on_top : LED bring-up top for the VF-Ti60F225 board (奥唯思FPGA core
// V1.4 + button board).  Turns LED0..LED5 on and leaves them on.
//
// LED polarity (from the schematic Ti60_F225_Core_V1.4.pdf, sheet
// "BANK 3.3V GPIO"): each LED is wired
//     VDD3V3 -> 4.7K (R16/R18/R19/R21/R22/R24/R25/R27) -> LED D1..D8 -> GPIO
// i.e. the FPGA pin sinks the current, so the LEDs are ACTIVE LOW:
// driving a pin to 0 lights the LED, driving it to 1 turns it off.
//
// Board mapping (schematic + Ti60_Board_引脚定义 V1.0, "BANK 3.3" sheet):
//   led[0] -> LED0 -> GPIOR_25 -> BGA P15
//   led[1] -> LED1 -> GPIOR_22 -> BGA P14
//   led[2] -> LED2 -> GPIOR_28 -> BGA R14
//   led[3] -> LED3 -> GPIOR_21 -> BGA N14
//   led[4] -> LED4 -> GPIOR_24 -> BGA N13
//   led[5] -> LED5 -> GPIOR_27 -> BGA P13
//
// Why the LEDs are clocked instead of tied low: efx_map rejects a design whose
// outputs are pure constants --
//   "[EFX-0010 VERI-ERROR] Post-synthesis netlist has only vcc and gnd nets
//    because all logic is eliminated. Legal, but will cause router to crash."
// So the LED register starts at 6'b111111 (all dark) and shifts a 0 in on the
// on-board 24 MHz crystal.  Six clocks after configuration the register holds
// 6'b000000 and every LED stays on (0.25 us at 24 MHz).
//==============================================================================
module led_on_top (
    input  wire       clk_24m,       // 24 MHz crystal, GPIOL_11 (BGA C5)
    output wire [5:0] led            // LED0..LED5, active low: 0 = on
);

    reg [5:0] led_r = 6'b111111;

    always @(posedge clk_24m) begin
        led_r <= {led_r[4:0], 1'b0};
    end

    assign led = led_r;

endmodule
