// Audio and video start together after the opening FIFO is prefetched.
// The tour remains held until the first-page fade-in is fully complete.
module exhibit_intro_lifecycle_v35 #(parameter integer CLOCK_HZ=50_000_000)(
 input clk,rst,asset_checked,asset_valid,presented,decoder_fault,
 input audio_done,black_ready,handoff_done,
 output intro_request,hold_tour,play_audio,tail_fade_request,
 output [5:0] frame_gray,output reg finished
);
reg [5:0] frame,registered_gray;wire [5:0] next_frame=frame+1'b1;
reg [22:0] ticks;
reg started,content_complete,switched_to_page;
(* async_reg="true" *) reg [1:0] presented_sync,fault_sync,audio_done_sync,black_sync,handoff_sync;
assign intro_request=asset_valid && !finished && !switched_to_page;
assign hold_tour=asset_valid && !finished;
assign play_audio=started && intro_request;
assign tail_fade_request=asset_valid && started && frame>=36 && !finished;
assign frame_gray=registered_gray;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  frame<=0;registered_gray<=0;ticks<=0;started<=0;content_complete<=0;switched_to_page<=0;finished<=0;
  presented_sync<=0;fault_sync<=0;audio_done_sync<=0;black_sync<=0;handoff_sync<=0;
 end else begin
  presented_sync<={presented_sync[0],presented};fault_sync<={fault_sync[0],decoder_fault};
  audio_done_sync<={audio_done_sync[0],audio_done};black_sync<={black_sync[0],black_ready};handoff_sync<={handoff_sync[0],handoff_done};
  if((asset_checked && !asset_valid) || fault_sync[1])begin finished<=1;switched_to_page<=1;end
  if(intro_request && presented_sync[1])started<=1;
  if(started && intro_request && !content_complete)begin
   if(ticks==CLOCK_HZ/10-1)begin
    ticks<=0;
    if(frame==39)content_complete<=1;
    else begin frame<=next_frame;registered_gray<=(next_frame>>1)^next_frame;end
   end else ticks<=ticks+1'b1;
  end
  if(content_complete && audio_done_sync[1] && black_sync[1])switched_to_page<=1;
  if(switched_to_page && handoff_sync[1])finished<=1;
 end
end
endmodule
