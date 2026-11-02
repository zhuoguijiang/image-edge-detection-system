//==============================================================================
// median3x3 : 3x3 median filter (parallel sorting network, no serial sort).
//   1) sort each row of the window (3x sort3)
//   2) a = max(row mins), b = med(row mids), c = min(row maxs)
//   3) median = med(a, b, c)
// Three pipeline stages.
//==============================================================================
module median3x3 #(
    parameter [7:0] ADAPT_TOL = 8'd12,
    parameter [3:0] ADAPT_MAX_SIM = 4'd1
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] w00, w01, w02,
    input  wire [7:0] w10, w11, w12,
    input  wire [7:0] w20, w21, w22,
    input  wire       in_valid,
    output reg  [7:0] med,
    output reg  [7:0] med_adaptive,
    output reg        out_valid
);

    function [7:0] absdiff;
        input [7:0] a;
        input [7:0] b;
        begin
            absdiff = (a > b) ? (a - b) : (b - a);
        end
    endfunction

    // Number of the eight neighbours that are close to the centre.  A real
    // thin line has at least two similar neighbours (along the line), while
    // an isolated salt/pepper pixel has none.
    wire [3:0] sim_cnt =
        {3'b000, (absdiff(w00, w11) <= ADAPT_TOL)} +
        {3'b000, (absdiff(w01, w11) <= ADAPT_TOL)} +
        {3'b000, (absdiff(w02, w11) <= ADAPT_TOL)} +
        {3'b000, (absdiff(w10, w11) <= ADAPT_TOL)} +
        {3'b000, (absdiff(w12, w11) <= ADAPT_TOL)} +
        {3'b000, (absdiff(w20, w11) <= ADAPT_TOL)} +
        {3'b000, (absdiff(w21, w11) <= ADAPT_TOL)} +
        {3'b000, (absdiff(w22, w11) <= ADAPT_TOL)};

    // ---- stage 1: sort each row ----
    wire [7:0] r0lo, r0mid, r0hi, r1lo, r1mid, r1hi, r2lo, r2mid, r2hi;
    sort3 u_s0 (.a(w00), .b(w01), .c(w02), .lo(r0lo), .mid(r0mid), .hi(r0hi));
    sort3 u_s1 (.a(w10), .b(w11), .c(w12), .lo(r1lo), .mid(r1mid), .hi(r1hi));
    sort3 u_s2 (.a(w20), .b(w21), .c(w22), .lo(r2lo), .mid(r2mid), .hi(r2hi));

    reg [7:0] s1_lo0, s1_mid0, s1_hi0;
    reg [7:0] s1_lo1, s1_mid1, s1_hi1;
    reg [7:0] s1_lo2, s1_mid2, s1_hi2;
    reg [3:0] s1_sim;
    reg [7:0] s1_center;
    reg       s1_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_lo0 <= 0; s1_mid0 <= 0; s1_hi0 <= 0;
            s1_lo1 <= 0; s1_mid1 <= 0; s1_hi1 <= 0;
            s1_lo2 <= 0; s1_mid2 <= 0; s1_hi2 <= 0;
            s1_sim <= 4'd0; s1_center <= 8'd0;
            s1_valid <= 1'b0;
        end else begin
            s1_lo0 <= r0lo; s1_mid0 <= r0mid; s1_hi0 <= r0hi;
            s1_lo1 <= r1lo; s1_mid1 <= r1mid; s1_hi1 <= r1hi;
            s1_lo2 <= r2lo; s1_mid2 <= r2mid; s1_hi2 <= r2hi;
            s1_sim <= sim_cnt; s1_center <= w11;
            s1_valid <= in_valid;
        end
    end

    // ---- stage 2: a = max(mins), b = med(mids), c = min(maxs) ----
    wire [7:0] mm01 = (s1_lo0 > s1_lo1) ? s1_lo0 : s1_lo1;
    wire [7:0] a_val = (mm01 > s1_lo2) ? mm01 : s1_lo2;

    wire [7:0] bl, bm, bh;
    sort3 u_sm (.a(s1_mid0), .b(s1_mid1), .c(s1_mid2), .lo(bl), .mid(bm), .hi(bh));

    wire [7:0] xx01 = (s1_hi0 < s1_hi1) ? s1_hi0 : s1_hi1;
    wire [7:0] c_val = (xx01 < s1_hi2) ? xx01 : s1_hi2;

    reg [7:0] s2_a, s2_b, s2_c;
    reg [3:0] s2_sim;
    reg [7:0] s2_center;
    reg       s2_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_a <= 0; s2_b <= 0; s2_c <= 0;
            s2_sim <= 4'd0; s2_center <= 8'd0;
            s2_valid <= 1'b0;
        end else begin
            s2_a <= a_val; s2_b <= bm; s2_c <= c_val;
            s2_sim <= s1_sim; s2_center <= s1_center;
            s2_valid <= s1_valid;
        end
    end

    // ---- stage 3: median of a, b, c ----
    wire [7:0] fl, fm, fh;
    sort3 u_sf (.a(s2_a), .b(s2_b), .c(s2_c), .lo(fl), .mid(fm), .hi(fh));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            med <= 8'd0; med_adaptive <= 8'd0; out_valid <= 1'b0;
        end else begin
            med <= fm;
            med_adaptive <= (s2_sim <= ADAPT_MAX_SIM) ? fm : s2_center;
            out_valid <= s2_valid;
        end
    end

endmodule
