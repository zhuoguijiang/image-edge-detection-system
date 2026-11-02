//==============================================================================
// camera_pixel_unpack : csi_rx 64-bit RAW8 beats -> one 8-bit pixel per clock
//
// The csi_rx IP delivers eight RAW8 pixels per pixel_data_valid beat.  The
// vendor data_unpack block (copied from the Efinity CSI-2 example) serialises
// the beat and keeps the line/frame timing aligned.  The small counters below
// are the same ones used by the vendor example: in_x/in_y are beat/line
// coordinates, not pixel coordinates.
//==============================================================================
module camera_pixel_unpack #(
    parameter PIXEL_BIT = 8,
    parameter PACK_BIT  = 64,
    parameter FIFO_WIDTH = 11
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  in_valid,
    input  wire                  in_hs,
    input  wire                  in_vs,
    input  wire [PACK_BIT-1:0]   in_data,

    output wire [PIXEL_BIT-1:0]  out_data,
    output wire                  out_valid,
    output wire                  out_de,
    output wire                  out_hs,
    output wire                  out_vs,
    output wire [FIFO_WIDTH-1:0] out_x,
    output wire [FIFO_WIDTH-1:0] out_y
);

    reg [FIFO_WIDTH-1:0] x_active;
    reg [FIFO_WIDTH-1:0] y_active;
    reg                  hs_1p;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_active <= {FIFO_WIDTH{1'b0}};
            y_active <= {FIFO_WIDTH{1'b0}};
            hs_1p    <= 1'b0;
        end else begin
            hs_1p <= in_hs;

            if (in_valid)
                x_active <= x_active + 1'b1;
            else if (!in_hs)
                x_active <= {FIFO_WIDTH{1'b0}};

            if (!in_hs && hs_1p)
                y_active <= y_active + 1'b1;
            else if (!in_vs)
                y_active <= {FIFO_WIDTH{1'b0}};
        end
    end

    data_unpack #(
        .PIXEL_BIT(PIXEL_BIT),
        .PACK_BIT(PACK_BIT),
        .FIFO_WIDTH(FIFO_WIDTH)
    ) u_unpack (
        .in_pclk  (clk),
        .in_rstn  (rst_n),
        .in_x     (x_active),
        .in_y     (y_active),
        .in_valid (in_valid),
        .in_de    (in_hs),
        .in_hs    (in_hs),
        .in_vs    (in_vs),
        .in_data  (in_data),
        .out_x    (out_x),
        .out_y    (out_y),
        .out_valid(out_valid),
        .out_de   (out_de),
        .out_hs   (out_hs),
        .out_vs   (out_vs),
        .out_data (out_data)
    );

endmodule
