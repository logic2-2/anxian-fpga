// Raw640x360 RGB56515fps reader. Frames are committed only after SDRAM drains.
// A displayed or pending-display slot is never selected for writing.
module exhibit_movie_stream_v37 #(parameter integer TIMEOUT=50_000_000,SECTORS=900)(
 input [1:0] movie_speed,
 input seek_request,input [11:0] seek_frame,input [23:0] seek_samples,seek_sector_offset,
 output reg seek_ack,seek_picture_ready,output [11:0] current_frame,
 input clk,rst,active,available,play_audio,input [31:0] base_lba,input [15:0] total_frames,
 input [23:0] consumed_samples,input write_ack,write_done_toggle,display_ack_toggle,
 output reg sd_req,output reg [31:0] sd_addr,input [7:0] sd_data,input sd_valid,sd_end,
 output reg write_req,write_active,write_slot,pixel_valid,output reg [23:0] pixel,
 output reg publish_toggle,publish_slot,output reg [15:0] publish_frame,
 output reg displayed,output reg fault
);
localparam IDLE=0,REQ_WRITE=1,REQ_SD=2,RX=3,GAP=4,DRAIN=5,ERROR=6;
reg [2:0] state;reg [1:0] ready;reg [11:0] id0,id1,next_frame,target_frame;
wire [11:0] frame_limit=total_frames[11:0];
reg [23:0] next_lba;reg [23:0] next_due;
reg [9:0] sector;reg [7:0] low;reg [9:0] received;
wire [23:0] sector_lba=next_lba+sector;
reg display_slot,write_seen,started,seek_seen;reg skip_toggle;reg [1:0] skip_third;
wire speed_skip=(movie_speed==3 && skip_toggle) || (movie_speed==2 && skip_third==2);
assign current_frame=target_frame;
reg [$clog2(TIMEOUT)-1:0] timer;
(* async_reg="true" *)reg [2:0] ack_sync,done_sync;reg [1:0] wr_ack_sync;
wire pending=publish_toggle!=ack_sync[2];
wire done_pulse=done_sync[2]^done_sync[1];
wire free0=!ready[0] && (!displayed || display_slot!=0) && !(pending && publish_slot==0);
wire free1=!ready[1] && (!displayed || display_slot!=1) && !(pending && publish_slot==1);
wire [15:0] colour={sd_data,low};
always @(posedge clk or posedge rst)begin
 if(rst)begin
  skip_toggle<=0;skip_third<=0;seek_ack<=0;seek_picture_ready<=0;seek_seen<=0;state<=IDLE;ready<=0;id0<=0;id1<=0;next_frame<=0;target_frame<=0;next_lba<=0;next_due<=3200;
  sector<=0;low<=0;received<=0;display_slot<=0;write_seen<=0;started<=0;timer<=0;
  ack_sync<=0;done_sync<=0;wr_ack_sync<=0;sd_req<=0;sd_addr<=0;write_req<=0;write_active<=0;write_slot<=0;pixel_valid<=0;pixel<=0;
  publish_toggle<=0;publish_slot<=0;publish_frame<=0;displayed<=0;fault<=0;
 end else begin
  seek_ack<=0;if(!seek_request)seek_seen<=0;
  ack_sync<={ack_sync[1:0],display_ack_toggle};done_sync<={done_sync[1:0],write_done_toggle};wr_ack_sync<={wr_ack_sync[0],write_ack};pixel_valid<=0;
  if(write_active && !write_req && done_pulse)write_seen<=1;
  if(active && available && !fault)begin
   if(ack_sync[2]!=ack_sync[1] && ack_sync[1]==publish_toggle && ready[publish_slot])begin
    displayed<=1;seek_picture_ready<=1;display_slot<=publish_slot;ready[publish_slot]<=0;
   end
   if(play_audio)started<=1;
   if(started && consumed_samples>=next_due && target_frame<frame_limit)begin target_frame<=target_frame+1'b1;next_due<=next_due+24'd3200;end
   if(!pending && !seek_request)begin
    if(ready[0] && id0<=target_frame)begin publish_slot<=0;publish_frame<=id0;publish_toggle<=!publish_toggle;end
    else if(ready[1] && id1<=target_frame)begin publish_slot<=1;publish_frame<=id1;publish_toggle<=!publish_toggle;end
   end
  end
  case(state)
   IDLE:begin
    timer<=0;sd_req<=0;write_req<=0;write_active<=0;
    if(!active)begin skip_toggle<=0;skip_third<=0;ready<=0;next_frame<=0;target_frame<=0;next_lba<=base_lba[23:0];next_due<=3200;displayed<=0;started<=0;fault<=0;end
    else if(seek_request && !seek_seen && !pending)begin
     // Keep displayed/display_slot: the old visible buffer remains protected.
     skip_toggle<=0;skip_third<=0;seek_seen<=1;seek_ack<=1;seek_picture_ready<=0;ready<=0;
     next_frame<=seek_frame;target_frame<=seek_frame;next_lba<=base_lba[23:0]+seek_sector_offset;
     next_due<=seek_samples+24'd3200;started<=0;
    end
    else if(!seek_request && available && !fault && next_frame<frame_limit && !(next_frame==0 && pending))begin
     if(speed_skip || (started && next_frame<target_frame))begin skip_toggle<=!skip_toggle;skip_third<=skip_third==2?0:skip_third+1'b1;next_frame<=next_frame+1'b1;next_lba<=next_lba+SECTORS;end
     else if(free0 || free1)begin write_slot<=!free0;write_active<=1;write_req<=1;write_seen<=0;sector<=0;state<=REQ_WRITE;end
    end
   end
   REQ_WRITE:begin
    timer<=timer+1'b1;
    if(wr_ack_sync[1])begin write_req<=0;timer<=0;state<=REQ_SD;end
    else if(timer==TIMEOUT-1)begin fault<=1;state<=ERROR;end
   end
   REQ_SD:begin sd_addr<={8'd0,sector_lba};received<=0;timer<=0;sd_req<=1;state<=RX;end
   RX:begin
    timer<=timer+1'b1;
    if(sd_valid)begin
     received<=received+1'b1;
     if(!received[0])low<=sd_data;
     else begin pixel_valid<=1;pixel<={colour[15:11],colour[15:13],colour[10:5],colour[10:9],colour[4:0],colour[4:2]};end
    end
    if(sd_end)begin sd_req<=0;state<=GAP;end
    else if(timer==TIMEOUT-1)begin fault<=1;state<=ERROR;end
   end
   GAP:begin
    if(received!=512)begin fault<=1;state<=ERROR;end
    else if(sector==SECTORS-1)begin timer<=0;state<=DRAIN;end
    else begin sector<=sector+1'b1;state<=REQ_SD;end
   end
   DRAIN:begin
    timer<=timer+1'b1;
    if(write_seen || done_pulse)begin
     if(active)begin ready[write_slot]<=1;if(write_slot)id1<=next_frame;else id0<=next_frame;end
     skip_toggle<=!skip_toggle;skip_third<=skip_third==2?0:skip_third+1'b1;write_active<=0;next_frame<=next_frame+1'b1;next_lba<=next_lba+SECTORS;state<=IDLE;
    end else if(timer==TIMEOUT-1)begin fault<=1;state<=ERROR;end
   end
   ERROR:begin sd_req<=0;write_req<=0;pixel_valid<=0;if(!active)begin write_active<=0;state<=IDLE;end end
   default:begin fault<=1;state<=ERROR;end
  endcase
 end
end
endmodule

// Bundled mailbox. Selection is prepared in blank, acknowledgement follows
// the existing read-FIFO clear/address latch transaction, freeing the old slot.
module exhibit_movie_present_v37(
 input clk,rst,requested,scene_movie,frame_req,read_ack,
 input request_toggle,request_slot,input [15:0] request_frame,
 output reg ack_toggle,read_movie,read_slot,output reg [15:0] displayed_frame
);
(* async_reg="true" *)reg [2:0] req_sync;reg [1:0] active_sync;
reg fr_d,fr_start_d,ack_d,commit,selected_toggle;
always @(posedge clk or posedge rst)begin
 if(rst)begin req_sync<=0;active_sync<=0;fr_d<=0;fr_start_d<=0;ack_d<=0;commit<=0;selected_toggle<=0;ack_toggle<=0;read_movie<=0;read_slot<=0;displayed_frame<=0;end
 else begin
  req_sync<={req_sync[1:0],request_toggle};active_sync<={active_sync[0],requested};fr_d<=frame_req;fr_start_d<=frame_req && !fr_d;ack_d<=read_ack;
  if(fr_start_d)begin
   commit<=0;
   if(!scene_movie)read_movie<=0;
   else if(active_sync[1] && req_sync[2]!=ack_toggle)begin
    read_movie<=1;read_slot<=request_slot;displayed_frame<=request_frame;selected_toggle<=req_sync[2];commit<=1;
   end
  end
  if(ack_d && !read_ack)begin
   if(commit)ack_toggle<=selected_toggle;
   // Cancel only after an actual exit. A movie mailbox can arrive during
   // the scene fade or too late for this vblank; keep it for the next frame.
   else if(!read_movie && !active_sync[1] && !scene_movie)ack_toggle<=req_sync[2];
   commit<=0;
  end
 end
end
endmodule
