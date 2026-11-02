# 24 MHz crystal input
create_clock -period 41.6667 [get_ports clk_24m]

# PLL feedback/system clock: 24 MHz (PLL divider 125, defined in the peri.xml)
create_clock -period 41.6667 [get_ports clk_sys]

# PLL-generated pixel clock: 25.0 MHz (clk_sys * 125 / 120, period 40 ns).
# NOTE: the old proj/system/system.sdc said 39.6825 (25.2 MHz) but the peri.xml
# PLL divider is 120 and the generated pt.sdc confirms 40.000 ns - the stale
# 25.2 number was only a (slightly) tighter constraint, not the real clock.
create_clock -period 40.0 [get_ports clk_pixel]

# PLL-generated 10x serializer clock: 250 MHz
create_clock -period 4.0 [get_ports clk_pixel_10x]

# PLL-generated csi_rx core clock: 50 MHz (clk_sys x 125 / 60).
# The Efinix csi2_rx IP in ip/csi_rx was generated with CLOCK_FREQ_MHZ = 50,
# so it gets a clock that matches that parameter (documented range 40..100 MHz).
create_clock -period 20.0 [get_ports clk_csi]

# The MIPI byte clock comes from the D-PHY RX hard block (CLKOUT of the
# GPIOR_PN_17 clock lane) and is asynchronous to the PLL clocks.
