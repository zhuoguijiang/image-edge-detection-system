//==============================================================================
// line_buffer_3x3 : two line buffers + 3x3 sliding window.
//
// Window centre is (dout_x, dout_y); the 9 outputs are
//   rows [dout_y-1 .. dout_y+1] x cols [dout_x-1 .. dout_x+1]
// i.e. w00 is top-left, w11 is the centre, w22 is bottom-right.
// dout_valid marks pixels whose full window lies inside the frame
// (input columns >= 2 and rows >= 2).
//
// LINE BUFFER STRUCTURE
//   The two line stores are single arrays with one write port and one
//   synchronous read port - the only structure Efinity reliably infers as
//   block RAM.  A combinational (asynchronous) read gets mapped into LUT/FF
//   logic instead (~10k FF per line at 640 wide - EFX-0657).
//   The read address is issued one cycle early (rd_ptr = ptr + 1) so the
//   registered read data lands on the current column, i.e. q1 is exactly one
//   line old and q2 two lines old, with no extra pipeline latency.
//==============================================================================
module line_buffer_3x3 #(
    parameter WIDTH = 640,
    parameter DW    = 8
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire [DW-1:0] din,
    input  wire          din_valid,
    input  wire          din_vsync,
    output wire [DW-1:0] w00, w01, w02,
    output wire [DW-1:0] w10, w11, w12,
    output wire [DW-1:0] w20, w21, w22,
    output reg           dout_valid,
    output reg  [15:0]   dout_x,
    output reg  [15:0]   dout_y
);

    reg [DW-1:0] lb1 [0:WIDTH-1];
    reg [DW-1:0] lb2 [0:WIDTH-1];
    reg [DW-1:0] q1, q2;              // 1 line / 2 lines ago (synchronous read)
    reg [15:0]   ptr;
    reg [15:0]   x_in, y_in;

    // Read address issued one cycle before the data is needed: it must be the
    // column of the *next* valid pixel.  While a valid pixel is being written
    // that is ptr+1; during the blanking gap ptr is frozen, so the next valid
    // pixel (the first of the new line) is at ptr itself.
    wire [15:0] nxt_ptr = (ptr == WIDTH-1) ? 16'd0 : ptr + 16'd1;
    wire [15:0] rd_ptr  = din_valid ? nxt_ptr : ptr;

    // simple dual-port RAM: synchronous read -> block RAM
    always @(posedge clk) begin
        if (din_valid) begin
            lb1[ptr] <= din;
            lb2[ptr] <= q1;
        end
        q1 <= lb1[rd_ptr];
        q2 <= lb2[rd_ptr];
    end

    reg [DW-1:0] r2d1, r2d2;   // current row, delayed 1 / 2 pixels
    reg [DW-1:0] r1d1, r1d2;   // 1 line ago, delayed 1 / 2 pixels
    reg [DW-1:0] r0d1, r0d2;   // 2 lines ago, delayed 1 / 2 pixels

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr <= 16'd0; x_in <= 16'd0; y_in <= 16'd0;
            r2d1 <= 0; r2d2 <= 0; r1d1 <= 0; r1d2 <= 0; r0d1 <= 0; r0d2 <= 0;
        end else if (din_vsync) begin
            ptr <= 16'd0; x_in <= 16'd0; y_in <= 16'd0;
            r2d1 <= 0; r2d2 <= 0; r1d1 <= 0; r1d2 <= 0; r0d1 <= 0; r0d2 <= 0;
        end else if (din_valid) begin
            ptr <= (ptr == WIDTH-1) ? 16'd0 : ptr + 16'd1;
            r2d1 <= din;  r2d2 <= r2d1;
            r1d1 <= q1;   r1d2 <= r1d1;
            r0d1 <= q2;   r0d2 <= r0d1;
            if (x_in == WIDTH-1) begin
                x_in <= 16'd0;
                y_in <= y_in + 16'd1;
            end else begin
                x_in <= x_in + 16'd1;
            end
        end
    end

    // combinational window, centred at (x_in-1, y_in-1)
    wire [DW-1:0] cw00 = r0d2, cw01 = r0d1, cw02 = q2;
    wire [DW-1:0] cw10 = r1d2, cw11 = r1d1, cw12 = q1;
    wire [DW-1:0] cw20 = r2d2, cw21 = r2d1, cw22 = din;

    reg [DW-1:0] w00_r, w01_r, w02_r, w10_r, w11_r, w12_r, w20_r, w21_r, w22_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w00_r <= 0; w01_r <= 0; w02_r <= 0;
            w10_r <= 0; w11_r <= 0; w12_r <= 0;
            w20_r <= 0; w21_r <= 0; w22_r <= 0;
            dout_valid <= 1'b0; dout_x <= 16'd0; dout_y <= 16'd0;
        end else if (din_vsync) begin
            dout_valid <= 1'b0;
        end else begin
            w00_r <= cw00; w01_r <= cw01; w02_r <= cw02;
            w10_r <= cw10; w11_r <= cw11; w12_r <= cw12;
            w20_r <= cw20; w21_r <= cw21; w22_r <= cw22;
            dout_valid <= din_valid && (x_in >= 16'd2) && (y_in >= 16'd2);
            dout_x <= (x_in >= 16'd1) ? (x_in - 16'd1) : 16'd0;
            dout_y <= (y_in >= 16'd1) ? (y_in - 16'd1) : 16'd0;
        end
    end

    assign w00 = w00_r; assign w01 = w01_r; assign w02 = w02_r;
    assign w10 = w10_r; assign w11 = w11_r; assign w12 = w12_r;
    assign w20 = w20_r; assign w21 = w21_r; assign w22 = w22_r;

endmodule
