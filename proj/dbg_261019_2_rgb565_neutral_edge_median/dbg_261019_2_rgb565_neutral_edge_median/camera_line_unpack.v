//==============================================================================
// camera_line_unpack : 64-bit CSI beats -> full 640x480 pixel stream
//
//   The camera delivers 80 beats of eight RAW8 pixels per line.  A beat can
//   arrive in a burst, so a ping-pong line buffer is used instead of trying to
//   unpack in the same cycle.  The two 80x64 banks live in ONE 160x64 simple
//   dual-port RAM (address = bank*80 + beat): 160*64 = 10240 bits = exactly one
//   RAM10.  Keeping them as two separate arrays made Efinity map the storage
//   into LUT/FF logic (~10k FF + 8k LUT), so this single-array form is both
//   smaller and still bit-exact.
//
//     write: one 64-bit beat per in_valid into bank W
//     read : one byte per clock from bank R (640 pixels over 640 clocks)
//     swap : at the falling edge of in_hs, bank W becomes the read bank
//
//   The camera line period (~32 us) is longer than the readout time
//   (640 x 40 ns = 25.6 us), so the second bank is ready before the next line
//   needs it.  This also avoids the one-beat loss seen in the vendor
//   data_unpack block.
//==============================================================================
module camera_line_unpack #(
    parameter H_ACTIVE = 640,
    parameter H_BEATS  = H_ACTIVE / 8,
    parameter H_BITS   = 11,
    parameter V_BITS   = 11
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  in_valid,
    input  wire                  in_hs,
    input  wire                  in_vs,
    input  wire [63:0]           in_data,

    output reg  [7:0]            out_data,
    output reg                   out_valid,
    output reg                   out_de,
    output reg                   out_hs,
    output reg                   out_vs,
    output reg  [H_BITS-1:0]     out_x,
    output reg  [V_BITS-1:0]     out_y
);

    // One simple dual-port RAM: bank 0 at 0..79, bank 1 at 80..159
    reg [63:0] mem [0:2*H_BEATS-1];
    localparam [7:0] BANK_STRIDE = H_BEATS;   // 80

    reg              wr_bank;       // bank currently being written
    reg              rd_bank;       // bank currently being read
    reg              line_ready;
    reg              busy;
    reg              frame_active;
    reg              first_line;
    reg              first_cycle;
    reg              hs_1p;
    reg              line_end_r;
    reg [6:0]        wr_beat;       // 0..79
    reg [6:0]        rd_beat;
    reg [2:0]        rd_byte;
    reg [63:0]       rd_word_r;

    // Synchronous read port: this is what lets Efinity infer RAM10 instead of
    // mapping the two 80x64 banks into LUT/FF logic.
    wire [6:0] rd_beat_next =
        (rd_byte == 3'd7 && rd_beat != H_BEATS - 1) ? (rd_beat + 1'b1) : rd_beat;
    wire [7:0] rd_word_addr = {1'b0, rd_beat_next} +
                              (rd_bank ? BANK_STRIDE : 8'd0);
    wire [7:0] wr_word_addr = {1'b0, wr_beat} +
                              (wr_bank ? BANK_STRIDE : 8'd0);
    always @(posedge clk) begin
        if (in_valid) mem[wr_word_addr] <= in_data;
        rd_word_r <= mem[rd_word_addr];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_bank      <= 1'b0;
            rd_bank      <= 1'b0;
            line_ready   <= 1'b0;
            busy         <= 1'b0;
            frame_active <= 1'b0;
            first_line   <= 1'b1;
            first_cycle  <= 1'b0;
            hs_1p        <= 1'b0;
            line_end_r   <= 1'b0;
            wr_beat      <= 7'd0;
            rd_beat      <= 7'd0;
            rd_byte      <= 3'd0;
            out_data     <= 8'd0;
            out_valid    <= 1'b0;
            out_de       <= 1'b0;
            out_hs       <= 1'b0;
            out_vs       <= 1'b0;
            out_x        <= {H_BITS{1'b0}};
            out_y        <= {V_BITS{1'b0}};
        end else begin
            hs_1p <= in_hs;
            line_end_r <= ~in_hs & hs_1p;

            // -----------------------------------------------------------------
            // Producer: write one beat per valid input cycle.
            // -----------------------------------------------------------------
            if (in_valid) begin
                if (wr_beat != H_BEATS - 1)
                    wr_beat <= wr_beat + 1'b1;
            end

            if (line_end_r) begin
                wr_beat <= 7'd0;
                if (!busy) begin
                    rd_bank    <= wr_bank;
                    line_ready <= 1'b1;
                    wr_bank    <= ~wr_bank;
                end
            end

            // -----------------------------------------------------------------
            // Consumer: one byte per clock from the completed line bank.
            // -----------------------------------------------------------------
            if (line_ready && !busy) begin
                busy      <= 1'b1;
                line_ready <= 1'b0;
                rd_beat   <= 7'd0;
                rd_byte   <= 3'd0;
                out_x     <= {H_BITS{1'b1}};   // first data cycle increments to 0
                out_valid <= 1'b0;
                out_de    <= 1'b0;
                out_hs    <= 1'b1;
                frame_active <= 1'b1;
                first_cycle  <= 1'b1;
                if (!first_line) out_y <= out_y + 1'b1;
                else             first_line <= 1'b0;
            end else if (busy) begin
                if (first_cycle) begin
                    first_cycle <= 1'b0;
                    out_valid   <= 1'b0;
                    out_de      <= 1'b0;
                    out_hs      <= 1'b1;
                end else begin
                    out_data  <= rd_word_r[{rd_byte, 3'b000} +: 8];
                    out_valid <= 1'b1;
                    out_de    <= 1'b1;
                    out_hs    <= 1'b1;
                    out_x     <= out_x + 1'b1;

                    if (rd_byte == 3'd7) begin
                        rd_byte <= 3'd0;
                        if (rd_beat == H_BEATS - 1) begin
                            busy      <= 1'b0;
                        end else begin
                            rd_beat <= rd_beat + 1'b1;
                        end
                    end else begin
                        rd_byte <= rd_byte + 1'b1;
                    end
                end
            end else begin
                out_valid <= 1'b0;
                out_de    <= 1'b0;
                out_hs    <= 1'b0;
            end

            if (~in_vs && !busy && !line_ready) begin
                frame_active <= 1'b0;
                first_line   <= 1'b1;
                out_y        <= {V_BITS{1'b0}};
            end
            out_vs <= frame_active;
        end
    end

endmodule
