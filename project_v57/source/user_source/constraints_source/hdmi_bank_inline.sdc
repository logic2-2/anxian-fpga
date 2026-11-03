# Reapply only the corrected bank/reset constraints when importing a routed
# checkpoint that cached the old variable-based timing.sdc expressions.
# New full builds use these same inline queries directly in timing.sdc.
set_max_delay -datapath_only -from [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/word_buf*}] -to [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_word_ready*}] 6
set_false_path -hold -from [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/word_buf*}] -to [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_word_ready*}]
set_false_path -from [get_regs -hier -quiet {rs_video/release_pipe*}] -to [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/serial_reset/release_pipe*}]
