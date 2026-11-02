//==============================================================================
// video_delay : pipelines a frozen pixel stream by STAGES cycles.
//
// WHY
//   The pixel-stream contract says the algorithm MUST keep de/hs/vs/valid
//   aligned with data.  When A-group reports its pipeline depth, B-group sets
//   STAGES here and the un-processed branch arrives at the split MUX with the
//   exact same latency as the processed branch.
//==============================================================================
module video_delay #(
    parameter STAGES = 1,               // >= 1
    parameter X_BITS = 11,
    parameter Y_BITS = 11
)(
    input  wire                clk,
    input  wire                rst_n,

    input  wire [7:0]          in_data,
    input  wire                in_valid,
    input  wire                in_de,
    input  wire                in_hs,
    input  wire                in_vs,
    input  wire [X_BITS-1:0]   in_x,
    input  wire [Y_BITS-1:0]   in_y,

    output wire [7:0]          out_data,
    output wire                out_valid,
    output wire                out_de,
    output wire                out_hs,
    output wire                out_vs,
    output wire [X_BITS-1:0]   out_x,
    output wire [Y_BITS-1:0]   out_y
);

    reg [7:0]        d  [0:STAGES-1];
    reg              v  [0:STAGES-1];
    reg              de [0:STAGES-1];
    reg              hs [0:STAGES-1];
    reg              vs [0:STAGES-1];
    reg [X_BITS-1:0] xr [0:STAGES-1];
    reg [Y_BITS-1:0] yr [0:STAGES-1];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < STAGES; i = i + 1) begin
                d[i]  <= 8'h00;
                v[i]  <= 1'b0;
                de[i] <= 1'b0;
                hs[i] <= 1'b0;
                vs[i] <= 1'b0;
                xr[i] <= {X_BITS{1'b0}};
                yr[i] <= {Y_BITS{1'b0}};
            end
        end else begin
            d[0]  <= in_data;
            v[0]  <= in_valid;
            de[0] <= in_de;
            hs[0] <= in_hs;
            vs[0] <= in_vs;
            xr[0] <= in_x;
            yr[0] <= in_y;
            for (i = 1; i < STAGES; i = i + 1) begin
                d[i]  <= d[i-1];
                v[i]  <= v[i-1];
                de[i] <= de[i-1];
                hs[i] <= hs[i-1];
                vs[i] <= vs[i-1];
                xr[i] <= xr[i-1];
                yr[i] <= yr[i-1];
            end
        end
    end

    assign out_data  = d[STAGES-1];
    assign out_valid = v[STAGES-1];
    assign out_de    = de[STAGES-1];
    assign out_hs    = hs[STAGES-1];
    assign out_vs    = vs[STAGES-1];
    assign out_x     = xr[STAGES-1];
    assign out_y     = yr[STAGES-1];

endmodule
