// Check the final RGB pixels in the static image body before HDMI transport.
// CRC32 processes one RGB-folded byte per pixel; references come from the
// original HD BMPs after the same RGB565 quantization/expansion as scanout.
module exhibit_pixel_integrity(
 input clk,rst,hs,vs,de,eligible,input [1:0] theme,input [23:0] rgb,
 output reg [15:0] bad_frames,checked_frames,output reg [31:0] last_crc
);
reg [10:0] x;reg [9:0] y;
reg de_d,vs_d,frame_ok;
reg [1:0] saved_theme;
reg [31:0] crc;reg [1:0] previous_theme;reg have_previous;
wire in_roi=de && y>=144 && y<592;
wire first_pixel=x==0 && y==144;
wire last_pixel=x==1279 && y==591;
wire [7:0] folded=rgb[23:16]^{rgb[14:8],rgb[15]}^{rgb[5:0],rgb[7:6]};
function [31:0] crc_byte;
 input [31:0] old_crc;input [7:0] value;
 reg [31:0] c;integer k;
 begin
  c=old_crc^{24'd0,value};
  for(k=0;k<8;k=k+1)c=c[0]?((c>>1)^32'hedb88320):(c>>1);
  crc_byte=c;
 end
endfunction
wire [31:0] next_crc=crc_byte(crc,folded);
always @(posedge clk or posedge rst)begin
 if(rst)begin
  x<=0;y<=0;de_d<=0;vs_d<=0;frame_ok<=0;saved_theme<=0;
  crc<=32'hffffffff;bad_frames<=0;checked_frames<=0;last_crc<=0;previous_theme<=0;have_previous<=0;
 end else begin
  de_d<=de;vs_d<=vs;
  if(!de)x<=0;else if(x==1279)x<=0;else x<=x+1'b1;
  if(vs_d && !vs)y<=0;
  else if(de_d && !de)begin if(y==719)y<=0;else y<=y+1'b1;end
  if(y<144 || y>=592)crc<=32'hffffffff;
  if(in_roi)begin
   crc<=next_crc;
   if(first_pixel)begin frame_ok<=eligible;saved_theme<=theme;end
   else frame_ok<=frame_ok && eligible && theme==saved_theme;
   if(last_pixel && frame_ok && eligible && theme==saved_theme)begin
    if(checked_frames!=16'hffff)checked_frames<=checked_frames+1'b1;
    if(have_previous && saved_theme==previous_theme && (~next_crc)!=last_crc && bad_frames!=16'hffff)bad_frames<=bad_frames+1'b1;
    last_crc<=~next_crc;previous_theme<=saved_theme;have_previous<=1;
   end
  end
 end
end
endmodule
