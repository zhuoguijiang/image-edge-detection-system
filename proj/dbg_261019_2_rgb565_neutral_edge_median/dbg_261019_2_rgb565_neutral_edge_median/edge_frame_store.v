//==============================================================================
// edge_frame_store : 1-bit 640x480 edge frame buffer
//
//   write : edge pipeline output, addressed by the actual edge-pipeline x/y
//           coordinates. The earlier counter-based implementation could lose
//           alignment if an active-data beat was missing, causing a cumulative
//           horizontal drift across each line.
//   read  : display timing from video_frame_store, 1:1 640x480
//
//   The read side uses the same prefetch scheme as video_frame_store:
//   issue byte 0 in the last two blanking cycles, then issue byte n+1 when
//   the current byte has two pixels left (x[2:0] == 6/7).
//==============================================================================
module edge_frame_store #(
    parameter H_ACTIVE = 640,
    parameter V_ACTIVE = 480,
    parameter H_SYNC   = 96,
    parameter H_BACK   = 48,
    parameter H_BITS   = 11,
    parameter V_BITS   = 11,
    parameter ROW_BYTES = H_ACTIVE / 8,
    parameter MEM_DEPTH = ROW_BYTES * V_ACTIVE,
    parameter MEM_AW   = 16,
    // The Canny window/linking chain reports the detected contour a few
    // source pixels down/right of the luminance transition. These corrections
    // place it back on the visible colour edge.
    parameter ALIGN_X_SUB = 2,
    parameter ALIGN_Y_SUB = 3
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // write side (full-resolution edge pipeline)
    input  wire                  in_bit,
    input  wire                  in_de,
    input  wire                  in_vs,
    input  wire [H_BITS-1:0]     in_x,
    input  wire [V_BITS-1:0]     in_y,

    // read side (display timing from video_frame_store)
    input  wire                  disp_de,
    input  wire [H_BITS-1:0]     disp_hcnt,
    input  wire [H_BITS-1:0]     disp_x,
    input  wire [V_BITS-1:0]     disp_y,

    output wire                  out_bit,
    output wire                  out_valid,
    output wire                  written
);

    localparam [H_BITS-1:0] DE_START = H_SYNC + H_BACK;

    reg [7:0]        byte_acc;
    reg              written_r;
    reg [7:0]        mem [0:MEM_DEPTH-1];

    wire [V_BITS-1:0] wy =
        (in_y >= ALIGN_Y_SUB) ? (in_y - ALIGN_Y_SUB) : {V_BITS{1'b0}};
    wire [H_BITS-1:0] wx =
        (in_x >= ALIGN_X_SUB) ? (in_x - ALIGN_X_SUB) : {H_BITS{1'b0}};
    wire              wr_ok =
        in_de && (in_x >= ALIGN_X_SUB) && (in_y >= ALIGN_Y_SUB) &&
        (wx < H_ACTIVE) && (wy < V_ACTIVE);

    wire [MEM_AW-1:0] wr_row_base =
        ({{(MEM_AW-V_BITS){1'b0}}, wy} << 6) +
        ({{(MEM_AW-V_BITS){1'b0}}, wy} << 4);
    wire [MEM_AW-1:0] wr_addr = wr_row_base + {{(MEM_AW-7){1'b0}}, wx[9:3]};

    assign written = written_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_acc  <= 8'd0;
            written_r <= 1'b0;
        end else if (!in_vs) begin
            byte_acc  <= 8'd0;
        end else if (in_de) begin
            if (wr_ok) begin
                if (wx[2:0] == 3'd0)
                    byte_acc <= {7'd0, in_bit};
                else
                    byte_acc[wx[2:0]] <= in_bit;

                if (wx[2:0] == 3'd7)
                    mem[wr_addr] <= {in_bit, byte_acc[6:0]};
            end

            if ((in_x >= H_ACTIVE - 4) && (in_y >= V_ACTIVE - 4))
                written_r <= 1'b1;
        end
    end

    // simple dual-port RAM: write port above, synchronous read port below
    reg [7:0] rd_data;
    reg [7:0] byte_lat;

    // Issue one cycle earlier than the video_frame_store version: the
    // synchronous read data must be valid at the pre-latch edge.
    wire pre_issue = (disp_hcnt == (DE_START - 3));
    wire pre_latch = (disp_hcnt == (DE_START - 1));
    wire nxt_issue = disp_de & (disp_x[2:0] == 3'd6);
    wire nxt_latch = disp_de & (disp_x[2:0] == 3'd7);

    wire [6:0] byte_idx = (pre_issue | pre_latch) ? 7'd0
                                                  : ({1'b0, disp_x[9:3]} + 1'b1);
    wire [MEM_AW-1:0] rd_row_base =
        ({{(MEM_AW-V_BITS){1'b0}}, disp_y} << 6) +
        ({{(MEM_AW-V_BITS){1'b0}}, disp_y} << 4);
    wire [MEM_AW-1:0] rd_addr = rd_row_base + {{(MEM_AW-7){1'b0}}, byte_idx};
    wire rd_en = pre_issue | nxt_issue;

    always @(posedge clk) begin
        if (rd_en) rd_data <= mem[rd_addr];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) byte_lat <= 8'd0;
        else if (pre_latch | nxt_latch) byte_lat <= rd_data;
    end

    assign out_bit   = byte_lat[disp_x[2:0]];
    assign out_valid = disp_de & written_r;

endmodule
