// Global visual gain is committed at VS blank, independently of media readiness.
// This channel and coefficient retain state across a video-mode-only reset.
module exhibit_screen_brightness(
 input clk,config_rst,video_rst,vs,input [6:0] payload,input request_toggle,
 output reg ack,output reg [6:0] applied,output [8:0] gain
);
reg [2:0] request_sync;reg pending,pending_id,vs_d;reg [6:0] pending_value;
always @(posedge clk or posedge config_rst)begin
 if(config_rst)begin request_sync<=0;pending<=0;pending_id<=0;pending_value<=100;vs_d<=0;ack<=0;applied<=100;end
 else begin
  request_sync<={request_sync[1:0],request_toggle};vs_d<=vs;
  if(!pending && request_sync[2]!=ack)begin
   pending_value<=payload>100?7'd100:payload;pending_id<=request_sync[2];pending<=1;
  end
  if(pending && vs_d && !vs && !video_rst)begin applied<=pending_value;ack<=pending_id;pending<=0;end
 end
end
exhibit_percent_gain coefficient(clk,config_rst,{1'b0,applied},gain);
endmodule
