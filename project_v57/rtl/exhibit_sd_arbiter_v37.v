// Sector owner is held through completion and the client's request-low gap.
// Register the physical request/address together to cut the UI/FAT mux away
// from the native SD command controller's wide register enables.
module exhibit_sd_arbiter_v37(
 input clk,rst,display_valid,
 input image_req,input [31:0] image_addr,
 input audio_req,input [31:0] audio_addr,
 input movie_req,input [31:0] movie_addr,
 input sd_end,audio_hold,output audio_owner,movie_owner,
 output reg sd_req,output reg [31:0] sd_addr
);
reg [1:0] owner;reg drop,audio_gap;
assign audio_owner=display_valid && owner==1 && !drop;
assign movie_owner=display_valid && owner==2 && !drop;
wire client_req=!display_valid?image_req:(audio_owner?audio_req:(movie_owner?movie_req:1'b0));
wire [31:0] client_addr=!display_valid?image_addr:(owner==1?audio_addr:movie_addr);
always @(posedge clk or posedge rst)begin
 if(rst)begin owner<=0;drop<=0;audio_gap<=0;sd_req<=0;sd_addr<=0;end
 else begin
  sd_req<=client_req;if(client_req)sd_addr<=client_addr;
  if(!display_valid)begin owner<=0;drop<=0;audio_gap<=0;end
  else if(owner==0)begin if(audio_req)owner<=1;else if(movie_req)owner<=2;end
  else if(!drop && sd_end)drop<=1;
  else if(drop)begin
   if(owner==1 && audio_gap)begin
    if(audio_req)begin drop<=0;audio_gap<=0;end
    else if(!audio_hold)begin owner<=0;drop<=0;audio_gap<=0;end
   end else if(owner==1?!audio_req:!movie_req)begin
    if(owner==1 && audio_hold)audio_gap<=1;
    else begin owner<=0;drop<=0;audio_gap<=0;end
   end
  end
 end
end
endmodule
