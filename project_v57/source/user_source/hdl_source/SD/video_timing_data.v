module video_timing_data #(parameter DATA_WIDTH=16)(
 input split_video,
 input video_clk,rst,frame_enable,read_req_ack,mode_hd,small_view,firstpage,fit,
 output reg read_req,output hs,vs,de,output display_de
);
wire rh,rv,rd,line_start,blank_start;wire[10:0] x;wire[9:0] y;
reg[1:0] ah,av,ad,nd,ack;
// Native HD frame or native 640x360 RGB332 companion, never 320x180 upscale.
wire canvas=rd && (split_video?(x<640 && y>=180 && y<540):firstpage?
 (mode_hd?(fit || (x>=320 && x<960 && y>=180 && y<540)):
   (fit?(y>=60 && y<420):(x>=160 && x<480 && y>=150 && y<330))):
 (mode_hd ? (!small_view || (x>=320 && x<960 && y>=180 && y<540)) : (y>=60 && y<420)));
exhibit_dual_timing timing(.clk(video_clk),.rst(rst),.mode_hd(mode_hd),.frame_enable(1'b0),
 .read_req_ack(1'b0),.read_req(),.hs(rh),.vs(rv),.de(rd),.x(x),.y(y),
 .line_start(line_start),.frame_blank_start(blank_start));
assign hs=ah[1];assign vs=av[1];assign de=ad[1];assign display_de=nd[1];
always @(posedge video_clk or posedge rst)begin
 if(rst)begin ah<=0;av<=0;ad<=0;nd<=0;ack<=0;read_req<=0;end
 else begin
  ah<={ah[0],rh};av<={av[0],rv};ad<={ad[0],canvas};nd<={nd[0],rd};ack<={ack[0],read_req_ack};
  if(blank_start && frame_enable)read_req<=1;else if(ack[1])read_req<=0;
 end
end
endmodule
