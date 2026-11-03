module exhibit_player_v37 #(
 parameter integer CLK_HZ=50_000_000, USE_EVENT_INPUTS=0,USE_BOOT_STATE=0,USE_NATIVE_SD=0,USE_TF_AUDIO=0,USE_BRAND_INTRO=0
)(
 input clk,rst,key_next,key_select,write_finish_toggle,publish_ack_toggle,adaptive_enable,
 input [1:0] boot_theme,boot_mode,output [1:0] current_theme,current_mode,
 output [3:0] state_code,error_detail,ready_mask,
 output display_valid,output [1:0] write_slot,
 output [47:0] publish_scene,output publish_toggle,
 output write_req,input write_req_ack,output write_en,output [31:0] write_data,
 inout SD_nCS,SD_MOSI,output SD_DCLK,input SD_MISO,SD_DAT1,SD_DAT2,
 output [31:0] diagnostic,output debug_sd_request,
 input next_action,select_action,style_action,input [31:0] options,
 input audio_clk,audio_rst,audio_scene_ready,output audio_bclk,audio_lrck,audio_dout,
 output audio_narrating,audio_fault,output [3:0] audio_error,output [5:0] audio_caption_id,input boot_hold,
 input [1:0] bgm_select,output [1:0] bgm_count,
 input [1:0] movie_speed,
 input movie_start,movie_exit,movie_pause_toggle,movie_forward,movie_backward,movie_output_muted,movie_picture_ready,display_ack_toggle,
 output movie_paused,movie_seeking,output [7:0] movie_progress,output [15:0] movie_elapsed_bcd,movie_duration_bcd,
 output movie_available,movie_play,movie_write_active,movie_write_slot,movie_publish_toggle,movie_publish_slot,output [15:0] movie_publish_frame,
 input opening_arm,opening_play,exclusive_opening,output opening_ready,opening_done,opening_available
);
wire style_press,next_press,select_press,sd_ready,media_ready,media_fault,fault;
wire scan_start,scan_done,found_valid,load_start,pixel_valid;
wire [31:0] found_handle,load_handle,sd_addr,image_sd_addr,audio_sd_addr;
wire [2:0] found_total;
wire [3:0] media_error,media_state;
wire [23:0] pixel;
wire [7:0] sd_data;
wire sd_req,sd_valid,sd_end,image_sd_req,audio_sd_req;
wire movie_active=current_mode==3;
wire movie_meta_available,movie_audio_ready,movie_audio_done,movie_fault,movie_displayed;
wire [23:0] movie_consumed;wire [31:0] movie_lba;wire [15:0] movie_frames;
wire movie_sd_req,movie_req_write,movie_pixel_valid;wire [31:0] movie_sd_addr;wire [23:0] movie_pixel;
(* async_reg="true" *)reg [1:0] picture_sync;reg movie_playing;
always @(posedge clk or posedge rst)begin
 if(rst)begin picture_sync<=0;movie_playing<=0;end
 else begin picture_sync<={picture_sync[0],movie_picture_ready};if(!movie_active || (movie_seeking && !seek_fading))movie_playing<=0;else if(movie_displayed && picture_sync[1] && movie_audio_ready)movie_playing<=1;end
end
wire movie_allow_audio;
wire seek_apply,seek_audio_ack,seek_video_ack,seek_picture_ready,seek_restart,seek_fading;
wire movie_ended=movie_audio_done && !movie_seeking && !movie_forward && !movie_backward;
wire [11:0] seek_frame,current_frame;
wire [23:0] seek_samples,seek_sector_offset;
exhibit_movie_seek_v47 seek_control(.clk(clk),.rst(rst),.active(movie_active),
 .forward(movie_forward),.backward(movie_backward),.current_frame(current_frame),.total_frames(movie_frames[11:0]),
 .output_muted(movie_output_muted),.audio_ack(seek_audio_ack),.video_ack(seek_video_ack),
 .audio_ready(movie_audio_ready),.picture_ready(seek_picture_ready),.fault(movie_fault || audio_fault),
 .busy(movie_seeking),.apply(seek_apply),.fading(seek_fading),.restart(seek_restart),.frame(seek_frame),.samples(seek_samples),.sector_offset(seek_sector_offset));
exhibit_movie_transport_v39 transport(.clk(clk),.rst(rst),.active(movie_active),
 .toggle_pause(movie_pause_toggle),.seek_restart(seek_restart),.current_frame(current_frame),.progress(movie_progress),.exit_request(movie_exit || next_press),
 .ended(movie_ended || movie_fault || audio_fault),.output_muted(movie_output_muted),
 .consumed_samples(movie_consumed),.total_frames(movie_frames),.paused(movie_paused),
 .allow_audio(movie_allow_audio),.elapsed_bcd(movie_elapsed_bcd),.duration_bcd(movie_duration_bcd));
assign movie_play=movie_playing && movie_allow_audio && (!movie_seeking || seek_fading);
assign movie_available=movie_meta_available && !audio_fault;
wire audio_index_valid;
wire narration_done;
wire [31:0] audio_index_lba,fs_begin,fs_end,fs_data;
wire audio_owner,movie_owner,audio_prefetch_hold;
exhibit_sd_arbiter_v37 sector_arbiter(.clk(clk),.rst(rst),.display_valid(display_valid),
 .image_req(image_sd_req),.image_addr(image_sd_addr),.audio_req(audio_sd_req),.audio_addr(audio_sd_addr),
 .movie_req(movie_sd_req),.movie_addr(movie_sd_addr),.sd_end(sd_end),.audio_hold(audio_prefetch_hold),
 .audio_owner(audio_owner),.movie_owner(movie_owner),.sd_req(sd_req),.sd_addr(sd_addr));
assign debug_sd_request=sd_req;
wire transport_fault;
wire [3:0] transport_error;
wire [5:0] transport_command;
wire [1:0] transport_command_error;
wire [31:0] media_diagnostic;
assign diagnostic=transport_fault?{8'hd4,2'd0,transport_command,8'd0,
 2'd0,(transport_error==1?transport_command_error:2'd0),transport_error}:media_diagnostic;
generate if(USE_EVENT_INPUTS)begin
 assign next_press=next_action;assign select_press=select_action;assign style_press=style_action;
end else begin
 exhibit_key_debounce #(.CLK_FREQ_HZ(CLK_HZ)) next_key(clk,rst,key_next,next_press);
 exhibit_select_key #(.CLK_HZ(CLK_HZ)) select_key(clk,rst,key_select,select_press,style_press);
end endgenerate
assign write_en=movie_write_active?movie_pixel_valid:pixel_valid;
assign write_data={movie_write_active?movie_pixel:pixel,8'd0};
exhibit_movie_stream_v37 movie_reader(.movie_speed(movie_speed),.clk(clk),.rst(rst),.active(movie_active),.available(movie_available),.play_audio(movie_play),
 .seek_request(seek_apply),.seek_frame(seek_frame),.seek_samples(seek_samples),.seek_sector_offset(seek_sector_offset),.seek_ack(seek_video_ack),.seek_picture_ready(seek_picture_ready),.current_frame(current_frame),
 .base_lba(movie_lba),.total_frames(movie_frames),.consumed_samples(movie_consumed),.write_ack(write_req_ack),.write_done_toggle(write_finish_toggle),.display_ack_toggle(display_ack_toggle),
 .sd_req(movie_sd_req),.sd_addr(movie_sd_addr),.sd_data(sd_data),.sd_valid(sd_valid && movie_owner),.sd_end(sd_end && movie_owner),
 .write_req(movie_req_write),.write_active(movie_write_active),.write_slot(movie_write_slot),.pixel_valid(movie_pixel_valid),.pixel(movie_pixel),
 .publish_toggle(movie_publish_toggle),.publish_slot(movie_publish_slot),.publish_frame(movie_publish_frame),.displayed(movie_displayed),.fault(movie_fault));
wire image_write_req;
assign write_req=movie_write_active?movie_req_write:image_write_req;
assign state_code=fault?4'he:media_state;
exhibit_control_v37 #(.CLK_HZ(CLK_HZ),.FRAME_WORDS(921600),.REQUIRE_ALL_READY(1),.USE_BOOT_STATE(USE_BOOT_STATE),.HAS_AUDIO_HOLD(USE_TF_AUDIO),.HAS_BOOT_HOLD(USE_BRAND_INTRO),.ONE_SHOT_NARRATION(USE_TF_AUDIO)) control(.movie_start(movie_start && movie_available),.movie_done(movie_exit || movie_ended || movie_fault || (movie_active && audio_fault)),
 .clk(clk),.rst(rst),.options(options),.sd_ready(sd_ready),.media_ready(media_ready),.media_fault(media_fault|transport_fault),.media_error(transport_fault?4'he:media_error),
 .scan_done(scan_done),.found_valid(found_valid),.found_handle(found_handle),.found_total(found_total),
 .pixel_valid(pixel_valid),.write_finish_toggle(write_finish_toggle),.key_next(next_press),.key_select(select_press),.key_style(style_press),
 .publish_ack_toggle(publish_ack_toggle),.scan_start(scan_start),.load_start(load_start),.load_handle(load_handle),
 .write_slot(write_slot),.ready_mask(ready_mask),.publish_scene(publish_scene),.publish_toggle(publish_toggle),
 .display_valid(display_valid),.fault(fault),.error_detail(error_detail),.mode(current_mode),.theme(current_theme),.boot_theme(boot_theme),.boot_mode(boot_mode),.detail_audio_active(audio_narrating),.detail_audio_done(narration_done),.boot_hold(boot_hold)
);
fat32_bmp_media_v37 #(.TIMEOUT_CYCLES(CLK_HZ),.HD_FILES_ONLY(1),.SCALE_TO_HD(1),.SCAN_AUDIO_INDEX(USE_TF_AUDIO)) media(
 .clk(clk),.rst(rst),.scan_start(scan_start),.scan_start_sector(32'd0),.scan_max_sector(32'd131071),.scan_target_count(3'd4),
 .ready(media_ready),.scan_done(scan_done),.scan_found_valid(found_valid),.scan_found_sector(found_handle),.scan_found_total(found_total),
 .load_start(load_start),.load_sector(load_handle),.sd_init_done(sd_ready),.adaptive_enable(adaptive_enable),.state_code(media_state),.bmp_width(16'd1280),.bmp_height(16'd720),
 .write_req(image_write_req),.write_req_ack(write_req_ack),.sd_sec_read(image_sd_req),.sd_sec_read_addr(image_sd_addr),
 .sd_sec_read_data(sd_data),.sd_sec_read_data_valid(sd_valid && !display_valid),.sd_sec_read_end(sd_end && !display_valid),
 .bmp_data_wr_en(pixel_valid),.bmp_data(pixel),.fault(media_fault),.error_detail(media_error),.diagnostic(media_diagnostic),
 .audio_index_valid(audio_index_valid),.audio_index_lba(audio_index_lba),.fs_begin(fs_begin),.fs_end(fs_end),.fs_data(fs_data)
);

generate if(USE_TF_AUDIO)begin:tf_audio
wire [12:0] fifo_used;wire [10:0] bgm_fifo_used;
wire fifo_clear,fifo_write,fifo_full,fifo_empty,fifo_pop;
wire [31:0] fifo_data,pcm_data;
wire bgm_clear,bgm_write,bgm_full,bgm_empty,bgm_read_reset,mixed_empty;
wire [31:0] bgm_write_data,bgm_pcm,mixed_pcm;
wire fifo_read_reset;
wire voice_pop,voice_pop_request,bgm_pop,voice_is_opening;
wire [2:0] speed_status;wire [31:0] speed_pcm;wire bgm_switch_hold,bgm_muted;
wire [24:0] audio_position;
wire [2:0] audio_track;
(* async_reg="true" *) reg [2:0] scene_ready_sync;
always @(posedge clk or posedge rst)begin
 if(rst)scene_ready_sync<=0;else scene_ready_sync<={scene_ready_sync[1:0],audio_scene_ready};
end
media_reset_sync pcm_reset(audio_clk,rst|audio_rst|fifo_clear,fifo_read_reset);
media_reset_sync bgm_reset(audio_clk,rst|audio_rst|bgm_clear,bgm_read_reset);
exhibit_tf_audio_v37 #(.TIMEOUT_CYCLES(CLK_HZ),.VOICE_FIFO_BITS(12)) stream(
 .bgm_select(bgm_select),.bgm_count(bgm_count),.bgm_muted(bgm_muted),.bgm_switch_hold(bgm_switch_hold),
 .clk(clk),.rst(rst),.enable(display_valid && !fault),.index_valid(audio_index_valid),.index_lba(audio_index_lba),.scene_ready(scene_ready_sync[2]),
 .fs_begin(fs_begin),.fs_end(fs_end),.fs_data(fs_data),.mode(current_mode),.theme(current_theme),
 .sd_req(audio_sd_req),.sd_addr(audio_sd_addr),.sd_data(sd_data),.sd_valid(sd_valid && audio_owner),.sd_end(sd_end && audio_owner),
 .fifo_used(fifo_used),.fifo_full(fifo_full),.fifo_clear(fifo_clear),.fifo_write(fifo_write),.fifo_data(fifo_data),
 .bgm_fifo_used(bgm_fifo_used),.bgm_fifo_full(bgm_full),.bgm_fifo_clear(bgm_clear),.bgm_fifo_write(bgm_write),.bgm_fifo_data(bgm_write_data),
 .narrating(audio_narrating),.fault(audio_fault),.error_code(audio_error),.narration_done(narration_done),
 .position_bytes(audio_position),.playing_track(audio_track),
 .movie_arm(movie_active),.seek_request(seek_apply),.seek_samples(seek_samples),.seek_ack(seek_audio_ack),.movie_play(movie_play),.movie_prefetch_hold(audio_prefetch_hold),.movie_available(movie_meta_available),.movie_ready(movie_audio_ready),.movie_done(movie_audio_done),.movie_consumed(movie_consumed),.movie_lba(movie_lba),.movie_frames(movie_frames),
 .opening_arm(opening_arm),.opening_play(opening_play),.opening_ready(opening_ready),.opening_done(opening_done),.voice_is_opening(voice_is_opening),.opening_available(opening_available));
exhibit_caption_track caption_timing(.clk(clk),.rst(rst),.active(audio_narrating && !audio_fault),
 .clear(fifo_clear),.track(audio_track),.position_bytes(audio_position),.fifo_used(fifo_used[10:0]),.cue(audio_caption_id));
// Data is immaterial when wr_en=0. Keep one qualifying logic stage on
// the very short RAM input path; no sample or write cycle is changed.
(* keep="true" *) wire [31:0] voice_fifo_data=fifo_data & {32{fifo_write}};
exhibit_pcm_fifo #(.ADDR_BITS(12),.RAM_KIND("9K")) audio_fifo(.wr_clk(clk),.wr_rst(rst|fifo_clear),.wr_en(fifo_write),.wr_data(voice_fifo_data),.wr_used(fifo_used),.wr_full(fifo_full),
 .rd_clk(audio_clk),.rd_rst(fifo_read_reset),.rd_pop(voice_pop),.rd_data(pcm_data),.rd_empty(fifo_empty));
exhibit_pcm_fifo music_fifo(.wr_clk(clk),.wr_rst(rst|bgm_clear),.wr_en(bgm_write),.wr_data(bgm_write_data),.wr_used(bgm_fifo_used),.wr_full(bgm_full),
 .rd_clk(audio_clk),.rd_rst(bgm_read_reset),.rd_pop(bgm_pop),.rd_data(bgm_pcm),.rd_empty(bgm_empty));
exhibit_movie_status_bridge_v39 #(.WIDTH(3)) speed_bridge(.source_clk(clk),.source_rst(rst),
 .payload({movie_active,movie_speed}),.video_clk(audio_clk),.video_rst(audio_rst),.vs(audio_lrck),.status(speed_status));
exhibit_audio_speed_v48 speed_control(.clk(audio_clk),.rst(fifo_read_reset),.enable(speed_status[2]),.speed(speed_status[1:0]),
 .consume(voice_pop_request),.empty(fifo_empty|fifo_read_reset),.pcm(pcm_data),.out_pcm(speed_pcm),.pop(voice_pop));
exhibit_live_mix_v35 mixer(.bgm_mute(bgm_switch_hold),.bgm_muted(bgm_muted),.clk(audio_clk),.rst(audio_rst),.sample_tick(fifo_pop),.duck(current_mode==2),
 .bgm(bgm_pcm),.voice(speed_pcm),.bgm_empty(bgm_empty|bgm_read_reset),.voice_empty(fifo_empty|fifo_read_reset),.mixed(mixed_pcm),.empty(mixed_empty),
 .exclusive_opening(exclusive_opening || movie_active || picture_sync[1]),.opening_play(opening_play || movie_play),.voice_is_opening(voice_is_opening),.bgm_pop(bgm_pop),.voice_pop(voice_pop_request));
exhibit_pcm_i2s serializer(.clk(audio_clk),.rst(audio_rst),.pcm(mixed_pcm),.empty(mixed_empty),
 .pop(fifo_pop),.bclk(audio_bclk),.lrck(audio_lrck),.dout(audio_dout));
end else begin:no_tf_audio
assign bgm_count=1;
assign seek_audio_ack=0;assign movie_meta_available=0;assign movie_audio_ready=0;assign movie_audio_done=0;assign movie_consumed=0;assign movie_lba=0;assign movie_frames=0;
assign audio_sd_req=0;assign audio_sd_addr=0;assign audio_narrating=0;assign audio_fault=0;assign audio_error=0;
assign narration_done=0;assign audio_caption_id=0;assign opening_ready=1;assign opening_done=1;assign opening_available=0;
hdmi_audio_tone_i2s_64fs tone(.I_mclk(audio_clk),.I_rst(audio_rst),.O_i2s_BCLK(audio_bclk),.O_i2s_LRCK(audio_lrck),.O_i2s_DOUT(audio_dout));
end endgenerate
generate if(USE_NATIVE_SD)begin:native_sd
wire dat3_hold_high;
assign SD_nCS=dat3_hold_high?1'b1:1'bz;
sd_native4_card card(
 .clk(clk),.rst(rst),.sd_clk(SD_DCLK),.sd_cmd(SD_MOSI),.sd_dat({SD_nCS,SD_DAT2,SD_DAT1,SD_MISO}),
 .read_req(sd_req),.read_lba(sd_addr),.init_done(sd_ready),.read_data(sd_data),
 .read_valid(sd_valid),.read_end(sd_end),.fault(transport_fault),.error_code(transport_error),
 .physical_reads(),.cache_hits(),.dat3_hold_high(dat3_hold_high),
 .debug_command(transport_command),.debug_command_error(transport_command_error));
end else begin:spi_sd
assign transport_fault=1'b0;
assign transport_error=4'd0;
assign transport_command=6'd0;
assign transport_command_error=2'd0;
sd_card_top card(
 .clk(clk),.rst(rst),.SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),.SD_MOSI(SD_MOSI),.SD_MISO(SD_MISO),
 .sd_init_done(sd_ready),.sd_sec_read(sd_req),.sd_sec_read_addr(sd_addr),.sd_sec_read_data(sd_data),.sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),
 .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(),.sd_sec_write_data_req(),.sd_sec_write_end()
);
end endgenerate
endmodule
