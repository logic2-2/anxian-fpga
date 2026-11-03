# Fixed720p: remove constraints for the removed VGA PLL only. Active HD clock rates and CDC bounds are unchanged.

# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 保留 top.sdc 里的系统主时钟与 derive_clocks
# 2) 把 timing(2).sdc 里的 pixel/serial 时钟改成整合工程实际名字
# 3) 增加 hdmi_5x_clk / audio_mclk 的命名
# 4) 不再对内部 net 直接 create_clock，避免和 derive_clocks 重复
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# ------------------------------------------------------------
# 3. 给关键 PLL 输出命名
#    下面这些路径是按你当前工程实例名写的：
#      sys_pll      -> sys_pll_m0
#      video_pll    -> video_pll_m0
#      音频 PLL     -> u_audio_pll
#
#    如果综合后实例路径略有不同，就按 Timing Analyzer 里的实际 pin 路径改。
# ------------------------------------------------------------
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {audio_mclk}  -source [get_ports {clk}] -master_clock {clk} [get_pins {u_audio_pll/pll_inst.clkc[2]}]

rename_clock -name {video_clk_hd} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_hd_pll/pll_inst.clkc[1]}]
rename_clock -name {hdmi_5x_hd} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_hd_pll/pll_inst.clkc[2]}]
# ------------------------------------------------------------
# 4. 从原 timing(2).sdc 迁移过来的 HDMI 像素/串行时钟约束
#
#    原文件是：
#      create_clock -name pixel_clk  ... [get_nets {S_pixel_clk}]
#      create_clock -name serial_clk ... [get_nets {S_serial_clk}]
#      set_clock_groups -exclusive ...
#
#    在整合工程里，这两个时钟已经由 video_pll 产生，并通过 derive_clocks 建出来了，
#    所以这里只保留“组关系”，不再重复 create_clock。
#
#    这里沿用原作者的写法，把 video_clk 和 hdmi_5x_clk 设成 exclusive。
#    如果后面 Timing Analyzer 明确显示两者之间需要做同步时序分析，再把这一条去掉。
# ------------------------------------------------------------
# Removed: pixel and serial clocks run concurrently; retain timing analysis.

# ------------------------------------------------------------
# 5. 音频 I2S 发生器/接收器跨域
#
#    audio_mclk 域里生成 I2S，video_clk 域里做三拍同步采样。
#    这类路径不是普通同步时序路径，直接切掉更合理。
# ------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {audio_mclk}] \
    -group [get_clocks {  video_clk_hd hdmi_5x_hd sd_card_clk ext_mem_clk}]

# ------------------------------------------------------------
# 6. 可选：如果你的 frame_read_write 内部异步 FIFO 已经完全处理好了跨域，
#    且报告里总出现 video_clk / sd_card_clk / ext_mem_clk 之间的大量伪违例，
#    可以打开下面这组异步分组。
#
#    建议先不要开，先看报告；
#    只有确认这些跨域都只经过 FIFO / 同步器时再开。
# ------------------------------------------------------------
# set_clock_groups -asynchronous \
#     -group [get_clocks {sd_card_clk}] \
#     -group [get_clocks {ext_mem_clk}] \
#     -group [get_clocks {video_clk}] \
#     -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 7. 其余 Input/Output delay 先保持空白
#    你当前两个原始 sdc 也都没有写这部分。
# ------------------------------------------------------------

# Reviewed CDC entrances only. The two PLLs have no guaranteed common phase.
# Gray pointer crosses into sync_r1, then primary_addr_gray_sync; its output
# is decoded only after those two destination registers (vendor FIFO RTL).
# Preserve a 20ns datapath bound (less than the 40ns source update period),
# and exclude only the first-stage asynchronous hold check, not the next stage.
set gray_source [get_regs -hier -quiet {frame_read_write_m0/main/read_buf/rd_to_wr_cross_inst/primary_addr_gray_reg*}]
set gray_first [get_regs -hier -quiet {frame_read_write_m0/main/read_buf/rd_to_wr_cross_inst/sync_r1*}]
if {[llength $gray_source]==0 || [llength $gray_first]==0} {error "Missing reviewed FIFO CDC endpoints"}
puts "CDC_SCOPE gray_source=[llength $gray_source] gray_first=[llength $gray_first]"
set_max_delay -datapath_only -from [get_regs -hier -quiet {frame_read_write_m0/main/read_buf/rd_to_wr_cross_inst/primary_addr_gray_reg*}] -to [get_regs -hier -quiet {frame_read_write_m0/main/read_buf/rd_to_wr_cross_inst/sync_r1*}] 20
set_false_path -hold -from [get_regs -hier -quiet {frame_read_write_m0/main/read_buf/rd_to_wr_cross_inst/primary_addr_gray_reg*}] -to [get_regs -hier -quiet {frame_read_write_m0/main/read_buf/rd_to_wr_cross_inst/sync_r1*}]

# Frame request is held until ACK and enters a two-register synchronizer.
set frame_source [get_regs -hier -quiet {video_timing_data_m0/read_req*}]
set frame_first [get_regs -hier -quiet {scene_bridge/frame_req_sync*}]
if {[llength $frame_source]==0 || [llength $frame_first]==0} {error "Missing reviewed frame-request CDC endpoints"}
puts "CDC_SCOPE frame_source=[llength $frame_source] frame_sync=[llength $frame_first]"
set_max_delay -datapath_only -from [get_regs -hier -quiet {video_timing_data_m0/read_req*}] -to [get_regs -hier -quiet {scene_bridge/frame_req_sync*}] 20
set_false_path -hold -from [get_regs -hier -quiet {video_timing_data_m0/read_req*}] -to [get_regs -hier -quiet {scene_bridge/frame_req_sync*}]

# Reviewed control/memory <-> selected video domain boundaries:
# async RAM FIFOs use registered Gray pointers and two-stage synchronizers;
# frame request/ACK and scene payload use held request/toggle handshakes;
# settings flags use two-stage mo_sync/mc_sync;
# resolution_mode changes only while video_hold asserts reset, with 4096
# 50-MHz guard clocks both before and after the clock handover.
# Pixel and its 5x serial clock stay timed against one another.
set_clock_groups -asynchronous -group [get_clocks {sd_card_clk ext_mem_clk}] -group [get_clocks { video_clk_hd  hdmi_5x_hd}]

# HDMI pixel-event toggle enters an explicit 2-FF serial-domain synchronizer
# (S_odd_even_1d then S_odd_even_2d). It is an event CDC, not a serial-cycle
# synchronous datapath. Bound its delay below the 13.468 ns source period.
set hdmi_toggle_source [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_odd_even}]
set hdmi_toggle_first [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_odd_even_1d}]
if {[llength $hdmi_toggle_source]==0 || [llength $hdmi_toggle_first]==0} {error "Missing HDMI toggle synchronizer"}
puts "HDMI_CDC source=[llength $hdmi_toggle_source] first=[llength $hdmi_toggle_first]"
set_max_delay -datapath_only -from [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_odd_even}] -to [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_odd_even_1d}] 10
set_false_path -hold -from [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_odd_even}] -to [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_odd_even_1d}]
# Serial reset has asynchronous assertion and a four-stage local release.
# Only the incoming asynchronous-reset boundary is excepted; local release
# stages and downstream serializer datapaths remain timed.
set hdmi_reset_source [get_regs -hier -quiet {rs_video/release_pipe*}]
set hdmi_reset_release [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/serial_reset/release_pipe*}]
if {[llength $hdmi_reset_source]==0 || [llength $hdmi_reset_release]==0} {error "Missing serial reset release stages"}
# TD 6.2 stores the constraint expression for later timing refresh. Query
# endpoints inline: saved Tcl variable references matched zero timing paths.
set_false_path -from [get_regs -hier -quiet {rs_video/release_pipe*}] -to [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/serial_reset/release_pipe*}]

# Banked TMDS words are held for two pixel periods. The selected bank is
# prepared at least three serial cycles after its pixel-domain write and
# one serial cycle before the shift-register load. Bound this bundled-data
# transfer to 6ns (< 3 * 2.693ns); the non-selected bank can change freely.
set tmds_word_banks [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/word_buf*}]
set tmds_word_prepare [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_word_ready*}]
if {[llength $tmds_word_banks]==0 || [llength $tmds_word_prepare]==0} {error "Missing banked TMDS word registers"}
puts "TMDS_BANK_CDC banks=[llength $tmds_word_banks] prepare=[llength $tmds_word_prepare]"
# The explicit physical delay bound covers the bundled-data transfer;
# downstream serial-to-serial stages retain their ordinary cycle checks.
set_max_delay -datapath_only -from [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/word_buf*}] -to [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_word_ready*}] 6
set_false_path -hold -from [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/word_buf*}] -to [get_regs -hier -quiet {u_hdmi2phy_wrapper/*/S_word_ready*}]
