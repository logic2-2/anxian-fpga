// Independent Jazz and narration FIFOs share one checked SD sector reader.
module exhibit_tf_audio_v37 #(parameter integer TIMEOUT_CYCLES=50_000_000,OPEN_PREFILL=512,VOICE_FIFO_BITS=10)(
 input [1:0] bgm_select,input bgm_muted,output reg [1:0] bgm_count,output reg bgm_switch_hold,
 input clk,rst,enable,index_valid,scene_ready,input [31:0] index_lba,fs_begin,fs_end,fs_data,
 input [1:0] mode,theme,output reg sd_req,output reg [31:0] sd_addr,
 input [7:0] sd_data,input sd_valid,sd_end,
 input [VOICE_FIFO_BITS:0] fifo_used,input [10:0] bgm_fifo_used,input fifo_full,bgm_fifo_full,
 output reg fifo_clear,fifo_write,output reg [31:0] fifo_data,
 output reg bgm_fifo_clear,bgm_fifo_write,output [31:0] bgm_fifo_data,
 output reg narrating,fault,narration_done,output reg [3:0] error_code,
 output [24:0] position_bytes,output [2:0] playing_track,
 input seek_request,input [23:0] seek_samples,output reg seek_ack,
 input movie_arm,movie_play,output movie_prefetch_hold,output movie_available,movie_ready,movie_done,output [23:0] movie_consumed,
 output [31:0] movie_lba,output [15:0] movie_frames,
 input opening_arm,opening_play,output opening_ready,opening_done,voice_is_opening,opening_available
);
localparam WAIT=0,INDEX_REQ=1,INDEX_RX=2,INDEX_CHECK=3,CLEAR=4,PLAY=5,
 DATA_RX=6,GAP=7,BGM_CLEAR=8,FAIL=9,BASE_WAIT=10,BASE_GET=11,LENGTH_WAIT=12,LENGTH_GET=13,ISSUE=15;
reg [3:0] state;reg seek_seen;
reg has_bgm,bgm_metadata_bad,bgm_rebuffer;
reg [1:0] bgm_metadata_count,bgm_applied;
(* async_reg="true" *)reg [1:0] bgm_muted_sync;
wire [1:0] requested_bgm=bgm_select<bgm_count?bgm_select:2'd0;
always @(posedge clk or posedge rst)begin
 if(rst)bgm_muted_sync<=0;else bgm_muted_sync<={bgm_muted_sync[0],bgm_muted};
end
reg [9:0] received;
reg [31:0] crc,expected_crc,word_shift;
wire [31:0] complete_word={sd_data,word_shift[31:8]};
reg metadata_bad,opening_metadata_bad,has_opening,index_checked,opening_requested,opening_finished;
// Register the outgoing level before its2-FF audio-clock synchronizer. The
// applied-track/rebuffer handoff must not create a combinational unmute pulse.
always @(posedge clk or posedge rst)begin
 if(rst)bgm_switch_hold<=0;
 else bgm_switch_hold<=enable && index_checked && (requested_bgm!=bgm_applied || bgm_rebuffer);
end
reg has_movie,movie_bad,movie_requested,movie_finished;reg [23:0] movie_audio_base;reg [24:0] movie_audio_len;
// Valid MV15 clips have at most2621 frames and the volume is below2^24 sectors.
reg [23:0] movie_lba24;reg [11:0] movie_frame_count;
assign movie_lba={8'd0,movie_lba24};assign movie_frames={4'd0,movie_frame_count};
reg [21:0] movie_sectors;reg [23:0] movie_samples;
reg [24:0] movie_video_end,movie_audio_end;reg [25:0] movie_expected_len;
wire [31:0] movie_sectors_next=({16'd0,movie_frames}<<10)-({16'd0,movie_frames}<<7)+({16'd0,movie_frames}<<2);
wire [31:0] movie_samples_next=({16'd0,movie_frames}<<11)+({16'd0,movie_frames}<<10)+({16'd0,movie_frames}<<7);
// Descriptor fields arrive hundreds of clocks before INDEX_CHECK. Pipeline
// span arithmetic so validation does not form a multiplier/add/compare chain.
always @(posedge clk or posedge rst)begin
 if(rst)begin movie_sectors<=0;movie_samples<=0;movie_video_end<=0;movie_audio_end<=0;movie_expected_len<=0;end
 else begin
  movie_sectors<=movie_sectors_next;movie_samples<=movie_samples_next;
  movie_video_end<=movie_lba+movie_sectors;
  movie_audio_end<={8'd0,movie_audio_base}+(({7'd0,movie_audio_len}+511)>>9);
  movie_expected_len<=44+(movie_samples<<2);
 end
end
// Index-validation scratch registers become the persistent Jazz descriptor.
reg [23:0] entry_base,current_base;
reg [24:0] entry_length,current_length;
reg [2:0] track;
reg [24:0] byte_pos,bgm_position;
assign position_bytes=byte_pos;assign playing_track=track;
reg [23:0] held_sample;
reg [1:0] previous_mode,previous_theme;
reg pending_detail,loading_bgm,sector_voice,voice_exhausted,voice_finished;
// Batch movie audio to avoid interrupting the contiguous video stream for
// every128 samples. Legacy opening/narration refill behavior is unchanged.
localparam integer MOVIE_LOW=(1<<VOICE_FIFO_BITS)/4;
localparam integer MOVIE_HIGH=(1<<VOICE_FIFO_BITS)-(1<<VOICE_FIFO_BITS)/8;
reg movie_refilling;
always @(posedge clk or posedge rst)begin
 if(rst)movie_refilling<=1;
 else if(track!=6 || !movie_arm)movie_refilling<=1;
 else if(voice_exhausted || fifo_used>=MOVIE_HIGH)movie_refilling<=0;
 else if(fifo_used<=MOVIE_LOW)movie_refilling<=1;
end
assign movie_prefetch_hold=track==6 && movie_arm && movie_refilling && !voice_exhausted && !fault;
wire voice_needs_data=track==6?movie_refilling:(fifo_used<=896);

reg [5:0] clear_count;
reg [8:0] start_byte;
reg [9:0] stop_byte;
reg [$clog2(TIMEOUT_CYCLES)-1:0] timer;
wire desired_changed=(mode!=previous_mode || theme!=previous_theme);
wire [2:0] descriptor=received[6:4]-3'd2;
wire [24:0] track_end={1'b0,entry_base}+((entry_length+25'd511)>>9);
wire [24:0] selected_position=sector_voice?byte_pos:bgm_position;
wire [24:0] selected_length=sector_voice?current_length:entry_length;
wire [23:0] selected_base=sector_voice?current_base:entry_base;
reg table_write;
reg [3:0] table_wa,table_ra;
reg [24:0] table_wd;
wire [24:0] table_q;
assign opening_available=index_checked && has_opening;
assign opening_done=index_checked && (!has_opening || opening_finished);
assign voice_is_opening=track>=5;
assign movie_available=index_checked && has_movie && !movie_bad;
assign movie_ready=movie_available && track==6 && !fifo_clear && (fifo_used>=OPEN_PREFILL || (voice_exhausted && fifo_used!=0));
assign movie_done=movie_finished;
wire [VOICE_FIFO_BITS+1:0] voice_occupancy={1'b0,fifo_used}+fifo_write;
assign movie_consumed=track==6 && !fifo_clear && ((byte_pos-25'd44)>>2)>=voice_occupancy?((byte_pos-25'd44)>>2)-voice_occupancy:24'd0;
assign opening_ready=index_checked && (!has_opening || (track==5 && !fifo_clear &&
 (fifo_used>=OPEN_PREFILL || (voice_exhausted && fifo_used!=0))));

assign bgm_fifo_data=fifo_data;
// Use spare9K memory for descriptors, releasing32K for the Jazz PCM FIFO.
EG_LOGIC_BRAM #(.DATA_WIDTH_A(25),.DATA_WIDTH_B(25),.ADDR_WIDTH_A(4),.ADDR_WIDTH_B(4),
 .DATA_DEPTH_A(16),.DATA_DEPTH_B(16),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) track_table(
 .dia(table_wd),.addra(table_wa),.cea(1'b1),.ocea(1'b1),.clka(clk),.wea(table_write),.rsta(1'b0),.bea(1'b1),.doa(),
 .dib(25'd0),.addrb(table_ra),.ceb(1'b1),.oceb(1'b1),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b1),.dob(table_q));
task bad_descriptor;begin
 if(received<112)metadata_bad<=1;else opening_metadata_bad<=1;
end endtask
function [31:0] crc_byte;input [31:0] c;input [7:0] b;integer j;reg [31:0] q;begin
 q=c^{24'd0,b};for(j=0;j<8;j=j+1)q=(q>>1)^(q[0]?32'hedb88320:0);crc_byte=q;
end endfunction
task fail;input [3:0] code;begin
 fault<=1;error_code<=code;state<=FAIL;sd_req<=0;narrating<=0;fifo_clear<=1;bgm_fifo_clear<=1;
end endtask
task restart_voice;input [2:0] next_track;begin
 track<=next_track;byte_pos<=44;fifo_clear<=1;clear_count<=0;
 table_ra<={next_track,1'b0};loading_bgm<=0;state<=BASE_WAIT;
 voice_exhausted<=0;voice_finished<=0;narrating<=next_track<5;
end endtask
task issue;input voice;begin sector_voice<=voice;state<=ISSUE;end endtask
always @(posedge clk or posedge rst)begin
 if(rst)begin
  seek_ack<=0;seek_seen<=0;state<=WAIT;sd_req<=0;sd_addr<=0;received<=0;crc<=32'hffffffff;expected_crc<=0;word_shift<=0;metadata_bad<=0;opening_metadata_bad<=0;has_opening<=0;index_checked<=0;opening_requested<=0;opening_finished<=0;
  has_movie<=0;movie_bad<=0;movie_requested<=0;movie_finished<=0;movie_lba24<=0;movie_frame_count<=0;movie_audio_base<=0;movie_audio_len<=0;
  has_bgm<=0;bgm_metadata_bad<=0;bgm_metadata_count<=1;bgm_count<=1;bgm_applied<=0;bgm_rebuffer<=0;
  entry_base<=0;current_base<=0;entry_length<=0;current_length<=0;
  track<=0;byte_pos<=44;bgm_position<=44;held_sample<=0;
  previous_mode<=0;previous_theme<=0;pending_detail<=0;loading_bgm<=0;sector_voice<=0;voice_exhausted<=1;voice_finished<=1;
  clear_count<=0;start_byte<=0;stop_byte<=512;timer<=0;
  table_write<=0;table_wa<=0;table_ra<=0;table_wd<=0;
  fifo_clear<=1;fifo_write<=0;fifo_data<=0;bgm_fifo_clear<=1;bgm_fifo_write<=0;
  narrating<=0;fault<=0;error_code<=0;narration_done<=0;
 end else begin
  seek_ack<=0;if(!seek_request)seek_seen<=0;
  fifo_write<=0;bgm_fifo_write<=0;table_write<=0;narration_done<=0;
  if(desired_changed)begin previous_mode<=mode;previous_theme<=theme;pending_detail<=mode==2;end
  case(state)
   WAIT:if(enable && index_valid)state<=INDEX_REQ;
   INDEX_REQ:begin has_bgm<=0;bgm_metadata_bad<=0;bgm_metadata_count<=1;bgm_applied<=0;bgm_rebuffer<=0;bgm_position<=44;has_movie<=0;movie_bad<=0;movie_requested<=0;movie_finished<=0;metadata_bad<=0;opening_metadata_bad<=0;has_opening<=0;index_checked<=0;opening_requested<=0;opening_finished<=0;sd_addr<=index_lba;sd_req<=1;received<=0;timer<=0;crc<=32'hffffffff;state<=INDEX_RX;end
   INDEX_RX:begin
    timer<=timer+1'b1;
    if(sd_valid)begin
     received<=received+1'b1;word_shift<=complete_word;
     if(received<508)crc<=crc_byte(crc,sd_data);
     if(received==511)expected_crc<=complete_word;
     if(received[1:0]==3)begin
      case(received[9:2])
       0:if(complete_word!=32'h31415841)metadata_bad<=1;
       1:if(complete_word!=1)metadata_bad<=1;
       2:if(complete_word!=fs_begin)metadata_bad<=1;
       3:if(complete_word!=fs_end || fs_end[31:24]!=0)metadata_bad<=1;
       4:if(complete_word!=5)metadata_bad<=1;
       5:if(complete_word!=48000)metadata_bad<=1;
      endcase
      if(received==131)has_opening<=complete_word==32'h314e504f;
      if(received==135 && has_opening && complete_word!=1)opening_metadata_bad<=1;
      if(received==139 && has_opening && complete_word!=((entry_length-44)>>2))opening_metadata_bad<=1;
      case(received[9:2])
       85:has_movie<=complete_word==32'h3234564d;
       86:if(complete_word!=1)movie_bad<=1;
       87:begin movie_lba24<=complete_word[23:0];if(complete_word[31:24]!=0 || complete_word<fs_data || complete_word>=fs_end)movie_bad<=1;end
       88:begin movie_frame_count<=complete_word[11:0];if(complete_word==0 || complete_word>2621)movie_bad<=1;end
       89:begin movie_audio_base<=complete_word[23:0];if(complete_word[31:24]!=0 || complete_word<fs_data)movie_bad<=1;end
       90:begin movie_audio_len<=complete_word[24:0];if(complete_word<48 || complete_word>33553920)movie_bad<=1;end
       91:if(complete_word!=460800)movie_bad<=1;
       92:if(complete_word!=640)movie_bad<=1;
       93:if(complete_word!=360)movie_bad<=1;
       94:if(complete_word!=15)movie_bad<=1;
       95:if(complete_word!=48000)movie_bad<=1;
       96:if(complete_word!=2)movie_bad<=1;
       97:if(complete_word!=16)movie_bad<=1;
       // Optional BGS1 extension. Extra descriptors use the existing two
       // unused table slots6/7; voice/movie track numbering is unchanged.
       56:has_bgm<=complete_word==32'h31534742;
       57:begin bgm_metadata_count<=complete_word[1:0];if(complete_word<1 || complete_word>3)bgm_metadata_bad<=1;end
       58:if(complete_word!=1)bgm_metadata_bad<=1;
      endcase
      if(received>=32 && received<128)case(received[3:2])
       0:begin
        if(complete_word[31:24]!=0 || complete_word[23:0]<fs_data[23:0])bad_descriptor;
        entry_base<=complete_word[23:0];table_write<=1;table_wa<={descriptor,1'b0};table_wd<={1'b0,complete_word[23:0]};
       end
       1:begin
        if(complete_word<48 || complete_word>33553920)bad_descriptor;
        entry_length<=complete_word[24:0];table_write<=1;table_wa<={descriptor,1'b1};table_wd<=complete_word[24:0];
       end
       2:if(complete_word[1:0]!=0 || complete_word+44!={7'd0,entry_length})bad_descriptor;
       3:if(complete_word!=2 || track_end>{1'b0,fs_end[23:0]})bad_descriptor;
      endcase
      if(has_bgm && received>=240 && received<272 &&
         ((received<256 && bgm_metadata_count>=2) || (received>=256 && bgm_metadata_count==3)))case(received[3:2])
       0:begin
        if(complete_word[31:24]!=0 || complete_word<fs_data || complete_word>=fs_end)bgm_metadata_bad<=1;
        entry_base<=complete_word[23:0];table_write<=1;table_wa<=received[8]?4'd14:4'd12;table_wd<={1'b0,complete_word[23:0]};
       end
       1:begin
        if(complete_word<48 || complete_word>33553920)bgm_metadata_bad<=1;
        entry_length<=complete_word[24:0];table_write<=1;table_wa<=received[8]?4'd15:4'd13;table_wd<=complete_word[24:0];
       end
       2:if(complete_word[1:0]!=0 || complete_word+44!={7'd0,entry_length})bgm_metadata_bad<=1;
       3:if(complete_word!=2 || track_end>{1'b0,fs_end[23:0]})bgm_metadata_bad<=1;
      endcase
     end
    end
    if(sd_end)begin sd_req<=0;state<=INDEX_CHECK;end
    else if(timer==TIMEOUT_CYCLES-1)fail(1);
   end
   INDEX_CHECK:begin
    bgm_count<=has_bgm && !bgm_metadata_bad?bgm_metadata_count:2'd1;
    if(movie_video_end>fs_end || movie_audio_end>fs_end || {7'd0,movie_audio_len}!=movie_expected_len)movie_bad<=1;
    if(received!=512 || expected_crc!=~crc || metadata_bad || (has_opening && opening_metadata_bad))fail(2);
    else begin index_checked<=1;loading_bgm<=1;table_ra<=0;pending_detail<=mode==2;state<=BASE_WAIT;end
   end
   BASE_WAIT:state<=BASE_GET;
   BASE_GET:begin
    if(loading_bgm)entry_base<=table_q[23:0];else current_base<=table_q[23:0];
    table_ra[0]<=1;state<=LENGTH_WAIT;
   end
   LENGTH_WAIT:state<=LENGTH_GET;
   LENGTH_GET:begin
    if(loading_bgm)begin
     entry_length<=table_q;loading_bgm<=0;
     if(bgm_rebuffer)begin clear_count<=0;state<=BGM_CLEAR;end
     else begin bgm_fifo_clear<=0;state<=PLAY;end
    end
    else begin current_length<=table_q;state<=CLEAR;end
   end
   CLEAR:begin
    if(clear_count==31)begin fifo_clear<=0;state<=PLAY;end
    else clear_count<=clear_count+1'b1;
   end
   BGM_CLEAR:begin
    // The voice FIFO and its narration cursor are never reset by BGM changes.
    if(clear_count==31)begin bgm_fifo_clear<=0;state<=PLAY;end
    else clear_count<=clear_count+1'b1;
   end
   PLAY:begin
    if(bgm_rebuffer && !bgm_fifo_clear && bgm_fifo_used>=OPEN_PREFILL)bgm_rebuffer<=0;
    if(!movie_arm)begin movie_requested<=0;movie_finished<=0;end
    if(!enable)begin fifo_clear<=1;bgm_fifo_clear<=1;state<=WAIT;narrating<=0;end
    else if(opening_arm && !opening_requested)begin
     opening_requested<=1;
     if(has_opening)begin opening_finished<=0;restart_voice(3'd5);end
     else opening_finished<=1;
    end else if(movie_arm && !movie_requested && movie_available)begin
     movie_requested<=1;movie_finished<=0;track<=6;current_base<=movie_audio_base;current_length<=movie_audio_len;byte_pos<=44;fifo_clear<=1;clear_count<=0;voice_exhausted<=0;voice_finished<=0;narrating<=0;state<=CLEAR;
    end else if(movie_arm && track==6 && seek_request && !seek_seen)begin
     // Finish the in-flight sector before resetting either FIFO pointer.
     seek_seen<=1;seek_ack<=1;movie_finished<=0;byte_pos<={seek_samples,2'b00}+25'd44;
     fifo_clear<=1;clear_count<=0;voice_exhausted<=0;voice_finished<=0;state<=CLEAR;
    end else if(!movie_arm && track==6)begin
     track<=0;narrating<=0;fifo_clear<=1;voice_exhausted<=1;voice_finished<=1;
    end else if(!opening_arm && track==5)begin
     track<=0;narrating<=0;fifo_clear<=1;voice_exhausted<=1;voice_finished<=1;
    end else if(mode!=2 && track!=0 && track<5)begin
     track<=0;narrating<=0;fifo_clear<=1;pending_detail<=0;voice_exhausted<=1;voice_finished<=1;
    end else if(mode==2 && pending_detail && !opening_arm && !movie_arm && track<5)begin pending_detail<=0;restart_voice({1'b0,theme}+1'b1);end
    else if(requested_bgm!=bgm_applied && bgm_muted_sync[1])begin
     bgm_applied<=requested_bgm;bgm_position<=44;bgm_fifo_clear<=1;bgm_rebuffer<=1;
     loading_bgm<=1;table_ra<=requested_bgm==0?4'd0:requested_bgm==1?4'd12:4'd14;state<=BASE_WAIT;
    end else begin
     if(track!=0 && voice_exhausted && !voice_finished && fifo_used==0)begin
      if(track==6)begin movie_finished<=1;voice_finished<=1;end
      else if(track==5)begin if(opening_play)begin opening_finished<=1;voice_finished<=1;end end
      else begin narration_done<=1;voice_finished<=1;end
     end
     if(bgm_fifo_used<=256 && !bgm_fifo_full)issue(0);
     else if(track!=0 && !voice_exhausted && voice_needs_data && !fifo_full &&
             (track==6?movie_arm:(track==5?opening_arm:(mode==2 && scene_ready))))issue(1);
     else if(bgm_fifo_used<=896 && !bgm_fifo_full)issue(0);
    end
   end
   ISSUE:begin
    sd_addr<={8'd0,selected_base}+{16'd0,selected_position[24:9]};sd_req<=1;received<=0;timer<=0;
    start_byte<=selected_position[8:0];
    stop_byte<=selected_position[24:9]==selected_length[24:9] && selected_length[8:0]!=0?
                 {1'b0,selected_length[8:0]}:10'd512;
    state<=DATA_RX;
   end
   DATA_RX:begin
    timer<=timer+1'b1;
    if(sd_valid)begin
     received<=received+1'b1;
     if(received>={1'b0,start_byte} && received<stop_byte)begin
      if(sector_voice)byte_pos<=byte_pos+1'b1;else bgm_position<=bgm_position+1'b1;
      case(received[1:0])
       0:held_sample[7:0]<=sd_data;
       1:held_sample[15:8]<=sd_data;
       2:held_sample[23:16]<=sd_data;
       3:if(sector_voice?fifo_full:bgm_fifo_full)fail(4);
         else begin fifo_data<={sd_data,held_sample};if(sector_voice)fifo_write<=1;else bgm_fifo_write<=1;end
      endcase
     end
    end
    if(sd_end)begin sd_req<=0;state<=GAP;end
    else if(timer==TIMEOUT_CYCLES-1)fail(5);
   end
   GAP:begin
    if(received!=512)fail(6);
    else begin
     if(sector_voice && byte_pos>=current_length)voice_exhausted<=1;
     if(!sector_voice && bgm_position>=entry_length)bgm_position<=44;
     state<=PLAY;
    end
   end
   FAIL:begin sd_req<=0;fifo_clear<=1;bgm_fifo_clear<=1;end
   default:fail(7);
  endcase
 end
end
endmodule
