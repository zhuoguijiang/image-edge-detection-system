# Phase-1 placeholder constraint.
# 640x480@60 with a 25 MHz pixel clock (800 x 525 total, ~59.52 Hz).
# The final HDMI design will instead constrain the on-board crystal input and the
# PLL-generated pixel/serializer clocks.
create_clock -period 40.0 [get_ports clk]
