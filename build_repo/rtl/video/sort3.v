//==============================================================================
// sort3 : 3-input sorting network, outputs ordered lo <= mid <= hi.
//==============================================================================
module sort3 (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [7:0] c,
    output wire [7:0] lo,
    output wire [7:0] mid,
    output wire [7:0] hi
);
    wire [7:0] h1, l1, h2, m2;
    assign h1  = (a > b) ? a : b;
    assign l1  = (a > b) ? b : a;
    assign h2  = (h1 > c) ? h1 : c;
    assign m2  = (h1 > c) ? c : h1;
    assign hi  = h2;
    assign mid = (l1 > m2) ? l1 : m2;
    assign lo  = (l1 > m2) ? m2 : l1;
endmodule
