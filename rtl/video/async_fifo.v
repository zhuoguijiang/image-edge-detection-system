//==============================================================================
// async_fifo : dual-clock FIFO, gray-coded pointers (Cummings style)
//
// Where it is used in this project
//   The MIPI byte-clock -> pixel-clock crossing already happens *inside*
//   csi_rx (its byte2pixel stage owns a dual-clock FIFO).  This module is the
//   generic version for the levels that still need a real CDC:
//     - pixel-domain producer  -> HDMI/display domain consumer
//     - line buffers for the 3x3 window in the algorithm pipeline
//
// Interface
//   Standard (non-FWFT) mode: pulse rd_en and rd_data is valid on the next
//   rd_clk edge.  This is the form that reliably infers block RAM.
//
// Notes
//   - No reset synchroniser inside: drive *_rst_n from each domain.
//   - full is conservative (registered); wr_en while full is ignored.
//==============================================================================
module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 10          // depth = 2**ADDR_WIDTH
)(
    // write domain
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output reg                   full,

    // read domain
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] rd_data,   // valid the cycle after rd_en
    output reg                   empty
);

    localparam DEPTH = (1 << ADDR_WIDTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    reg  [ADDR_WIDTH:0] wr_bin, wr_gray;
    reg  [ADDR_WIDTH:0] rd_bin, rd_gray;
    reg  [ADDR_WIDTH:0] rd_gray_s1, rd_gray_s2;   // rd -> wr domain
    reg  [ADDR_WIDTH:0] wr_gray_s1, wr_gray_s2;   // wr -> rd domain

    wire wr_do = wr_en & ~full;
    wire rd_do = rd_en & ~empty;

    wire [ADDR_WIDTH:0] wr_bin_next  = wr_bin + {{ADDR_WIDTH{1'b0}}, wr_do};
    wire [ADDR_WIDTH:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    wire [ADDR_WIDTH:0] rd_bin_next  = rd_bin + {{ADDR_WIDTH{1'b0}}, rd_do};
    wire [ADDR_WIDTH:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    // full : write pointer reaches the read pointer with the two MSBs inverted
    wire wr_full_next = (wr_gray_next ==
                        {~rd_gray_s2[ADDR_WIDTH:ADDR_WIDTH-1],
                          rd_gray_s2[ADDR_WIDTH-2:0]});
    // empty : read pointer catches up with the synchronised write pointer
    wire rd_empty_next = (rd_gray_next == wr_gray_s2);

    //--------------------------------------------------------------------------
    // Write domain
    //--------------------------------------------------------------------------
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin  <= {(ADDR_WIDTH+1){1'b0}};
            wr_gray <= {(ADDR_WIDTH+1){1'b0}};
            full    <= 1'b0;
        end else begin
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
            full    <= wr_full_next;
            if (wr_do)
                mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) {rd_gray_s2, rd_gray_s1} <= {(ADDR_WIDTH+1){1'b0}};
        else           {rd_gray_s2, rd_gray_s1} <= {rd_gray_s1, rd_gray};
    end

    //--------------------------------------------------------------------------
    // Read domain
    //--------------------------------------------------------------------------
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin  <= {(ADDR_WIDTH+1){1'b0}};
            rd_gray <= {(ADDR_WIDTH+1){1'b0}};
            empty   <= 1'b1;
            rd_data <= {DATA_WIDTH{1'b0}};
        end else begin
            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
            empty   <= rd_empty_next;
            if (rd_do)
                rd_data <= mem[rd_bin[ADDR_WIDTH-1:0]];
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) {wr_gray_s2, wr_gray_s1} <= {(ADDR_WIDTH+1){1'b0}};
        else           {wr_gray_s2, wr_gray_s1} <= {wr_gray_s1, wr_gray};
    end

endmodule
