// Playback control and low-rate time display. No RAM or DSP is required.
module exhibit_movie_transport_v39(
 input seek_restart,input [11:0] current_frame,output reg [7:0] progress,
 input clk,rst,active,toggle_pause,exit_request,ended,output_muted,
 input [23:0] consumed_samples,input [15:0] total_frames,
 output reg paused,output allow_audio,
 output reg [15:0] elapsed_bcd,output reg [15:0] duration_bcd
);
(* async_reg="true" *)reg [1:0] muted_sync;
reg [23:0] next_second;
reg [9:0] frames_in_minute;
reg [3:0] minutes;
reg [3:0] tens;reg [7:0] last_frames;
reg [3:0] ones;
reg active_d;reg [19:0] progress_due;reg [11:0] previous_frame;
assign allow_audio=active && !(paused && muted_sync[1]);
always @*begin
 if(frames_in_minute>=750)begin tens=5;last_frames=frames_in_minute-750;end
 else if(frames_in_minute>=600)begin tens=4;last_frames=frames_in_minute-600;end
 else if(frames_in_minute>=450)begin tens=3;last_frames=frames_in_minute-450;end
 else if(frames_in_minute>=300)begin tens=2;last_frames=frames_in_minute-300;end
 else if(frames_in_minute>=150)begin tens=1;last_frames=frames_in_minute-150;end
 else begin tens=0;last_frames=frames_in_minute;end
 if(last_frames>=135)ones=9;else if(last_frames>=120)ones=8;
 else if(last_frames>=105)ones=7;else if(last_frames>=90)ones=6;
 else if(last_frames>=75)ones=5;else if(last_frames>=60)ones=4;
 else if(last_frames>=45)ones=3;else if(last_frames>=30)ones=2;
 else if(last_frames>=15)ones=1;else ones=0;
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  progress<=0;progress_due<=0;previous_frame<=0;muted_sync<=0;paused<=0;next_second<=48000;elapsed_bcd<=0;
  duration_bcd<=0;frames_in_minute<=0;minutes<=0;active_d<=0;
 end else begin
  muted_sync<={muted_sync[0],output_muted};active_d<=active;previous_frame<=current_frame;
  if(!active || !active_d || seek_restart || current_frame<previous_frame)begin progress<=0;progress_due<=total_frames[11:0];end
  else if(progress<255 && {current_frame,8'd0}>=progress_due && total_frames!=0)begin
   progress<=progress+1'b1;progress_due<=progress_due+total_frames[11:0];
  end
  // MV15 accepts at most2621 frames at15fps: maximum02:54.
  if(total_frames>=1800)begin minutes<=2;frames_in_minute<=total_frames-1800;end
  else if(total_frames>=900)begin minutes<=1;frames_in_minute<=total_frames-900;end
  else begin minutes<=0;frames_in_minute<=total_frames;end
  duration_bcd<={4'd0,minutes,tens,ones};
  if(!active || exit_request || ended)paused<=0;
  else if(!active_d)paused<=toggle_pause;
  else if(toggle_pause)paused<=!paused;
  if(active && (!active_d || seek_restart))begin elapsed_bcd<=0;next_second<=48000;end
  else if(active)begin
   // Count actual consumed PCM samples, preserving partial seconds on pause.
   if(consumed_samples>=next_second && elapsed_bcd!=16'h9959)begin
    next_second<=next_second+24'd48000;
    if(elapsed_bcd[3:0]!=9)elapsed_bcd[3:0]<=elapsed_bcd[3:0]+1'b1;
    else begin
     elapsed_bcd[3:0]<=0;
     if(elapsed_bcd[7:4]!=5)elapsed_bcd[7:4]<=elapsed_bcd[7:4]+1'b1;
     else begin
      elapsed_bcd[7:4]<=0;
      if(elapsed_bcd[11:8]!=9)elapsed_bcd[11:8]<=elapsed_bcd[11:8]+1'b1;
      else begin elapsed_bcd[11:8]<=0;elapsed_bcd[15:12]<=elapsed_bcd[15:12]+1'b1;end
     end
    end
   end
  end
 end
end
endmodule

// Stable bundled-data mailbox. A whole status word changes only in vblank.
module exhibit_movie_status_bridge_v39 #(parameter integer WIDTH=33)(
 input source_clk,source_rst,input [WIDTH-1:0] payload,
 input video_clk,video_rst,vs,output reg [WIDTH-1:0] status
);
reg [WIDTH-1:0] mailbox;reg request,ack;
(* async_reg="true" *)reg [2:0] ack_sync,request_sync;
reg vs_d;
always @(posedge source_clk or posedge source_rst)begin
 if(source_rst)begin mailbox<=0;request<=0;ack_sync<=0;end
 else begin
  ack_sync<={ack_sync[1:0],ack};
  if(ack_sync[2]==request && mailbox!=payload)begin mailbox<=payload;request<=!request;end
 end
end
always @(posedge video_clk or posedge video_rst)begin
 if(video_rst)begin status<=0;ack<=0;request_sync<=0;vs_d<=0;end
 else begin
  request_sync<={request_sync[1:0],request};vs_d<=vs;
  if(vs_d && !vs && request_sync[2]!=ack)begin status<=mailbox;ack<=request_sync[2];end
 end
end
endmodule
// Same-clock seek transaction. New requests during a seek are ignored.
// First fade to silence, then drain/reset readers, then wait for committed
// video and prefetched audio. The user's pause latch is independent.
module exhibit_movie_seek_v47(
 input clk,rst,active,forward,backward,input [11:0] current_frame,total_frames,
 input output_muted,audio_ack,video_ack,audio_ready,picture_ready,fault,
 output busy,apply,fading,output reg restart,output reg [11:0] frame,
 output reg [23:0] samples,sector_offset
);
localparam IDLE=0,MUTE=1,APPLY=2,READY=3;
reg [1:0] state;reg got_audio,got_video;
(* async_reg="true" *)reg [1:0] muted_sync;
wire [12:0] plus_frame={1'b0,current_frame}+13'd150;
assign busy=state!=IDLE;
assign apply=state==APPLY;
assign fading=state==MUTE;
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=IDLE;got_audio<=0;got_video<=0;restart<=0;frame<=0;samples<=0;sector_offset<=0;muted_sync<=0;end
 else begin
  restart<=0;muted_sync<={muted_sync[0],output_muted};
  // Register shift/add addresses; no variable multiplier or divider.
  samples<=({12'd0,frame}<<11)+({12'd0,frame}<<10)+({12'd0,frame}<<7);
  sector_offset<=({12'd0,frame}<<10)-({12'd0,frame}<<7)+({12'd0,frame}<<2);
  if(!active || fault)state<=IDLE;
  else case(state)
   IDLE:if((forward || backward) && total_frames!=0)begin
    if(backward)frame<=current_frame>150?current_frame-12'd150:12'd0;
    else frame<=plus_frame>={1'b0,total_frames}?total_frames-1'b1:plus_frame[11:0];
    got_audio<=0;got_video<=0;state<=MUTE;
   end
   // One extra state cycle after the key ensures addresses have settled.
   MUTE:if(muted_sync[1])state<=APPLY;
   APPLY:begin
    if(audio_ack)got_audio<=1;if(video_ack)got_video<=1;
    if((got_audio || audio_ack) && (got_video || video_ack))begin restart<=1;state<=READY;end
   end
   READY:if(audio_ready && picture_ready)state<=IDLE;
   default:state<=IDLE;
  endcase
 end
end
endmodule
