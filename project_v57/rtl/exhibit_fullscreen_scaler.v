// Streaming 640x480 -> 1280x720 interpolation. Three rotating line buffers
// keep the two source rows needed by the delayed output, plus the incoming row.
// Source rows arrive on phases 0,1 of each three-line group. Output trails
// source timing by 3300 clocks (two HD lines). VGA bypasses the scaler.
module exhibit_fullscreen_scaler(
 input clk,rst,mode_hd,hs,vs,native_de,source_de,input [23:0] rgb,
 output ohs,ovs,ode,output [23:0] orgb
);
(* ram_style="block" *) reg [23:0] row0[0:639];
(* ram_style="block" *) reg [23:0] row1[0:639];
(* ram_style="block" *) reg [23:0] row2[0:639];
(* ram_style="block" *) reg [2:0] sync_delay[0:3300];
reg [11:0] ptr,filled;
wire [11:0] rdptr=ptr==3300?12'd0:ptr+1'b1;
reg [2:0] delayed;
reg [9:0] wx;
reg [1:0] wb;
reg source_d,vs_d;
function [1:0] next_bank;
 input [1:0] b;
 begin next_bank=b==2?0:b+1'b1;end
endfunction

always @(posedge clk) begin
 if(mode_hd) begin
  sync_delay[ptr]<={hs,vs,native_de};
  delayed<=sync_delay[rdptr];
  if(source_de) begin
   case(wb)
    0:row0[wx]<=rgb;
    1:row1[wx]<=rgb;
    2:row2[wx]<=rgb;
   endcase
  end
 end
end
always @(posedge clk or posedge rst) begin
 if(rst)begin ptr<=0;filled<=0;wx<=0;wb<=0;source_d<=0;vs_d<=0;end
 else begin
  if(ptr==3300)ptr<=0;else ptr<=ptr+1'b1;
  if(filled<3301)filled<=filled+1'b1;
  source_d<=source_de;vs_d<=vs;
  if(!source_de)wx<=0;else if(wx==639)wx<=0;else wx<=wx+1'b1;
  if(vs_d && !vs)wb<=0;
  else if(source_d && !source_de)wb<=next_bank(wb);
 end
end

wire [2:0] dc=filled==3301?delayed:3'b000;
reg [10:0] x;
reg [9:0] y;
reg [1:0] phase,bank;
reg de_d,dvs_d;
wire [9:0] rx=x>=1278?10'd639:({1'b0,x[10:1]}+x[0]);
reg [23:0] q0,q1,q2,a,b;
reg [2:0] c1,c2,c3,c4,c5;
reg [1:0] p1,p2,k1;
reg last1,last2,odd1,odd2,odd3,odd4;
reg [9:0] sr,sg,sb;
reg [23:0] vertical,previous,result;
// 171/512 approximates 1/3 with <=1 LSB error over the full 0..765 range.
wire [17:0] mr=sr*8'd171,mg=sg*8'd171,mb=sb*8'd171;
wire [8:0] ar={1'b0,previous[23:16]}+{1'b0,vertical[23:16]}+9'd1;
wire [8:0] ag={1'b0,previous[15:8]}+{1'b0,vertical[15:8]}+9'd1;
wire [8:0] ab={1'b0,previous[7:0]}+{1'b0,vertical[7:0]}+9'd1;
always @(posedge clk)begin
 q0<=row0[rx];q1<=row1[rx];q2<=row2[rx];
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  x<=0;y<=0;phase<=0;bank<=0;de_d<=0;dvs_d<=0;
  c1<=0;c2<=0;c3<=0;c4<=0;c5<=0;p1<=0;p2<=0;k1<=0;
  last1<=0;last2<=0;odd1<=0;odd2<=0;odd3<=0;odd4<=0;
  a<=0;b<=0;sr<=0;sg<=0;sb<=0;vertical<=0;previous<=0;result<=0;
 end else begin
  de_d<=dc[0];dvs_d<=dc[1];
  if(!dc[0])x<=0;else if(x==1279)x<=0;else x<=x+1'b1;
  if(dvs_d && !dc[1])begin y<=0;phase<=0;bank<=0;end
  else if(de_d && !dc[0])begin
   if(y==719)begin y<=0;phase<=0;bank<=0;end
   else begin
    y<=y+1'b1;phase<=phase==2?0:phase+1'b1;
    if(phase!=0)bank<=next_bank(bank);
   end
  end
  c1<=dc;p1<=phase;k1<=bank;last1<=y==719;odd1<=x[0];
  c2<=c1;p2<=p1;last2<=last1;odd2<=odd1;
  case(k1)
   0:begin a<=q0;b<=last1?q0:q1;end
   1:begin a<=q1;b<=last1?q1:q2;end
   default:begin a<=q2;b<=last1?q2:q0;end
  endcase
  c3<=c2;odd3<=odd2;
  case(p2)
   1:begin
    sr<={2'b0,a[23:16]}+{1'b0,b[23:16],1'b0};
    sg<={2'b0,a[15:8]}+{1'b0,b[15:8],1'b0};
    sb<={2'b0,a[7:0]}+{1'b0,b[7:0],1'b0};
   end
   2:begin
    sr<={1'b0,a[23:16],1'b0}+{2'b0,b[23:16]};
    sg<={1'b0,a[15:8],1'b0}+{2'b0,b[15:8]};
    sb<={1'b0,a[7:0],1'b0}+{2'b0,b[7:0]};
   end
   default:begin
    sr<={1'b0,a[23:16],1'b0}+{2'b0,a[23:16]};
    sg<={1'b0,a[15:8],1'b0}+{2'b0,a[15:8]};
    sb<={1'b0,a[7:0],1'b0}+{2'b0,a[7:0]};
   end
  endcase
  c4<=c3;odd4<=odd3;vertical<={mr[16:9],mg[16:9],mb[16:9]};
  c5<=c4;
  if(c4[0] && !odd4)previous<=vertical;
  result<=c4[0]?(odd4?{ar[8:1],ag[8:1],ab[8:1]}:vertical):24'd0;
 end
end
assign ohs=mode_hd?c5[2]:hs;
assign ovs=mode_hd?c5[1]:vs;
assign ode=mode_hd?c5[0]:native_de;
assign orgb=mode_hd?result:rgb;
endmodule
