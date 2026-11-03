// Six raster masks. Parameter thresholds settle in vertical blank.
// Mask, colour multiply and output occupy three aligned pixel stages.
module exhibit_video_transition(
 input clk,rst,mode_hd,input [2:0] effect,input hs,vs,de,input [23:0] rgb,input [8:0] gain,
 output reg ohs,ovs,ode,output reg [23:0] orgb
);
reg [10:0] x;reg [9:0] y;reg de_d,vs_d;
reg [16:0] r,g,b;reg h0,v0,d0,h1,v1,d1;reg keep_pixel;
reg [23:0] masked_rgb;reg [8:0] gain0;
wire [11:0] width=mode_hd?12'd1280:12'd640;
wire [10:0] height=mode_hd?11'd720:11'd480;
reg [11:0] edge_x,left_x,right_x;
reg [10:0] edge_y,top_y,bottom_y;
reg [14:0] vertical_product;
reg [6:0] rank_limit;
reg [8:0] colour_gain;
reg [2:0] effect_q;
wire [5:0] rank={x[4]^y[4],y[4],x[5]^y[5],y[5],x[6]^y[6],y[6]};
// Settings and envelope only change at frame commits, before active video.
always @(posedge clk or posedge rst)begin
 if(rst)begin
  edge_x<=0;edge_y<=0;left_x<=0;right_x<=0;top_y<=0;bottom_y<=0;
  vertical_product<=0;rank_limit<=0;colour_gain<=0;effect_q<=0;
 end else begin
  edge_x<=mode_hd?({3'd0,gain}<<2)+gain:({3'd0,gain}<<1)+(gain>>1);
  vertical_product<=mode_hd?gain*6'd45:gain*4'd15;
  edge_y<=mode_hd?vertical_product>>4:vertical_product>>3;
  left_x<=(width-edge_x)>>1;right_x<=(width+edge_x)>>1;
  top_y<=(height-edge_y)>>1;bottom_y<=(height+edge_y)>>1;
  rank_limit<=gain[8:2];colour_gain<=effect==0?gain:9'd256;effect_q<=effect;
 end
end
always @*begin
 case(effect_q)
  0:keep_pixel=1;
  1:keep_pixel=x<edge_x;
  2:keep_pixel=y<edge_y;
  3:keep_pixel=x>=left_x && x<right_x && y>=top_y && y<bottom_y;
  4:keep_pixel={1'b0,rank}<rank_limit;
  5:keep_pixel=y[4]?(x>=width-edge_x):(x<edge_x);
  default:keep_pixel=1;
 endcase
end
always @(posedge clk or posedge rst)begin
 if(rst)begin x<=0;y<=0;de_d<=0;vs_d<=0;r<=0;g<=0;b<=0;h0<=0;v0<=0;d0<=0;masked_rgb<=0;gain0<=0;h1<=0;v1<=0;d1<=0;ohs<=0;ovs<=0;ode<=0;orgb<=0;end
 else begin
  de_d<=de;vs_d<=vs;
  if(!de)x<=0;else if(x==(mode_hd?1279:639))x<=0;else x<=x+1'b1;
  if(vs_d && !vs)y<=0;
  else if(de_d && !de)begin if(y==(mode_hd?719:479))y<=0;else y<=y+1'b1;end
  masked_rgb<=de && keep_pixel?rgb:24'd0;gain0<=colour_gain;
  h0<=hs;v0<=vs;d0<=de;
  r<=masked_rgb[23:16]*gain0;g<=masked_rgb[15:8]*gain0;b<=masked_rgb[7:0]*gain0;
  h1<=h0;v1<=v0;d1<=d0;ohs<=h1;ovs<=v1;ode<=d1;
  orgb<=d1?{r[15:8],g[15:8],b[15:8]}:24'd0;
 end
end
endmodule
