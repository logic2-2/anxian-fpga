// Independent Jazz and narration FIFOs share one checked SD sector reader.
module exhibit_tf_audio #(parameter integer TIMEOUT_CYCLES=50_000_000)(
 input clk,rst,enable,index_valid,scene_ready,input [31:0] index_lba,fs_begin,fs_end,fs_data,
 input [1:0] mode,theme,output reg sd_req,output reg [31:0] sd_addr,
 input [7:0] sd_data,input sd_valid,sd_end,
 input [10:0] fifo_used,bgm_fifo_used,input fifo_full,bgm_fifo_full,
 output reg fifo_clear,fifo_write,output reg [31:0] fifo_data,
 output reg bgm_fifo_clear,bgm_fifo_write,output [31:0] bgm_fifo_data,
 output reg narrating,fault,narration_done,output reg [3:0] error_code,
 output [24:0] position_bytes,output [2:0] playing_track
);
localparam WAIT=0,INDEX_REQ=1,INDEX_RX=2,INDEX_CHECK=3,CLEAR=4,PLAY=5,
 DATA_RX=6,GAP=7,FAIL=9,BASE_WAIT=10,BASE_GET=11,LENGTH_WAIT=12,LENGTH_GET=13,ISSUE=15;
reg [3:0] state;
reg [9:0] received;
reg [31:0] crc,expected_crc,word_shift;
wire [31:0] complete_word={sd_data,word_shift[31:8]};
reg metadata_bad;
// Index-validation scratch registers become the persistent Jazz descriptor.
reg [23:0] entry_base,current_base;
reg [24:0] entry_length,current_length;
reg [2:0] track;
reg [24:0] byte_pos,bgm_position;
assign position_bytes=byte_pos;assign playing_track=track;
reg [23:0] held_sample;
reg [1:0] previous_mode,previous_theme;
reg pending_detail,loading_bgm,sector_voice,voice_exhausted,voice_finished;
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
assign bgm_fifo_data=fifo_data;
// Use spare9K memory for descriptors, releasing32K for the Jazz PCM FIFO.
EG_LOGIC_BRAM #(.DATA_WIDTH_A(25),.DATA_WIDTH_B(25),.ADDR_WIDTH_A(4),.ADDR_WIDTH_B(4),
 .DATA_DEPTH_A(16),.DATA_DEPTH_B(16),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) track_table(
 .dia(table_wd),.addra(table_wa),.cea(1'b1),.ocea(1'b1),.clka(clk),.wea(table_write),.rsta(1'b0),.bea(1'b1),.doa(),
 .dib(25'd0),.addrb(table_ra),.ceb(1'b1),.oceb(1'b1),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b1),.dob(table_q));
function [31:0] crc_byte;input [31:0] c;input [7:0] b;integer j;reg [31:0] q;begin
 q=c^{24'd0,b};for(j=0;j<8;j=j+1)q=(q>>1)^(q[0]?32'hedb88320:0);crc_byte=q;
end endfunction
task fail;input [3:0] code;begin
 fault<=1;error_code<=code;state<=FAIL;sd_req<=0;narrating<=0;fifo_clear<=1;bgm_fifo_clear<=1;
end endtask
task restart_voice;input [2:0] next_track;begin
 track<=next_track;byte_pos<=44;fifo_clear<=1;clear_count<=0;
 table_ra<={next_track,1'b0};loading_bgm<=0;state<=BASE_WAIT;
 voice_exhausted<=0;voice_finished<=0;narrating<=1;
end endtask
task issue;input voice;begin sector_voice<=voice;state<=ISSUE;end endtask
always @(posedge clk or posedge rst)begin
 if(rst)begin
  state<=WAIT;sd_req<=0;sd_addr<=0;received<=0;crc<=32'hffffffff;expected_crc<=0;word_shift<=0;metadata_bad<=0;
  entry_base<=0;current_base<=0;entry_length<=0;current_length<=0;
  track<=0;byte_pos<=44;bgm_position<=44;held_sample<=0;
  previous_mode<=0;previous_theme<=0;pending_detail<=0;loading_bgm<=0;sector_voice<=0;voice_exhausted<=1;voice_finished<=1;
  clear_count<=0;start_byte<=0;stop_byte<=512;timer<=0;
  table_write<=0;table_wa<=0;table_ra<=0;table_wd<=0;
  fifo_clear<=1;fifo_write<=0;fifo_data<=0;bgm_fifo_clear<=1;bgm_fifo_write<=0;
  narrating<=0;fault<=0;error_code<=0;narration_done<=0;
 end else begin
  fifo_write<=0;bgm_fifo_write<=0;table_write<=0;narration_done<=0;
  if(desired_changed)begin previous_mode<=mode;previous_theme<=theme;pending_detail<=mode==2;end
  case(state)
   WAIT:if(enable && index_valid)state<=INDEX_REQ;
   INDEX_REQ:begin sd_addr<=index_lba;sd_req<=1;received<=0;timer<=0;crc<=32'hffffffff;state<=INDEX_RX;end
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
      if(received>=32 && received<112)case(received[3:2])
       0:begin
        if(complete_word[31:24]!=0 || complete_word[23:0]<fs_data[23:0])metadata_bad<=1;
        entry_base<=complete_word[23:0];table_write<=1;table_wa<={descriptor,1'b0};table_wd<={1'b0,complete_word[23:0]};
       end
       1:begin
        if(complete_word<48 || complete_word>33553920)metadata_bad<=1;
        entry_length<=complete_word[24:0];table_write<=1;table_wa<={descriptor,1'b1};table_wd<=complete_word[24:0];
       end
       2:if(complete_word[1:0]!=0 || complete_word+44!={7'd0,entry_length})metadata_bad<=1;
       3:if(complete_word!=2 || track_end>{1'b0,fs_end[23:0]})metadata_bad<=1;
      endcase
     end
    end
    if(sd_end)begin sd_req<=0;state<=INDEX_CHECK;end
    else if(timer==TIMEOUT_CYCLES-1)fail(1);
   end
   INDEX_CHECK:begin
    if(received!=512 || expected_crc!=~crc || metadata_bad)fail(2);
    else begin loading_bgm<=1;table_ra<=0;pending_detail<=mode==2;state<=BASE_WAIT;end
   end
   BASE_WAIT:state<=BASE_GET;
   BASE_GET:begin
    if(loading_bgm)entry_base<=table_q[23:0];else current_base<=table_q[23:0];
    table_ra[0]<=1;state<=LENGTH_WAIT;
   end
   LENGTH_WAIT:state<=LENGTH_GET;
   LENGTH_GET:begin
    if(loading_bgm)begin entry_length<=table_q;loading_bgm<=0;bgm_fifo_clear<=0;state<=PLAY;end
    else begin current_length<=table_q;state<=CLEAR;end
   end
   CLEAR:begin
    if(clear_count==31)begin fifo_clear<=0;state<=PLAY;end
    else clear_count<=clear_count+1'b1;
   end
   PLAY:begin
    if(!enable)begin fifo_clear<=1;bgm_fifo_clear<=1;state<=WAIT;narrating<=0;end
    else if(mode!=2 && track!=0)begin
     track<=0;narrating<=0;fifo_clear<=1;pending_detail<=0;voice_exhausted<=1;voice_finished<=1;
    end else if(mode==2 && pending_detail)begin pending_detail<=0;restart_voice({1'b0,theme}+1'b1);end
    else begin
     if(track!=0 && voice_exhausted && !voice_finished && fifo_used==0)begin narration_done<=1;voice_finished<=1;end
     if(bgm_fifo_used<=256 && !bgm_fifo_full)issue(0);
     else if(mode==2 && track!=0 && !voice_exhausted && scene_ready && fifo_used<=896 && !fifo_full)issue(1);
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
