// Source payload is held until ACK. Destination takes one extra settling cycle
// after the request synchronizer, then applies the entire scene at frame read.
module exhibit_scene_bridge(
 input mem_clk,rst_mem,input [13:0] publish_scene,input publish_toggle,
 output reg publish_ack_toggle,
 input video_read_req,video_read_req_ack,
 output read_req_mem,output reg [1:0] selected_read_buf,
 output reg [13:0] active_scene,
 output reg frame_toggle
);
reg [2:0] req_sync;
reg [1:0] frame_req_sync;
reg frame_req_d,ack_d;
reg pending,transaction_id,selected_commit,selected_id;
reg [13:0] pending_scene,selected_scene;
assign read_req_mem=frame_req_sync[1];
always @(posedge mem_clk or posedge rst_mem) begin
 if(rst_mem) begin
  req_sync<=0;frame_req_sync<=0;frame_req_d<=0;ack_d<=0;
  pending<=0;transaction_id<=0;selected_commit<=0;selected_id<=0;
  pending_scene<=0;selected_scene<=0;selected_read_buf<=0;
  active_scene<=0;frame_toggle<=0;publish_ack_toggle<=0;
 end else begin
  req_sync<={req_sync[1:0],publish_toggle};
  frame_req_sync<={frame_req_sync[0],video_read_req};
  frame_req_d<=frame_req_sync[1];ack_d<=video_read_req_ack;
  if(!pending && req_sync[2]!=publish_ack_toggle) begin
   pending_scene<=publish_scene;transaction_id<=req_sync[2];pending<=1;
  end
  if(frame_req_sync[1] && !frame_req_d) begin
   selected_commit<=pending;
   if(pending) begin
    selected_read_buf<=pending_scene[1:0];selected_scene<=pending_scene;
    selected_id<=transaction_id;
   end else begin
    selected_read_buf<=active_scene[1:0];selected_scene<=active_scene;
   end
  end
  // The read controller has finished latching its base address. The selection
  // remains stable throughout ACK, including publications arriving mid-ACK.
  if(ack_d && !video_read_req_ack) begin
   active_scene<=selected_scene;frame_toggle<=~frame_toggle;
   if(selected_commit) begin publish_ack_toggle<=selected_id;pending<=0;end
   selected_commit<=0;
  end
 end
end
endmodule
