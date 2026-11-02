//==============================================================================
// key_debounce : push-button debouncer with press / release pulses.
//
//   key_out   follows key_in only after CNT_MAX stable cycles
//   press     one-clk pulse on a debounced press   (rising edge)
//   released  one-clk pulse on a debounced release (falling edge)
//             named "released" because `release` is a reserved word in
//             SystemVerilog and Efinity compiles this design in sv_09 mode
//
// Default: 20 ms at 24 MHz -> 480_000 cycles.
//==============================================================================
module key_debounce #(
    parameter CNT_W    = 20,
    parameter CNT_MAX  = 480_000,
    parameter PRESS_LOW = 1'b1          // 1 = button pulls the input low
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_in,
    output reg  key_out,
    output reg  press,
    output reg  released
);

    wire key_sync = PRESS_LOW ? ~key_in : key_in;

    reg              key_sync_1p;
    reg [CNT_W-1:0]  cnt;
    reg              stable;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_sync_1p <= 1'b0;
            cnt         <= {CNT_W{1'b0}};
            stable      <= 1'b0;
            key_out     <= 1'b0;
            press       <= 1'b0;
            released    <= 1'b0;
        end else begin
            key_sync_1p <= key_sync;
            press       <= 1'b0;
            released    <= 1'b0;

            if (key_sync != key_sync_1p) begin
                cnt <= {CNT_W{1'b0}};        // input moved : restart the timer
            end else if (cnt < CNT_MAX[CNT_W-1:0]) begin
                cnt <= cnt + 1'b1;
            end

            stable <= (cnt == CNT_MAX[CNT_W-1:0]);

            if (stable && (key_out != key_sync)) begin
                key_out <= key_sync;
                press   <= key_sync;
                released <= ~key_sync;
            end
        end
    end

endmodule
