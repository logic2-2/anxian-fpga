// Three registered pixel stages including label and font block-ROM lookups.
// scene is a frame-committed descriptor: valid/fault/error/ready/mode/theme.
module exhibit_osd(
 input clk,rst,input [13:0] scene,
 input hs_in,vs_in,de_in,input [23:0] rgb_in,
 output reg hs_out,vs_out,de_out,output reg [23:0] rgb_out
);
reg [9:0] x,y;
reg de_d,vs_d;
reg [3:0] line_id;
(* rom_style="bram" *) reg [7:0] label_rows[0:511];
initial $readmemh("E:/FPGA/anxian_contest/project_v57/rtl/label_rows.hex",label_rows);
reg [7:0] label_char;
reg [2:0] gx_label,gy_label;
reg label_text_valid,label_h,label_v,label_d;
reg [23:0] label_bg;

(* rom_style="bram" *) reg [4:0] font_rows[0:1023];
initial $readmemh("E:/FPGA/anxian_contest/project_v57/rtl/font_rows.hex",font_rows);
reg [4:0] font_row;
reg [2:0] gx_d;
reg text_valid_d,h_d,v_d,d_d;
reg [23:0] bg_d;
reg [4:0] col;
reg [2:0] gx,gy;

reg [23:0] composed,accent;

always @* begin
 case(scene[1:0])
  0: accent=24'h35d8e6;
  1: accent=24'h7a9bff;
  2: accent=24'hfbbf45;
  default: accent=24'hd989e8;
 endcase
 line_id=4'd15;col=0;gx=0;gy=0;
 if(y>=12 && y<26) begin
  case(scene[1:0])
   2'd0: line_id=4'd0;
   2'd1: line_id=4'd1;
   2'd2: line_id=4'd2;
   2'd3: line_id=4'd3;
  endcase
 end else if(y>=38 && y<52) begin
  if(scene[12]) line_id=4'd4;
  else if(!scene[13]) line_id=4'd5;
  else if(scene[3:2]==2) begin
   case(scene[1:0])
    2'd0: line_id=4'd6;
    2'd1: line_id=4'd7;
    2'd2: line_id=4'd8;
    2'd3: line_id=4'd9;
   endcase
  end else if(scene[3:2]==1) line_id=4'd10;
  else line_id=4'd11;
 end else if(y>=454 && y<468) begin
  if(scene[3:2]==2) line_id=4'd12;
  else if(scene[3:2]==1) line_id=4'd13;
  else line_id=4'd14;
 end
 // Each cell is 16x16: 5x7 glyph doubled with padding.
 if(x>=16 && x<528) begin
  col=(x-16)>>4;gx=((x-16)&15)>>1;
  if(y>=454) gy=(y-454)>>1;
  else if(y>=38) gy=(y-38)>>1;
  else gy=(y-12)>>1;
 end
 composed=rgb_in;
 if(y<64 || y>=448) composed=24'h111d2c;
 if(y>=60 && y<64) composed=accent;
 // Four readiness indicators. A selected theme gets a white upper border.
 if(x>=552 && x<624 && y>=12 && y<26) begin
  case((x-552)>>4)
   0: composed=scene[4]?accent:24'h344154;
   1: composed=scene[5]?accent:24'h344154;
   2: composed=scene[6]?accent:24'h344154;
   3: composed=scene[7]?accent:24'h344154;
   default: composed=24'h111d2c;
  endcase
  if(((x-552)&15)>=12) composed=24'h111d2c;
  else if(y<14 && ((x-552)>>4)==scene[1:0]) composed=24'hffffff;
 end
end
always @(posedge clk) begin
 label_char<=label_rows[{line_id,col}];
 font_row<=font_rows[{label_char[6:0],gy_label}];
end
always @(posedge clk or posedge rst) begin
 if(rst) begin
  x<=0;y<=0;de_d<=0;vs_d<=0;
  hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;gx_d<=0;text_valid_d<=0;h_d<=0;v_d<=0;d_d<=0;bg_d<=0;gx_label<=0;gy_label<=0;label_text_valid<=0;label_h<=0;label_v<=0;label_d<=0;label_bg<=0;
 end else begin
  de_d<=de_in;vs_d<=vs_in;
  if(!de_in) x<=0;
  else if(x==639) x<=0;
  else x<=x+1;
  if(vs_d && !vs_in) y<=0;
  else if(de_d && !de_in) begin if(y<479) y<=y+1;else y<=0;end
  gx_label<=gx;gy_label<=gy;label_text_valid<=x>=16 && x<528 && gx<5 && gy<7;
  label_h<=hs_in;label_v<=vs_in;label_d<=de_in;label_bg<=composed;
  gx_d<=gx_label;text_valid_d<=label_text_valid;
  h_d<=label_h;v_d<=label_v;d_d<=label_d;bg_d<=label_bg;
  hs_out<=h_d;vs_out<=v_d;de_out<=d_d;
  rgb_out<=d_d?(text_valid_d && font_row[4-gx_d]?24'hf4f8ff:bg_d):24'd0;
 end
end
endmodule
