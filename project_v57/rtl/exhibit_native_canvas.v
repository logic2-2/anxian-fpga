// HD pixels pass through at 1:1. VGA uses the 320x180 companion image,
// doubled to a 640x360 letterbox using two rotating line buffers.
module exhibit_native_canvas(
 input clk,rst,mode_hd,hs,vs,native_de,source_de,input [23:0] rgb,
 output ohs,ovs,ode,output [23:0] orgb
);
(* ram_style="block" *) reg [23:0] row0[0:319],row1[0:319];
(* ram_style="block" *) reg [2:0] sync_delay[0:800];
reg [9:0] ptr,filled;
wire [9:0] rp=ptr==800?10'd0:ptr+1'b1;
reg [2:0] delayed,c1;
reg [8:0] wx;
reg wb,source_d,vs_d;
reg [9:0] x,y;
reg de_d,dvs_d,bank,inside;
reg [23:0] q0,q1;
always @(posedge clk)begin
 if(!mode_hd)begin
  sync_delay[ptr]<={hs,vs,native_de};delayed<=sync_delay[rp];
  if(source_de)begin if(wb)row1[wx]<=rgb;else row0[wx]<=rgb;end
 end
 q0<=row0[x[9:1]];q1<=row1[x[9:1]];
end
wire [2:0] dc=filled==801?delayed:3'd0;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  ptr<=0;filled<=0;wx<=0;wb<=0;source_d<=0;vs_d<=0;
  x<=0;y<=0;de_d<=0;dvs_d<=0;c1<=0;bank<=0;inside<=0;
 end else begin
  if(ptr==800)ptr<=0;else ptr<=ptr+1'b1;
  if(filled<801)filled<=filled+1'b1;
  source_d<=source_de;vs_d<=vs;
  if(!source_de)wx<=0;else if(wx==319)wx<=0;else wx<=wx+1'b1;
  if(vs_d && !vs)wb<=0;else if(source_d && !source_de)wb<=!wb;
  de_d<=dc[0];dvs_d<=dc[1];
  if(!dc[0])x<=0;else if(x==639)x<=0;else x<=x+1'b1;
  if(dvs_d && !dc[1])y<=0;
  else if(de_d && !dc[0])begin if(y==479)y<=0;else y<=y+1'b1;end
  c1<=dc;bank<=y[1];inside<=y>=60 && y<420;
 end
end
assign ohs=mode_hd?hs:c1[2];
assign ovs=mode_hd?vs:c1[1];
assign ode=mode_hd?native_de:c1[0];
assign orgb=mode_hd?(source_de?rgb:24'd0):((inside && c1[0])?(bank?q1:q0):24'd0);
endmodule
