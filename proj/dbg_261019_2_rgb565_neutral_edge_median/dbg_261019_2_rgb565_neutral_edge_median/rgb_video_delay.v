`timescale 1ns / 1ps
//==============================================================================
// rgb_video_delay : pipeline a 24-bit RGB pixel stream by STAGES cycles,
// keeping valid/de/hs/vs/x/y aligned with the data.
//==============================================================================
module rgb_video_delay #(
    parameter STAGES = 1,
    parameter X_BITS = 11,
    parameter Y_BITS = 11
)(
    input  wire                clk,
    input  wire                rst_n,

    input  wire [7:0]          in_r,
    input  wire [7:0]          in_g,
    input  wire [7:0]          in_b,
    input  wire                in_valid,
    input  wire                in_de,
    input  wire                in_hs,
    input  wire                in_vs,
    input  wire [X_BITS-1:0]   in_x,
    input  wire [Y_BITS-1:0]   in_y,

    output wire [7:0]          out_r,
    output wire [7:0]          out_g,
    output wire [7:0]          out_b,
    output wire                out_valid,
    output wire                out_de,
    output wire                out_hs,
    output wire                out_vs,
    output wire [X_BITS-1:0]   out_x,
    output wire [Y_BITS-1:0]   out_y
);

    reg [7:0]        rr [0:STAGES-1];
    reg [7:0]        gr [0:STAGES-1];
    reg [7:0]        br [0:STAGES-1];
    reg              vr [0:STAGES-1];
    reg              dr [0:STAGES-1];
    reg              hr [0:STAGES-1];
    reg              sr [0:STAGES-1];
    reg [X_BITS-1:0] xr [0:STAGES-1];
    reg [Y_BITS-1:0] yr [0:STAGES-1];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < STAGES; i = i + 1) begin
                rr[i] <= 8'd0; gr[i] <= 8'd0; br[i] <= 8'd0;
                vr[i] <= 1'b0; dr[i] <= 1'b0; hr[i] <= 1'b0; sr[i] <= 1'b0;
                xr[i] <= {X_BITS{1'b0}}; yr[i] <= {Y_BITS{1'b0}};
            end
        end else begin
            rr[0] <= in_r; gr[0] <= in_g; br[0] <= in_b;
            vr[0] <= in_valid; dr[0] <= in_de;
            hr[0] <= in_hs;    sr[0] <= in_vs;
            xr[0] <= in_x;     yr[0] <= in_y;
            for (i = 1; i < STAGES; i = i + 1) begin
                rr[i] <= rr[i-1]; gr[i] <= gr[i-1]; br[i] <= br[i-1];
                vr[i] <= vr[i-1]; dr[i] <= dr[i-1];
                hr[i] <= hr[i-1]; sr[i] <= sr[i-1];
                xr[i] <= xr[i-1]; yr[i] <= yr[i-1];
            end
        end
    end

    assign out_r = rr[STAGES-1];
    assign out_g = gr[STAGES-1];
    assign out_b = br[STAGES-1];
    assign out_valid = vr[STAGES-1];
    assign out_de    = dr[STAGES-1];
    assign out_hs    = hr[STAGES-1];
    assign out_vs    = sr[STAGES-1];
    assign out_x     = xr[STAGES-1];
    assign out_y     = yr[STAGES-1];

endmodule
