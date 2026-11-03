// Two pixel stages: Q8 percent contrast, then unit-step brightness and saturation.
module exhibit_video_adjust(
 input clk,rst,mode_hd,hs,vs,de,visible,small_view,input [1:0] profile,
 input [6:0] brightness_code,input [7:0] contrast_percent,
 input [23:0] rgb,
 output reg ohs,ovs,ode,output reg [23:0] orgb
);
reg [10:0] x;reg [9:0] y;reg de_d,vs_d;
wire [8:0] contrast;
exhibit_percent_gain percent_gain(clk,rst,contrast_percent,contrast);
wire signed [9:0] brightness=10'sd0;
reg signed [18:0] pr,pg,pb;
reg signed [9:0] bright_d;
reg h1,v1,d1,keep1;
function [7:0] sat;
 input signed [19:0] value;
 begin if(value<0)sat=0;else if(value>255)sat=255;else sat=value[7:0];end
endfunction
// Screen brightness is now applied after every visual layer.

always @(posedge clk or posedge rst) begin
 if(rst)begin
  x<=0;y<=0;de_d<=0;vs_d<=0;pr<=0;pg<=0;pb<=0;bright_d<=0;
  h1<=0;v1<=0;d1<=0;keep1<=0;ohs<=0;ovs<=0;ode<=0;orgb<=0;
 end else begin
  de_d<=de;vs_d<=vs;
  if(!de)x<=0;else if(x==(mode_hd?1279:639))x<=0;else x<=x+1;
  if(vs_d && !vs)y<=0;else if(de_d && !de)begin if(y==(mode_hd?719:479))y<=0;else y<=y+1;end
  pr<=($signed({1'b0,rgb[23:16]})-9'sd128)*$signed({1'b0,contrast});
  pg<=($signed({1'b0,rgb[15:8]})-9'sd128)*$signed({1'b0,contrast});
  pb<=($signed({1'b0,rgb[7:0]})-9'sd128)*$signed({1'b0,contrast});
  bright_d<=brightness;h1<=hs;v1<=vs;d1<=de;
  // Do not reserve permanent strips for OSD: after notifications fade the
  // complete cached picture must remain available in both video modes.
  keep1<=visible;
  ohs<=h1;ovs<=v1;ode<=d1;
  orgb<=d1 && keep1?{sat((pr>>>8)+128+bright_d),sat((pg>>>8)+128+bright_d),sat((pb>>>8)+128+bright_d)}:24'd0;
 end
end
endmodule
