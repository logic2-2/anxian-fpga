
module top(
    input                       clk,
    input                       rst_n,          // 板上 KEY1：复位
    input                       key1,           // 板上 KEY2：下一主题 / 选择 / 减
    input                       key2,           // 板上 KEY4：预览详情 / 确认 / 加
    input                       key_menu,       // 板上 KEY3：菜单/返回

    output [7:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF: native DAT3/CMD share the former SPI CS/MOSI pins.
    inout                       sd_ncs,
    output                      sd_dclk,
    inout                       sd_mosi,
    input                       sd_miso,
    input                       sd_dat1,
    input                       sd_dat2
);

parameter ENABLE_INTERNAL_DIAGNOSTICS = 0;
parameter USE_NATIVE_SD = 1;
parameter ENABLE_SD_TIMING = 1;
parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd460800;   // 1280*720 RGB565, 2 pixels/word
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sys_pll_lock,audio_pll_lock;
wire reset_request;
wire rst_sd,rst_mem,rst_video,rst_audio,rst_ui;
wire fit_requested,fit_applied,fit_reload_hold;
wire intro_hold,intro_request,intro_play_audio,intro_tail_fade;
wire opening_audio_ready,opening_audio_done,opening_audio_available;
wire movie_available,movie_start,movie_exit,movie_play,movie_picture_ready,movie_mode_active;
wire movie_write_active,movie_write_slot,movie_publish_toggle,movie_publish_slot,movie_ack_toggle;
wire movie_read_mem,movie_read_slot;wire [15:0] movie_publish_frame,movie_display_frame;
wire movie_display_video;
wire movie_pause_toggle,movie_paused,movie_forward,movie_backward,movie_seeking;
wire [7:0] movie_progress;
wire [15:0] movie_elapsed_bcd,movie_duration_bcd;
wire [9:0] audio_settings;wire video_split_requested;
wire [54:0] movie_status_video;wire [1:0] bgm_select,bgm_count;
wire [8:0] movie_output_gain;
reg movie_output_muted;
(* async_reg="true" *)reg [1:0] movie_pause_gain_sync;
wire movie_status_source_rst;
media_reset_sync movie_status_reset(sd_card_clk,rst_sd|video_hold|(resolution_mode && !video_hi_lock),movie_status_source_rst);
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin movie_output_muted<=1;movie_pause_gain_sync<=0;end
 else begin movie_output_muted<=movie_output_gain==0;movie_pause_gain_sync<={movie_pause_gain_sync[0],movie_paused || movie_seeking};end
end
exhibit_movie_status_bridge_v39 #(.WIDTH(55)) movie_status_bridge(.source_clk(sd_card_clk),.source_rst(movie_status_source_rst),
 .payload({video_split_requested,audio_settings,movie_progress,movie_seeking,(bgm_select<bgm_count?bgm_select:2'd0),movie_paused,movie_elapsed_bcd,movie_duration_bcd}),
 .video_clk(video_clk),.video_rst(rst_video),.vs(vs_adj),.status(movie_status_video));
wire audio_stream_fault;
wire intro_black_ready,intro_handoff_done;
wire media_reset_request=reset_request|fit_reload_hold;
assign reset_request=~rst_n | ~sys_pll_lock | ~video_hi_lock | ~audio_pll_lock;
wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;
wire video_clk_hi,serial_clk_hi,video_hi_lock;
wire resolution_mode,video_hold,mode_busy,menu_open,mode_request,requested_mode;
// User-selected fixed1280x720 output. Pixel and serial clocks retain their HD PLL rates.
assign resolution_mode=1'b1;
wire [3:0] menu_cursor;
wire [31:0] settings_options;
wire [6:0] brightness_payload,screen_brightness;
wire brightness_toggle,brightness_ack;
wire [8:0] screen_gain;
wire ui_next,ui_view,ui_style;
wire [1:0] menu_open_sync;
wire [3:0] menu_cursor_sync;
reg [1:0] mo_sync;
reg [3:0] mc_s0,mc_s1;
reg [1:0] fit_sync;
assign menu_open_sync=mo_sync;assign menu_cursor_sync=mc_s1;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin mo_sync<=0;mc_s0<=0;mc_s1<=0;fit_sync<=0;end
 else begin mo_sync<={mo_sync[0],menu_open};mc_s0<=menu_cursor;mc_s1<=mc_s0;fit_sync<={fit_sync[0],fit_requested};end
end
exhibit_settings_menu_v37 settings(.video_split(video_split_requested),.audio_settings(audio_settings),.bgm_count(bgm_count),.bgm_select(bgm_select),.movie_available(movie_available),.movie_active(movie_mode_active),.movie_start(movie_start),.movie_exit(movie_exit),.movie_pause_toggle(movie_pause_toggle),.movie_forward(movie_forward),.movie_backward(movie_backward),.clk(sd_card_clk),.rst(rst_ui),.next_n(intro_hold?1'b1:key1),.view_n(intro_hold?1'b1:key2),.menu_n(intro_hold?1'b1:key_menu),
 .active_mode(resolution_mode),.menu_open(menu_open),.cursor(menu_cursor),.options(settings_options),
 .brightness_payload(brightness_payload),.brightness_toggle(brightness_toggle),.brightness_ack(brightness_ack),
 .mode_request(mode_request),.requested_mode(requested_mode),
 .next_event(ui_next),.view_event(ui_view),.style_event(ui_style),.adaptive_enable(fit_requested));
exhibit_fit_reload fit_reload(.clk(sd_card_clk),.rst(rst_ui),.menu_open(menu_open),.requested_fit(fit_requested),.applied_fit(fit_applied),.media_hold(fit_reload_hold));
exhibit_video_switch switch_control(.clk(sd_card_clk),.rst(rst_ui),.request(1'b0),
 .requested_mode(1'b1),.hi_locked(video_hi_lock),.active_mode(),.video_hold(video_hold),.busy(mode_busy));
wire pixel_mux_raw,serial_mux_raw;
assign pixel_mux_raw=video_clk_hi;
assign serial_mux_raw=serial_clk_hi;
EG_LOGIC_BUFG pixel_buffer(.i(pixel_mux_raw),.o(video_clk));
EG_LOGIC_BUFG serial_buffer(.i(serial_mux_raw),.o(hdmi_5x_clk));
video_pll_720 video_hd_pll(.refclk(clk),.reset(1'b0),.locked(video_hi_lock),.clk0_out(video_clk_hi),.clk1_out(serial_clk_hi));

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;
wire [1:0] player_theme,player_mode;
assign movie_mode_active=player_mode==3;
reg [1:0] remembered_theme,remembered_mode;
always @(posedge sd_card_clk or posedge rst_ui)begin
 if(rst_ui)begin remembered_theme<=0;remembered_mode<=0;end
 else if(display_valid && !fit_reload_hold)begin remembered_theme<=player_theme;remembered_mode<=player_mode;end
end

wire [3:0]  state_code;
wire [3:0]  error_detail;
wire [6:0]  error_segments;
wire [6:0]  seg_data_0;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;

wire publish_toggle,publish_ack_toggle,frame_toggle;
wire [47:0] publish_scene,active_scene_mem,selected_scene_mem;
wire [3:0] ready_mask;
wire intro_asset_valid,intro_asset_checked,intro_finished;
wire intro_visible,intro_presented,intro_decoder_fault;
wire [5:0] intro_frame_gray;
exhibit_intro_lifecycle_v35 intro_lifecycle(.clk(sd_card_clk),.rst(rst_ui),
 .asset_checked(intro_asset_checked),.asset_valid(intro_asset_valid),.presented(intro_presented),.decoder_fault(intro_decoder_fault),
 .audio_done(opening_audio_done || audio_stream_fault),.black_ready(intro_black_ready),.handoff_done(intro_handoff_done),
 .intro_request(intro_request),.hold_tour(intro_hold),.play_audio(intro_play_audio),.tail_fade_request(intro_tail_fade),.frame_gray(intro_frame_gray),.finished(intro_finished));
wire [31:0] media_diagnostic;
wire [15:0] read_underflows,read_overflows;
// Keep the integrity monitors even when their OSD row is hidden.
(* keep="true" *) wire [15:0] pixel_bad_frames,pixel_checked_frames;
(* keep="true" *) wire [31:0] image_last_crc;
wire axis_s_ready_hd;
(* keep="true" *) reg [15:0] axis_reject_count;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)axis_reject_count<=0;
 else if(!ENABLE_INTERNAL_DIAGNOSTICS || pixel_checked_frames<4)axis_reject_count<=0;
 else if(axis_s_valid && !(resolution_mode?axis_s_ready_hd:axis_s_ready) && axis_reject_count!=16'hffff)
  axis_reject_count<=axis_reject_count+1'b1;
end
reg [31:0] diagnostic_s0,diagnostic_s1;
reg [3:0] ready_s0,ready_s1;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin diagnostic_s0<=0;diagnostic_s1<=0;ready_s0<=0;ready_s1<=0;end
 else begin diagnostic_s0<=display_valid?{pixel_bad_frames,axis_reject_count}:media_diagnostic;diagnostic_s1<=diagnostic_s0;ready_s0<=ready_mask;ready_s1<=ready_s0;end
end
wire [1:0] selected_read_buf;
wire read_req_mem;
(* async_reg="true" *)reg [1:0] split_mem_sync;
reg split_req_d,movie_split_read;
always @(posedge ext_mem_clk or posedge rst_mem)begin
 if(rst_mem)begin split_mem_sync<=0;split_req_d<=0;movie_split_read<=0;end
 else begin
  split_mem_sync<={split_mem_sync[0],video_split_requested};split_req_d<=read_req_mem;
  // The UI permits layout edits only outside movie playback. Sample once
  // per read handshake; the payload remains held through the FIFO ACK.
  if(read_req_mem && !split_req_d)movie_split_read<=split_mem_sync[1];
 end
end
wire [8:0] active_gain_mem;
exhibit_transition_bridge #(.STEP(16)) scene_bridge(
 .mem_clk(ext_mem_clk),.rst_mem(rst_mem),.publish_scene(publish_scene),.publish_toggle(publish_toggle),
 .publish_ack_toggle(publish_ack_toggle),.video_read_req(video_read_req),.video_read_req_ack(video_read_req_ack),
 .read_req_mem(read_req_mem),.selected_read_buf(selected_read_buf),.selected_scene(selected_scene_mem),.active_gain(active_gain_mem),.active_scene(active_scene_mem),.frame_toggle(frame_toggle)
);
// Active scene changes once per frame, at the read handshake in vertical blank.
// Stable bundled payload is sampled after a three-stage event synchronizer.
reg [2:0] scene_event_sync;
reg [47:0] active_scene_video;
reg [8:0] active_gain_video;
reg [1:0] frame_enable_sync;
reg [7:0] boot_status_s0,boot_status_s1;
always @(posedge video_clk or posedge rst_video) begin
 if(rst_video) begin
  scene_event_sync<=0;active_scene_video<=0;active_gain_video<=0;frame_enable_sync<=0;
  boot_status_s0<=0;boot_status_s1<=0;
 end else begin
  scene_event_sync<={scene_event_sync[1:0],frame_toggle};
  frame_enable_sync<={frame_enable_sync[0],display_valid};
  boot_status_s0<={state_code,error_detail};boot_status_s1<=boot_status_s0;
  if(scene_event_sync[2]^scene_event_sync[1]) begin active_scene_video<=active_scene_mem;active_gain_video<=active_gain_mem;end
 end
end
reg movie_split_video;
wire movie_split_active=movie_split_video && movie_display_video;
reg movie_video;reg [1:0] movie_available_video;reg [15:0] movie_frame_video;
assign movie_display_video=movie_video;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin movie_split_video<=0;movie_video<=0;movie_available_video<=0;movie_frame_video<=0;end
 else begin movie_available_video<={movie_available_video[0],movie_available};
 if(scene_event_sync[2]^scene_event_sync[1])begin
  movie_split_video<=movie_split_read && movie_read_mem && active_scene_mem[3:2]==3;
  movie_video<=movie_read_mem && active_scene_mem[3:2]==3;
  movie_frame_video<=movie_display_frame;
 end
 end
end
exhibit_movie_present_v37 movie_present(.clk(ext_mem_clk),.rst(rst_mem),.requested(player_mode==3),.scene_movie(selected_scene_mem[3:2]==3),
 .frame_req(read_req_mem),.read_ack(video_read_req_ack),.request_toggle(movie_publish_toggle),.request_slot(movie_publish_slot),.request_frame(movie_publish_frame),
 .ack_toggle(movie_ack_toggle),.read_movie(movie_read_mem),.read_slot(movie_read_slot),.displayed_frame(movie_display_frame));
wire pixel_visible=active_scene_video[13];
wire [13:0] osd_scene=pixel_visible?active_scene_video[13:0]:
 {1'b0,(boot_status_s1[7:4]==4'he || boot_status_s1[7:4]==4'hf),boot_status_s1[3:0],8'd0};
wire hs_osd,vs_osd,de_osd;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关

wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 音频链路



media_reset_sync rs_ui(sd_card_clk,reset_request,rst_ui);
media_reset_sync rs_sd(sd_card_clk,media_reset_request,rst_sd);
media_reset_sync rs_mem(ext_mem_clk,media_reset_request,rst_mem);
media_reset_sync rs_video(video_clk,media_reset_request|video_hold|(resolution_mode && !video_hi_lock),rst_video);
media_reset_sync rs_audio(audio_mclk,reset_request,rst_audio);

// TF/SDRAM控制器50MHz，SDRAM引脚时钟相对控制器延后8ns；视频时钟不变。
sys_pll sys_pll_m0(
    .locked(sys_pll_lock),
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (1'b0)
);



// 复用你 I2S->HDMI 工程里的 PLL，只取 12.288MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 四槽预加载与展陈交互 =====================
wire debug_sd_request;
wire audio_narrating;
wire [5:0] audio_caption_id;
wire [3:0] audio_stream_error;
wire [47:0] load_timing_segments;
wire load_timing_visible=ENABLE_SD_TIMING && state_code!=4'he && state_code!=4'hf;
exhibit_load_timing load_timing(.clk(sd_card_clk),.rst(rst_sd),.ready(display_valid),
 .fault(state_code==4'he || state_code==4'hf),.card_request(debug_sd_request),
 .segments(load_timing_segments),.total_bcd(),.card_bcd());
exhibit_player_v37 #(.USE_EVENT_INPUTS(1),.USE_BOOT_STATE(1),.USE_NATIVE_SD(USE_NATIVE_SD),.USE_TF_AUDIO(1),.USE_BRAND_INTRO(1)) player(
 .bgm_select(bgm_select),.bgm_count(bgm_count),
 .movie_speed(audio_settings[1:0]),.movie_start(movie_start),.movie_exit(movie_exit),.movie_pause_toggle(movie_pause_toggle),.movie_forward(movie_forward),.movie_backward(movie_backward),.movie_output_muted(movie_output_muted),.movie_seeking(movie_seeking),.movie_progress(movie_progress),.movie_paused(movie_paused),.movie_elapsed_bcd(movie_elapsed_bcd),.movie_duration_bcd(movie_duration_bcd),.movie_picture_ready(movie_picture_ready),.display_ack_toggle(movie_ack_toggle),
 .movie_available(movie_available),.movie_play(movie_play),.movie_write_active(movie_write_active),.movie_write_slot(movie_write_slot),.movie_publish_toggle(movie_publish_toggle),.movie_publish_slot(movie_publish_slot),.movie_publish_frame(movie_publish_frame),
 .clk(sd_card_clk),.rst(rst_sd),.key_next(key1),.key_select(key2),
 .next_action(ui_next),.select_action(ui_view),.style_action(ui_style),.options(settings_options),.diagnostic(media_diagnostic),.debug_sd_request(debug_sd_request),
 .adaptive_enable(fit_applied),.boot_theme(remembered_theme),.boot_mode(remembered_mode),.current_theme(player_theme),.current_mode(player_mode),
 .state_code(state_code),.error_detail(error_detail),.ready_mask(ready_mask),.display_valid(display_valid),
 .write_finish_toggle(frame_write_toggle_mem),.publish_ack_toggle(publish_ack_toggle),
 .write_slot(write_buf_idx),.publish_scene(publish_scene),.publish_toggle(publish_toggle),
 .write_req(sd_card_write_req),.write_req_ack(sd_card_write_req_ack),.write_en(sd_card_write_en),.write_data(sd_card_write_data),
 .SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso),.SD_DAT1(sd_dat1),.SD_DAT2(sd_dat2),
 .audio_clk(audio_mclk),.audio_rst(rst_audio),.audio_scene_ready(active_scene_mem[3:0]=={player_mode,player_theme} && active_gain_mem==256),
 .audio_bclk(audio_i2s_bclk),.audio_lrck(audio_i2s_lrck),.audio_dout(audio_i2s_dout),
 .audio_narrating(audio_narrating),.audio_fault(audio_stream_fault),.audio_error(audio_stream_error),.audio_caption_id(audio_caption_id),.boot_hold(intro_hold),
 .opening_arm(intro_request),.opening_play(intro_play_audio),.exclusive_opening(intro_request || intro_visible),
 .opening_ready(opening_audio_ready),.opening_done(opening_audio_done),.opening_available(opening_audio_available)
);

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

wire [15:0] fault_word=(media_diagnostic[31:24]==8'hd4) ?
 {8'hd4,media_diagnostic[7:0]}:media_diagnostic[15:0];
wire [6:0] fault_command_hi,fault_command_lo;
seg_decoder command_decoder_hi(media_diagnostic[23:20],fault_command_hi);
seg_decoder command_decoder_lo(media_diagnostic[19:16],fault_command_lo);
wire [6:0] fault_digit0,fault_digit1,fault_digit2,fault_digit3;
seg_decoder fault_decoder0(fault_word[3:0],fault_digit0);
seg_decoder fault_decoder1(fault_word[7:4],fault_digit1);
seg_decoder fault_decoder2(fault_word[11:8],fault_digit2);
seg_decoder fault_decoder3(fault_word[15:12],fault_digit3);
wire [63:0] panel_digits=load_timing_visible?{16'hffff,load_timing_segments}:
 ENABLE_SD_TIMING?{{1'b1,fault_command_hi},{1'b1,fault_command_lo},{1'b1,seg_data_0},{1'b1,error_segments},
  {1'b1,fault_digit3},{1'b1,fault_digit2},{1'b1,fault_digit1},{1'b1,fault_digit0}}:
 {48'hffffffffffff,{1'b1,seg_data_0},{1'b1,error_segments}};
exhibit_hx4s20_seg_scan panel_scan(.clk(clk),.rst(~rst_n),.digits(panel_digits),
 .select(seg_sel),.segments(seg_data));

// 两个相邻数码位：原位显示E/F，旁边显示错误细分码；正常时细分码为0。
seg_decoder error_decoder(.bin_data(error_detail),.seg_data(error_segments));

// ===================== 原图像时序与帧缓存 =====================
wire native_de_0;
reg [20:0] native_de_pipe;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)native_de_pipe<=0;else native_de_pipe<={native_de_pipe[19:0],native_de_0};
end
wire hs_canvas,vs_canvas,de_canvas;
wire [23:0] canvas_rgb;
wire first_video=pixel_visible && active_scene_video[1:0]==0;
reg [1:0] applied_fit_video;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)applied_fit_video<=0;else applied_fit_video<={applied_fit_video[0],fit_applied};
end
assign hs_canvas=hs;assign vs_canvas=vs;assign de_canvas=native_de_pipe[20];
assign canvas_rgb=de?vout_data_raw:24'd0;
video_timing_data video_timing_data_m0(.split_video(movie_split_active),
    .frame_enable(frame_enable_sync[1]),
    // PREVIEW pauses playback; it uses the same full-size canvas as AUTO.
    .mode_hd(resolution_mode),.small_view(1'b0),.display_de(native_de_0),
    .firstpage(first_video),.fit(applied_fit_video[1] || movie_display_video),
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// Image adjustment -> text -> spectrum -> common final fade envelope.
wire hs_adj,vs_adj,de_adj,hs_spec,vs_spec,de_spec,hs_final,vs_final,de_final;
wire [23:0] adjusted_rgb,osd_rgb,spectrum_rgb,transition_rgb;
wire hs_transition,vs_transition,de_transition;
wire [95:0] spectrum_levels;
wire spectrum_enabled=pixel_visible && !intro_visible && !menu_open_sync[1] &&
 ((movie_split_active && active_scene_video[38:37]!=0) ||
 (active_scene_video[3:2]!=3 && (active_scene_video[38:37]==2 ||
 (active_scene_video[38:37]==1 && active_scene_video[3:2]==2))));
wire viewport_consume;
assign viewport_consume=video_read_en;
wire rotation_hs,rotation_vs,rotation_de;
wire [23:0] rotation_rgb;
wire rotation_want,rotation_release,rotation_grant,rotation_valid,rotation_rd;
wire [20:0] rotation_addr;
wire [15:0] rotation_misses;
reg [1:0] opening_ready_video;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)opening_ready_video<=0;else opening_ready_video<={opening_ready_video[0],opening_audio_ready || audio_stream_fault};
end
exhibit_rotation_v34 #(.ENABLE_BRAND_INTRO(1)) rotation(
 .mem_clk(ext_mem_clk),.mem_rst(rst_mem),.video_clk(video_clk),.video_rst(rst_video),
 .enable(display_valid),.firstpage(first_video && !movie_display_video),.mode_hd(resolution_mode),.fit(applied_fit_video[1]),
 .hs(hs_canvas),.vs(vs_canvas),.de(de_canvas),.rgb(canvas_rgb),
 .ohs(rotation_hs),.ovs(rotation_vs),.ode(rotation_de),.orgb(rotation_rgb),
 .want(rotation_want),.release_bus(rotation_release),.grant(rotation_grant),.mem_busy(Sdr_busy),.refresh(Sdr_init_ref_vld),
 .mem_valid(rotation_valid),.mem_data(Sdr_rd_dout),.rd_en(rotation_rd),.rd_addr(rotation_addr),.missed_groups(rotation_misses),
 .intro_request(intro_request),.intro_ready(active_gain_video==256 && opening_ready_video[1]),.intro_frame_gray(intro_frame_gray),
 .intro_visible(intro_visible),.intro_presented(intro_presented),.decoder_fault(intro_decoder_fault));
exhibit_video_adjust adjust(
 .clk(video_clk),.rst(rst_video),.mode_hd(resolution_mode),.hs(rotation_hs),.vs(rotation_vs),.de(rotation_de),.visible(pixel_visible),
 .small_view(1'b0),.profile(active_scene_video[15:14]),
 .brightness_code(active_scene_video[22:16]),.contrast_percent(active_scene_video[30:23]),.rgb(rotation_rgb),
 .ohs(hs_adj),.ovs(vs_adj),.ode(de_adj),.orgb(adjusted_rgb)
);
wire movie_stats_active=movie_display_video && active_scene_video[3:2]==3 && !intro_visible;
wire [6:0] movie_actual_fps;wire movie_actual_fps_valid;
exhibit_movie_fps_v38 movie_fps_meter(.clk(video_clk),.rst(rst_video),.mode_hd(resolution_mode),
 .enable(movie_stats_active),.vs(vs_adj),.de(de_adj),.frame_id(movie_frame_video),
 .fps(movie_actual_fps),.valid(movie_actual_fps_valid));
exhibit_native_osd_v38 #(.INTRO_SUPPRESSION(1)) osd(.video_split(movie_split_active),.video_split_setting(movie_status_video[54]),.audio_settings(movie_status_video[53:44]),.movie_available(movie_available_video[1]),
 .movie_active(movie_stats_active),.movie_progress(movie_status_video[43:36]),.movie_seeking(movie_status_video[35]),.bgm_select(movie_status_video[34:33]),.movie_status(movie_status_video[32:0]),.movie_fps(movie_actual_fps),.movie_fps_valid(movie_actual_fps_valid),
 .clk(video_clk),.rst(rst_video),.mode_hd(resolution_mode),.menu_open(menu_open_sync[1]),.cursor(menu_cursor_sync),.fit_enabled(fit_sync[1]),
 .options({active_scene_video[47:23],screen_brightness}),.scene(osd_scene),.diagnostic(diagnostic_s1),.ready_mask(ready_s1),.image_crc(image_last_crc),
 .hs_in(hs_adj),.vs_in(vs_adj),.de_in(de_adj),.rgb_in(adjusted_rgb),.intro_active(intro_visible || active_scene_video[3:2]==3),
 .hs_out(hs_osd),.vs_out(vs_osd),.de_out(de_osd),.rgb_out(osd_rgb)
);
exhibit_fft256 spectrum(.clk(video_clk),.rst(rst_video),.enable(spectrum_enabled),.sample_valid(audio_valid),.sample(audio_left_data[23:8]),.levels(spectrum_levels),.spectrum_valid());
exhibit_spectrum_osd spectrum_osd(.split_video(movie_split_active),.clk(video_clk),.rst(rst_video),.mode_hd(resolution_mode),.hs(hs_osd),.vs(vs_osd),.de(de_osd),
 .enable(spectrum_enabled),
 .rgb(osd_rgb),.levels(spectrum_levels),
 .ohs(hs_spec),.ovs(vs_spec),.ode(de_spec),.orgb(spectrum_rgb));
wire hs_caption,vs_caption,de_caption;
wire [23:0] caption_rgb;
exhibit_caption_osd captions(.source_clk(sd_card_clk),.source_rst(rst_sd),.source_cue(audio_caption_id),
 .clk(video_clk),.rst(rst_video),.mode_hd(resolution_mode),
 .enable(pixel_visible && !intro_visible && !menu_open_sync[1] && active_scene_video[36] && active_scene_video[3:2]==2),
 .hs(hs_spec),.vs(vs_spec),.de(de_spec),.rgb(spectrum_rgb),
 .ohs(hs_caption),.ovs(vs_caption),.ode(de_caption),.orgb(caption_rgb));
wire [8:0] intro_handoff_gain;
wire intro_override_effect;
exhibit_intro_handoff_v35 intro_handoff(.clk(video_clk),.rst(rst_video),.mode_hd(resolution_mode),.vs(vs_caption),
 .intro_visible(intro_visible),.tail_request(intro_tail_fade),.gain(intro_handoff_gain),.override_effect(intro_override_effect),.black_ready(intro_black_ready),.done(intro_handoff_done));
reg [8:0] movie_gain;reg movie_vs_d;
reg movie_picture_latched;
assign movie_picture_ready=movie_picture_latched;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin movie_gain<=0;movie_vs_d<=0;movie_picture_latched<=0;end
 else begin
  movie_vs_d<=vs_caption;
  if(active_scene_video[3:2]!=3)begin movie_gain<=0;movie_picture_latched<=0;end
  else begin
   if(movie_vs_d && !vs_caption && movie_display_video && movie_gain<256)movie_gain<=movie_gain>=240?256:movie_gain+16;
   if(movie_display_video && de_caption && movie_gain==256 && active_gain_video==256)movie_picture_latched<=1;
  end
 end
end
wire [8:0] exhibit_gain=active_gain_video<intro_handoff_gain?active_gain_video:intro_handoff_gain;
wire [8:0] movie_gate_gain=movie_display_video?movie_gain:9'd0;
wire [8:0] final_scene_gain_next=active_scene_video[3:2]==3 && movie_gate_gain<exhibit_gain?movie_gate_gain:exhibit_gain;
// Gains change in vertical blank; register their selection ahead of pixel DSPs.
reg [8:0] final_scene_gain;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)final_scene_gain<=0;else final_scene_gain<=final_scene_gain_next;
end
exhibit_video_transition_v37 fade(.clk(video_clk),.rst(rst_video),.mode_hd(resolution_mode),.effect((intro_override_effect || active_scene_video[3:2]==3)?3'd0:active_scene_video[35:33]),
 .hs(hs_caption),.vs(vs_caption),.de(de_caption),.rgb(caption_rgb),
 .gain(pixel_visible?final_scene_gain:9'd256),.ohs(hs_transition),.ovs(vs_transition),.ode(de_transition),.orgb(transition_rgb));

exhibit_screen_brightness brightness_control(
 .clk(video_clk),.config_rst(reset_request),.video_rst(rst_video),.vs(vs_transition),
 .payload(brightness_payload),.request_toggle(brightness_toggle),.ack(brightness_ack),
 .applied(screen_brightness),.gain(screen_gain));
// This is the final visual stage: image, captions, menu and spectrum all dim.
exhibit_video_gain global_dim(.clk(video_clk),.rst(rst_video),
 .hs(hs_transition),.vs(vs_transition),.de(de_transition),.rgb(transition_rgb),.gain(screen_gain),
 .ohs(hs_final),.ovs(vs_final),.ode(de_final),.orgb(vout_data));

generate if(ENABLE_INTERNAL_DIAGNOSTICS)begin: optional_integrity
exhibit_pixel_integrity image_integrity(
 .clk(video_clk),.rst(rst_video),.hs(hs_final),.vs(vs_final),.de(de_final),.rgb(vout_data),
 .theme(active_scene_video[1:0]),
 .eligible(resolution_mode && pixel_visible && active_scene_video[3:2]!=1 &&
           active_scene_video[15:14]==0 && active_scene_video[30:23]==8'd100 && screen_brightness==7'd100 &&
           active_gain_video==256 && !menu_open_sync[1] && !spectrum_enabled),
 .bad_frames(pixel_bad_frames),.checked_frames(pixel_checked_frames),.last_crc(image_last_crc));
end else begin: no_hidden_statistics
 assign pixel_bad_frames=0;assign pixel_checked_frames=0;assign image_last_crc=0;
end endgenerate

exhibit_frame_cache_v37 #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (720),.ENABLE_BRAND_INTRO(1)
) frame_read_write_m0(.movie_split_read(movie_split_read),.movie_split_display(movie_split_active),.movie_read(movie_read_mem),.movie_display(movie_display_video),.movie_write(movie_write_active),.movie_write_slot(movie_write_slot),.movie_read_slot(movie_read_slot),
    // Select image format by output resolution, independently of UI mode.
    .small_view(!resolution_mode),
    .video_rst(rst_video),.packed_read(resolution_mode),
    .first_video(first_video),.fit(fit_applied),
    .intro_valid(intro_asset_valid),.intro_checked(intro_asset_checked),
    .anim_want(rotation_want),.anim_release(rotation_release),.anim_grant(rotation_grant),
    .anim_rd_en(rotation_rd),.anim_rd_addr(rotation_addr),.anim_valid(rotation_valid),
    .underflows(read_underflows),.overflows(read_overflows),
    .mem_clk           (ext_mem_clk),
    .rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (read_req_mem),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (2*FRAME_PIXELS),
    .read_addr_3       (3*FRAME_PIXELS),
    .read_addr_index   (selected_read_buf),
    .read_len          (FRAME_PIXELS),
    .read_en           (viewport_consume && pixel_visible),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (2*FRAME_PIXELS),
    .write_addr_3      (3*FRAME_PIXELS),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// Audio now comes from indexed TF PCM through the player's BRAM32K FIFO.

wire raw_audio_valid;
wire [23:0] raw_audio_left,raw_audio_right;
I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (rst_video),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (raw_audio_valid),
    .O_audio_left_data  (raw_audio_left),
    .O_audio_right_data (raw_audio_right)
);

wire eq_audio_valid;wire [23:0] eq_audio_left,eq_audio_right;
reg [7:0] applied_eq;reg eq_hold;
wire [7:0] desired_eq=movie_status_video[53:46];
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin applied_eq<={2'd0,3'd4,3'd4};eq_hold<=0;end
 else if(applied_eq!=desired_eq)begin
  eq_hold<=1;
  if(movie_output_gain==0)begin applied_eq<=desired_eq;eq_hold<=0;end
 end else eq_hold<=0;
end
exhibit_audio_eq_v48 equalizer(.clk(video_clk),.rst(rst_video),.sample_valid(raw_audio_valid),
 .left_in(raw_audio_left),.right_in(raw_audio_right),.bass(applied_eq[2:0]),.treble(applied_eq[5:3]),.effect(applied_eq[7:6]),
 .sample_out_valid(eq_audio_valid),.left_out(eq_audio_left),.right_out(eq_audio_right));
wire [8:0] volume_gain;
exhibit_percent_gain volume_percent(.clk(video_clk),.rst(rst_video),.percent({1'b0,active_scene_video[45:39]}),.gain(volume_gain));
reg [8:0] audio_target_gain;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)audio_target_gain<=0;
 // Image transitions never change the music level. The volume control and
 // initial-media mute keep their existing sample-by-sample slew.
 else audio_target_gain<=pixel_visible && !eq_hold && !(movie_display_video && movie_pause_gain_sync[1])?volume_gain:9'd0;
end
exhibit_audio_gain audio_fade(.clk(video_clk),.rst(rst_video),.sample_valid(eq_audio_valid),.left_in(eq_audio_left),.right_in(eq_audio_right),
 .target_gain(audio_target_gain),.applied_gain(movie_output_gain),.sample_out_valid(audio_valid),.left_out(audio_left_data),.right_out(audio_right_data));

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .mode_hd(resolution_mode),
    .I_vs          (vs_final),
    .I_de          (de_final),
    .I_rgb         (vout_data),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_video),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
wire [9:0] hi_ch0,hi_ch1,hi_ch2,hi_clk;
assign tmds_ch0_data=hi_ch0;
assign tmds_ch1_data=hi_ch1;
assign tmds_ch2_data=hi_ch2;
assign tmds_clk_data=hi_clk;
// DDC remains idle, matching the accepted720p mode. No EDID autodetection.
assign HDMI_DDC_SCL=1'b1;
assign HDMI_DDC_SDA=1'bz;
assign axis_s_ready=1'b0;
assign edid_valid=1'b0;
assign edid_data=8'd0;
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 1980        ),
    .HSA                    ( 40         ),
    .HFP                    ( 440         ),
    .HBP                    ( 220         ),
    .HACTIVE                ( 1280        ),
    .VTOTAL                 ( 750        ),
    .VSA                    ( 5          ),
    .VFP                    ( 5         ),
    .VBP                    ( 20         ),
    .VACTIVE                ( 720        ),
    .VIDEO_VIC              ( 19         ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_hd_core(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_video),
    .I_edid_read_trig   (1'b0),
    .O_edid_read_valid  (),
    .O_edid_read_data   (),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready_hd),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (),
    .IO_ddc_sda         (),

    .O_ch0_tmds_data    (hi_ch0),
    .O_ch1_tmds_data    (hi_ch1),
    .O_ch2_tmds_data    (hi_ch2),
    .O_clk_tmds_data    (hi_clk)
);

hdmi_phy_wrapper_v37 #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_video),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule










