# Native SD uses registered clock enables in the 50 MHz sd_card_clk domain.
# At 25 MHz SD, launch and capture are one 20 ns host period apart.
# Conservative board envelope: default-speed card tOD <=14ns plus 3ns
# forwarded-clock/PCB allowance; CMD setup/hold 5ns plus 2ns allowance.
# Apply to every host cycle (stricter than the enabled, alternate SD cycles).
# These are design assumptions; the physical card/board still needs validation.
set_input_delay -clock [get_clocks {sd_card_clk}] -max 17 [get_ports {sd_mosi sd_miso sd_dat1 sd_dat2 sd_ncs}]
set_input_delay -clock [get_clocks {sd_card_clk}] -min 3 [get_ports {sd_mosi sd_miso sd_dat1 sd_dat2 sd_ncs}]
# CMD/OE change only on SD falling edges: next card sample is20ns later,
# previous card sample was20ns earlier. Constrain setup to the next host edge.
# A zero hold budget at the launch host edge is stricter than the card's
# previous-edge 7ns hold requirement (launch occurs20ns after that edge).
# This relies on the explicit fall enable in sd_native4_cmd; no output changes
# are allowed on SD rising edges, except while the controller is in reset.
set_output_delay -clock [get_clocks {sd_card_clk}] -max 7 [get_ports {sd_mosi sd_ncs}]
set_output_delay -clock [get_clocks {sd_card_clk}] -min 0 [get_ports {sd_mosi sd_ncs}]
set_output_delay -clock [get_clocks {sd_card_clk}] -max 0 [get_ports {sd_dclk}]
set_output_delay -clock [get_clocks {sd_card_clk}] -min 0 [get_ports {sd_dclk}]
