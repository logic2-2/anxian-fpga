// Atomic scene mailbox + frame-counted fade-out / black switch / fade-in.
module exhibit_transition_bridge #(parameter integer STEP=32)(
 input mem_clk,rst_mem,input [47:0] publish_scene,input publish_toggle,
 output reg publish_ack_toggle,input video_read_req,video_read_req_ack,
 output read_req_mem,output reg [1:0] selected_read_buf,
 output reg [47:0] selected_scene,active_scene,
 output reg [8:0] active_gain,output reg frame_toggle
);
localparam HOLD=0,OUT=1,BLACK=2,IN=3;
reg [1:0] phase;
reg [2:0] req_sync;
reg [1:0] frame_req_sync;
reg frame_req_d,ack_d,pending,transaction_id,selected_commit,selected_id;
reg [47:0] pending_scene;
reg [8:0] selected_gain;
// AUTO and PREVIEW now show identical full-size pixels. Pausing/resuming the
// same theme only updates UI metadata; it should not fade the image to black.
wire same_full_image=pending_scene[1:0]==active_scene[1:0] &&
 pending_scene[15:14]==active_scene[15:14] &&
 pending_scene[3:2]<2 && active_scene[3:2]<2;
assign read_req_mem=frame_req_sync[1];
always @(posedge mem_clk or posedge rst_mem) begin
 if(rst_mem) begin
  req_sync<=0;frame_req_sync<=0;frame_req_d<=0;ack_d<=0;pending<=0;
  transaction_id<=0;selected_commit<=0;selected_id<=0;pending_scene<=0;
  selected_scene<=0;active_scene<=0;active_gain<=0;selected_gain<=0;
  selected_read_buf<=0;frame_toggle<=0;publish_ack_toggle<=0;phase<=HOLD;
 end else begin
  req_sync<={req_sync[1:0],publish_toggle};
  frame_req_sync<={frame_req_sync[0],video_read_req};
  frame_req_d<=frame_req_sync[1];ack_d<=video_read_req_ack;
  if(!pending && req_sync[2]!=publish_ack_toggle) begin
   pending_scene<=publish_scene;transaction_id<=req_sync[2];pending<=1;
  end
  if(frame_req_sync[1] && !frame_req_d) begin
   selected_commit<=0;
   case(phase)
    HOLD: if(pending) begin
     if(!active_scene[13] || same_full_image || (pending_scene[3:0]==active_scene[3:0] && pending_scene[15:14]==active_scene[15:14])) begin
      selected_scene<=pending_scene;selected_read_buf<=pending_scene[1:0];
      selected_id<=transaction_id;selected_commit<=1;
      if(!active_scene[13]) begin selected_gain<=0;phase<=IN;end
     end else begin selected_gain<=256-STEP;phase<=OUT;end
    end
    OUT: if(selected_gain<=STEP) begin selected_gain<=0;phase<=BLACK;end
         else selected_gain<=selected_gain-STEP;
    BLACK: begin
     // Zero gain has already been displayed for a complete old-scene frame.
     selected_scene<=pending_scene;selected_read_buf<=pending_scene[1:0];
     selected_id<=transaction_id;selected_commit<=1;selected_gain<=0;phase<=IN;
    end
    IN: if(selected_gain>=256-STEP) begin selected_gain<=256;phase<=HOLD;end
        else selected_gain<=selected_gain+STEP;
   endcase
  end
  if(ack_d && !video_read_req_ack) begin
   active_scene<=selected_scene;active_gain<=selected_gain;frame_toggle<=~frame_toggle;
   if(selected_commit) begin publish_ack_toggle<=selected_id;pending<=0;end
   selected_commit<=0;
  end
 end
end
endmodule
