module exhibit_resolution_menu_osd(
 input clk,rst,mode_hd,menu_open,cursor_mode,
 input hs,vs,de,input [23:0] rgb,
 output reg ohs,ovs,ode,output reg [23:0] orgb
);
reg [10:0] x;reg [9:0] y;reg de_d,vs_d;
reg [4:0] font_rows[0:1023];
initial $readmemh("E:/FPGA/anxian_contest/project_v57/rtl/font_rows.hex",font_rows);
wire [10:0] left=mode_hd?11'd400:11'd80;
wire [9:0] top_y=mode_hd?10'd280:10'd160;
reg [2:0] line_id,gy;reg [4:0] column;reg [2:0] gx;
reg text_on;reg [23:0] background;reg [7:0] character;
reg [4:0] glyph;reg [2:0] gx_d;reg text_d;
reg hd,vd,dd;reg [23:0] bg_d;
function [7:0] text_char;
 input [2:0] line;input [4:0] col;reg [255:0] words;
 begin
  case(line)
   0: words="DISPLAY SETTINGS                ";
   1: words=" 640 X 480                      ";
   2: words=" 1280 X 720                     ";
   3: words="NEXT SELECT  VIEW APPLY         ";
   4: words="HOLD VIEW CANCEL                ";
   default: words=0;
  endcase
  text_char=words[255-col*8-:8];
 end
endfunction
always @* begin
 line_id=7;gy=0;column=0;gx=0;text_on=0;background=rgb;character=0;
 if(menu_open && x>=left && x<left+480 && y>=top_y && y<top_y+184) begin
  background=24'h142438;
  if(x==left || x==left+479 || y==top_y || y==top_y+183) background=24'h35d8e6;
  if((!cursor_mode && y>=top_y+48 && y<top_y+76) ||
     (cursor_mode && y>=top_y+80 && y<top_y+108)) background=24'h245266;
  if(y>=top_y+16 && y<top_y+30)begin line_id=0;gy=(y-top_y-16)>>1;end
  else if(y>=top_y+56 && y<top_y+70)begin line_id=1;gy=(y-top_y-56)>>1;end
  else if(y>=top_y+88 && y<top_y+102)begin line_id=2;gy=(y-top_y-88)>>1;end
  else if(y>=top_y+128 && y<top_y+142)begin line_id=3;gy=(y-top_y-128)>>1;end
  else if(y>=top_y+152 && y<top_y+166)begin line_id=4;gy=(y-top_y-152)>>1;end
  if(x>=left+16 && x<left+464 && line_id!=7)begin
   column=(x-left-16)>>4;gx=((x-left-16)&15)>>1;
   character=text_char(line_id,column);text_on=gx<5;
  end
 end
end
always @(posedge clk) glyph<=font_rows[{character[6:0],gy}];
always @(posedge clk or posedge rst) begin
 if(rst)begin x<=0;y<=0;de_d<=0;vs_d<=0;gx_d<=0;text_d<=0;hd<=0;vd<=0;dd<=0;bg_d<=0;ohs<=0;ovs<=0;ode<=0;orgb<=0;end
 else begin
  de_d<=de;vs_d<=vs;
  if(!de)x<=0;else if(x==(mode_hd?1279:639))x<=0;else x<=x+1;
  if(vs_d && !vs)y<=0;
  else if(de_d && !de)begin if(y==(mode_hd?719:479))y<=0;else y<=y+1;end
  gx_d<=gx;text_d<=text_on;hd<=hs;vd<=vs;dd<=de;bg_d<=background;
  ohs<=hd;ovs<=vd;ode<=dd;orgb<=dd?(text_d && glyph[4-gx_d]?24'hf4f8ff:bg_d):24'd0;
 end
end
endmodule
