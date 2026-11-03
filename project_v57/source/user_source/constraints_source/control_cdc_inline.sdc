# Same previously reviewed first-stage boundaries and physical delay bounds.
# Inline endpoints survive TD timing refresh when importing an old checkpoint.
set_max_delay -datapath_only -from [get_regs -hier -quiet {frame_read_write_m0/main/read_buf/rd_to_wr_cross_inst/primary_addr_gray_reg*}] -to [get_regs -hier -quiet {frame_read_write_m0/main/read_buf/rd_to_wr_cross_inst/sync_r1*}] 20
set_false_path -hold -from [get_regs -hier -quiet {frame_read_write_m0/main/read_buf/rd_to_wr_cross_inst/primary_addr_gray_reg*}] -to [get_regs -hier -quiet {frame_read_write_m0/main/read_buf/rd_to_wr_cross_inst/sync_r1*}]
set_max_delay -datapath_only -from [get_regs -hier -quiet {video_timing_data_m0/read_req*}] -to [get_regs -hier -quiet {scene_bridge/frame_req_sync*}] 20
set_false_path -hold -from [get_regs -hier -quiet {video_timing_data_m0/read_req*}] -to [get_regs -hier -quiet {scene_bridge/frame_req_sync*}]
set_max_delay -datapath_only -from [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_odd_even}] -to [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_odd_even_1d}] 10
set_false_path -hold -from [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_odd_even}] -to [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_odd_even_1d}]
