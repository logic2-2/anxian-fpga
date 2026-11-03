// Active-first raster. Frame fetch starts at the first vertical-blank line.
module exhibit_dual_timing(
 input clk,rst,mode_hd,frame_enable,read_req_ack,
 output reg read_req,output hs,vs,de,
 output [10:0] x,output [9:0] y,
 output line_start,frame_blank_start
);
reg [10:0] h;
reg [9:0] v;
reg [1:0] ack;
wire [10:0] ha=mode_hd?11'd1280:11'd640;
wire [10:0] ht=mode_hd?11'd1980:11'd800;
wire [9:0] va=mode_hd?10'd720:10'd480;
wire [9:0] vt=mode_hd?10'd750:10'd525;
wire h_sync=mode_hd?(h>=1720 && h<1760):(h>=656 && h<752);
wire v_sync=mode_hd?(v>=725 && v<730):(v>=490 && v<492);
assign hs=mode_hd?h_sync:!h_sync;
assign vs=mode_hd?v_sync:!v_sync;
assign de=h<ha && v<va;
assign x=h;
assign y=v;
assign line_start=h==0;
assign frame_blank_start=h==0 && v==va;
always @(posedge clk or posedge rst) begin
 if(rst) begin h<=0;v<=0;ack<=0;read_req<=0;end
 else begin
  ack<={ack[0],read_req_ack};
  if(h==ht-1) begin h<=0;if(v==vt-1)v<=0;else v<=v+1;end
  else h<=h+1;
  if(frame_blank_start && frame_enable) read_req<=1;
  else if(ack[1]) read_req<=0;
 end
end
endmodule
