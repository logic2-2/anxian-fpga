// Native 24-pixel antialiased glyphs at 720p; 12-pixel fallback at VGA.
// Coordinate + label + glyph + coverage + composition + fade: seven stages.
module exhibit_native_osd #(
 parameter SHOW_DIAGNOSTICS=0,INTRO_SUPPRESSION=0
)(
 input clk,rst,mode_hd,menu_open,fit_enabled,input [3:0] cursor,input [31:0] options,input [13:0] scene,input intro_active,
 input [31:0] diagnostic,image_crc,input [3:0] ready_mask,
 input hs_in,vs_in,de_in,input [23:0] rgb_in,
 output reg hs_out,vs_out,de_out,output reg [23:0] rgb_out
);

initial begin

end
`include "E:/FPGA/anxian_contest/project_v57/rtl/menu_zh_values.vh"
reg [10:0] x;reg [9:0] y;reg de_d,vs_d;
reg [4:0] lid;
reg [5:0] col;
reg [3:0] gx;
reg [4:0] row_base;
reg on;
reg [23:0] bg,accent;
reg [2:0] panel,panel0,panel1,panel2,panel3;
reg sticky,sticky0,sticky1,sticky2,sticky3;
wire [4:0] status_opacity;
exhibit_status_toast notification(
 .clk(clk),.rst(rst),.vs(vs_in),.mode_hd(mode_hd),.menu_open(menu_open),
 .scene(scene),.options(options[29:0]),.opacity(status_opacity));
reg [10:0] left;
reg [9:0] top_y;
reg [4:0] lid0;reg [5:0] col0;reg [3:0] gx0;
reg [4:0] row_base0,row_y0;reg row_hd0;
reg t0,h0,v0,d0;reg [23:0] bg0;
wire [7:0] label_character;
reg [7:0] custom_character;reg custom_valid;
reg [4:0] value_kind;reg [5:0] value_column;
reg [7:0] rchar,bchar,cchar,dchar,fchar,echar,tchar,achar,vchar,error_char;
wire [7:0] character=custom_valid?custom_character:label_character;
// Keep static labels in the unused 32K bank, away from the full 9K banks.
// The synchronous ROM has the same one-clock latency as the old label read.
EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
 .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("32K"),.FORCE_KEEP("ON"),
 .INIT_FILE("E:/FPGA/anxian_contest/project_v57/rtl/label_hd_rows.dath")) label_rom(
 .dia(8'd0),.addra({lid0,col0}),.cea(1'b1),.ocea(1'b1),.clka(clk),.wea(1'b0),.rsta(1'b0),.bea(1'b1),.doa(label_character),
 .dib(8'd0),.addrb(11'd0),.ceb(1'b0),.oceb(1'b0),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b1),.dob());
reg [3:0] gx1,gx2;
reg [4:0] gy1;
reg t1,t2,h1,v1,d1,h2,v2,d2;
reg [23:0] bg1,bg2,bg3;
reg h3,v3,d3,t3;reg [1:0] coverage3;
reg h4,v4,d4,h5,v5,d5;
reg [23:0] over4,base4,base5;
reg [4:0] alpha4;
reg signed [14:0] fade_r,fade_g,fade_b;
wire [31:0] bits;
wire [47:0] cjk_bits;
reg cjk2,half2;
function [7:0] hexchar;
 input [3:0] digit;
 begin hexchar=digit<10?8'd48+digit:8'd65+digit-10;end
endfunction
// Generated labels and numeric fields use ASCII32..95; Chinese characters
// select the independent CJK plane. Subtract32 modulo64 by toggling bit5.
wire [5:0] glyph_index={~character[5],character[4:0]};
// 32-row storage alignment replaces the character*24 address adders.
// Visible glyphs still contain the original 24 rows and keep their latency.
wire [10:0] glyph_address={glyph_index,gy1};
wire [10:0] cjk_address={character[5:0],gy1};
EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
 .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("32K"),.FORCE_KEEP("ON"),
 .INIT_FILE("E:/FPGA/anxian_contest/project_v57/rtl/font_hd_rows_32.dath")) ascii_glyphs(
 .dia(32'd0),.addra(glyph_address),.cea(1'b1),.ocea(1'b1),.clka(clk),.wea(1'b0),.rsta(1'b0),.bea(1'b1),.doa(bits),
 .dib(32'd0),.addrb(11'd0),.ceb(1'b0),.oceb(1'b0),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b1),.dob());
// Independent 16-bit planes prevent the mapper from wasting wide ROM blocks.
exhibit_menu_zh_plane #(.INIT_A("E:/FPGA/anxian_contest/project_v57/rtl/font_menu_zh_hi_32_a.hex"),.INIT_B("E:/FPGA/anxian_contest/project_v57/rtl/font_menu_zh_hi_32_b.hex")) zh_hi(clk,cjk_address,cjk_bits[47:32]);
exhibit_menu_zh_plane #(.INIT_A("E:/FPGA/anxian_contest/project_v57/rtl/font_menu_zh_mid_32_a.hex"),.INIT_B("E:/FPGA/anxian_contest/project_v57/rtl/font_menu_zh_mid_32_b.hex")) zh_mid(clk,cjk_address,cjk_bits[31:16]);
exhibit_menu_zh_plane #(.INIT_A("E:/FPGA/anxian_contest/project_v57/rtl/font_menu_zh_lo_32_a.hex"),.INIT_B("E:/FPGA/anxian_contest/project_v57/rtl/font_menu_zh_lo_32_b.hex")) zh_lo(clk,cjk_address,cjk_bits[15:0]);
// A Chinese glyph occupies two cells, with a 24px square in a 32px advance.
wire [4:0] cjk_column=half2?{1'b0,gx2}+5'd12:{1'b0,gx2}-5'd4;
wire cjk_inside=half2?gx2<12:gx2>=4;
wire [1:0] ascii_coverage=(bits>>((15-gx2)*2))&2'b11;
wire [1:0] cjk_coverage=cjk_inside?((cjk_bits>>((23-cjk_column)*2))&2'b11):2'b00;
wire [1:0] coverage=cjk2?cjk_coverage:ascii_coverage;
reg [10:0] scroll,ticker_x,ticker_origin;
// Track the subtitle coordinate with the raster instead of putting subtract,
// add, modulo and text selection in the same pixel path. Both modes start
// from (scroll - 48) modulo 1280; VGA advances two glyph pixels per pixel.
always @(posedge clk or posedge rst)begin
 if(rst)begin ticker_x<=1232;ticker_origin<=1232;end
 else begin
  ticker_origin<=scroll>=48?scroll-11'd48:scroll+11'd1232;
  if(!de_in)ticker_x<=ticker_origin;
  else if(mode_hd)ticker_x<=ticker_x==1279?11'd0:ticker_x+1'b1;
  else ticker_x<=ticker_x>=1278?ticker_x-11'd1278:ticker_x+11'd2;
 end
end
wire [3:0] cursor_safe=cursor<=8?cursor:4'd0;
wire [9:0] cursor_y=mode_hd?10'd218+cursor_safe*10'd32:10'd112+cursor_safe*10'd24;
reg [23:0] btext,ctext,vtext;
reg [15:0] dtext;
wire [79:0] rtext=mode_hd?"1280 X 720":"640 X 480 ";
reg [63:0] etext;
wire [31:0] ttext=options[20]?ZH_ON:ZH_OFF;
wire [31:0] ftext=fit_enabled?ZH_ON:ZH_OFF;
wire [63:0] atext=options[22:21]==0?ZH_AUDIO_OFF:options[22:21]==1?ZH_AUDIO_DETAIL:ZH_AUDIO_ALWAYS;

reg [7:0] bright_sign,contrast_lead,volume_lead;
reg [7:0] bright_abs,contrast_rem,volume_rem;
function [15:0] decimal_pair;
 input [7:0] n;
 reg [3:0] tens;reg [7:0] ones;
 begin
  if(n>=90)begin tens=9;ones=n-90;end
  else if(n>=80)begin tens=8;ones=n-80;end
  else if(n>=70)begin tens=7;ones=n-70;end
  else if(n>=60)begin tens=6;ones=n-60;end
  else if(n>=50)begin tens=5;ones=n-50;end
  else if(n>=40)begin tens=4;ones=n-40;end
  else if(n>=30)begin tens=3;ones=n-30;end
  else if(n>=20)begin tens=2;ones=n-20;end
  else if(n>=10)begin tens=1;ones=n-10;end
  else begin tens=0;ones=n;end
  decimal_pair={8'd48+tens,8'd48+ones};
 end
endfunction
wire [15:0] bright_digits=decimal_pair(bright_abs);
always @*case(options[19:17])
 0:etext=ZH_FADE;1:etext=ZH_WIPE;2:etext=ZH_VWIPE;
 3:etext=ZH_CENTER;4:etext=ZH_TILES;5:etext=ZH_ALTERNATE;
 default:etext=ZH_FADE;
endcase
// Parameter formatting is registered separately from the pixel/glyph path.
always @(posedge clk)begin
 if(rst)begin
  btext<="100";ctext<="100";vtext<="100";dtext<="03";
  bright_sign<=49;bright_abs<=0;contrast_lead<=49;contrast_rem<=0;volume_lead<=49;volume_rem<=0;
 end else begin
  bright_sign<=options[6:0]>=100?8'd49:8'd32;
  bright_abs<=options[6:0]>=100?7'd0:options[6:0];
  contrast_lead<=options[14:7]>=100?8'd49:8'd48;
  contrast_rem<=options[14:7]>=100?options[14:7]-8'd100:options[14:7];
  volume_lead<=options[29:23]>=100?8'd49:8'd48;
  volume_rem<=options[29:23]>=100?options[29:23]-7'd100:options[29:23];
  btext<={bright_sign,(bright_sign==32 && bright_abs<10?8'd32:bright_digits[15:8]),bright_digits[7:0]};
  ctext<={contrast_lead,decimal_pair(contrast_rem)};
  vtext<={volume_lead,decimal_pair(volume_rem)};
  case(options[16:15])
   0:dtext<="03";1:dtext<="05";2:dtext<="08";default:dtext<="12";
  endcase
 end
end
function [23:0] shade;
 input [23:0] colour;
 reg [8:0] r,g,b;
 begin r={1'b0,colour[23:16]}+17;g={1'b0,colour[15:8]}+29;b={1'b0,colour[7:0]}+44;shade={r[8:1],g[8:1],b[8:1]};end
endfunction
reg [23:0] painted_bg,painted3;
// Paint alongside glyph coverage so the shade and antialias adders do not
// share one pixel cycle. The output retains its existing seven-stage delay.
always @*case(panel2)
 1:painted_bg=24'h111d2c;
 2:painted_bg=accent;
 3:painted_bg=shade(bg2);
 5:painted_bg=24'h3f6480;
 6:painted_bg=24'h294963;
 default:painted_bg=bg2;
endcase
wire [9:0] er={2'b0,painted3[23:16]}+{1'b0,painted3[23:16],1'b0}+10'd245;
wire [9:0] eg={2'b0,painted3[15:8]}+{1'b0,painted3[15:8],1'b0}+10'd248;
wire [9:0] eb={2'b0,painted3[7:0]}+{1'b0,painted3[7:0],1'b0}+10'd255;
wire [8:0] hr={1'b0,painted3[23:16]}+9'd245;
wire [8:0] hg={1'b0,painted3[15:8]}+9'd248;
wire [8:0] hb={1'b0,painted3[7:0]}+9'd255;
function [7:0] finish_fade;
 input [7:0] original;
 input signed [14:0] product;
 begin finish_fade=$signed({1'b0,original})+(product>>>4);end
endfunction

always @*begin
 case(scene[1:0])
  0:accent=24'h35d8e6;1:accent=24'h7a9bff;
  2:accent=24'hfbbf45;default:accent=24'hd989e8;
 endcase
 lid=31;col=0;gx=0;row_base=0;on=0;bg=rgb_in;panel=0;sticky=0;
 if(mode_hd)begin
  if(y<110 || y>=650)panel=1;
  if(y>=106 && y<110)panel=2;
  if(y>=22 && y<46)begin lid={3'd0,scene[1:0]};row_base=5'd22;end
  else if(y>=64 && y<88)begin
   lid=scene[12]?4:(!scene[13]?5:(scene[3:2]==2?6+scene[1:0]:(scene[3:2]==1?10:11)));row_base=5'd0;
  end else if(y>=678 && y<702)begin lid=scene[3:2]==2?12:13;row_base=5'd6;end
  if(x>=48 && x<1072)begin col=x[9:4]-6'd3;gx=x[3:0];on=lid!=31;end
 end else begin
  if(y<60 || y>=440)panel=1;
  if(y>=56 && y<60)panel=2;
  if(y>=12 && y<24)begin lid={3'd0,scene[1:0]};row_base=5'd12;end
  else if(y>=32 && y<44)begin
   lid=scene[12]?4:(!scene[13]?5:(scene[3:2]==2?6+scene[1:0]:(scene[3:2]==1?10:11)));row_base=5'd0;
  end else if(y>=454 && y<466)begin lid=scene[3:2]==2?12:13;row_base=5'd6;end
  if(x>=24 && x<536)begin col=x[8:3]-6'd3;gx={x[2:0],1'b0};on=lid!=31;end
 end
 // Subtitle layer uses the existing font ROM, with a translucent panel.
 if(options[20] && scene[13] && scene[3:2]!=2 && (mode_hd?(y>=648 && y<672):(y>=428 && y<440)))begin
  panel=3;sticky=1;lid=31;on=0;
  if(x>=(mode_hd?48:24) && x<(mode_hd?1232:616) && ticker_x<1024)begin
   lid=25+scene[1:0];col=ticker_x[9:4];gx=ticker_x[3:0];
   row_base=mode_hd?5'd8:5'd12;on=1;
  end
 end
 left=mode_hd?224:32;top_y=mode_hd?160:64;
 if(menu_open && x>=left && x<left+(mode_hd?832:576) && y>=top_y && y<top_y+(mode_hd?416:336))begin
  panel=1;sticky=1;lid=31;on=0;row_base=0;
  if(y>=cursor_y && y<cursor_y+(mode_hd?30:22))panel=options[31]?5:6;
  if(mode_hd)begin
   if(y>=176 && y<200)begin lid=14;row_base=5'd16;end
   else if(y>=224 && y<248)begin lid=15;row_base=5'd0;end
   else if(y>=256 && y<280)begin lid=16;row_base=5'd0;end
   else if(y>=288 && y<312)begin lid=17;row_base=5'd0;end
   else if(y>=320 && y<344)begin lid=18;row_base=5'd0;end
   else if(y>=352 && y<376)begin lid=20;row_base=5'd0;end
   else if(y>=384 && y<408)begin lid=21;row_base=5'd0;end
   else if(y>=416 && y<440)begin lid=22;row_base=5'd0;end
   else if(y>=448 && y<472)begin lid=23;row_base=5'd0;end
   else if(y>=480 && y<504)begin lid=19;row_base=5'd0;end
   else if(y>=520 && y<544)begin lid=options[31]?29:24;row_base=5'd8;end
   else if(y>=548 && y<572)begin lid=30;row_base=5'd4;end
   if(x>=256 && x<1024)begin col=x[9:4]-6'd16;gx=x[3:0];on=lid!=31;end
  end else begin
   if(y>=80 && y<92)begin lid=14;row_base=5'd16;end
   else if(y>=116 && y<128)begin lid=15;row_base=5'd20;end
   else if(y>=140 && y<152)begin lid=16;row_base=5'd12;end
   else if(y>=164 && y<176)begin lid=17;row_base=5'd4;end
   else if(y>=188 && y<200)begin lid=18;row_base=5'd28;end
   else if(y>=212 && y<224)begin lid=20;row_base=5'd20;end
   else if(y>=236 && y<248)begin lid=21;row_base=5'd12;end
   else if(y>=260 && y<272)begin lid=22;row_base=5'd4;end
   else if(y>=284 && y<296)begin lid=23;row_base=5'd28;end
   else if(y>=308 && y<320)begin lid=19;row_base=5'd20;end
   else if(y>=336 && y<348)begin lid=options[31]?29:24;row_base=5'd16;end
   else if(y>=360 && y<372)begin lid=30;row_base=5'd8;end
   if(x>=48 && x<592)begin col=x[8:3]-6'd6;gx={x[2:0],1'b0};on=lid!=31;end
  end
 end
end
function [7:0] text_byte;
 input [79:0] text;input [5:0] column;
 begin case(column)
  18:text_byte=text[79:72];19:text_byte=text[71:64];
  20:text_byte=text[63:56];21:text_byte=text[55:48];
  22:text_byte=text[47:40];23:text_byte=text[39:32];
  24:text_byte=text[31:24];25:text_byte=text[23:16];
  26:text_byte=text[15:8];27:text_byte=text[7:0];
  default:text_byte=0;
 endcase end
endfunction
always @(posedge clk)begin
 // Sample character candidates in parallel; select the parameter kind after
 // this register boundary. No additional pixel latency is introduced.
 value_kind<=lid0;value_column<=col0;
 rchar<=text_byte(rtext,col0);bchar<=text_byte({btext,56'd0},col0);
 cchar<=text_byte({ctext,56'd0},col0);dchar<=text_byte({dtext,64'd0},col0);
 fchar<=text_byte({ftext,48'd0},col0);echar<=text_byte({etext,16'd0},col0);
 tchar<=text_byte({ttext,48'd0},col0);achar<=text_byte({atext,16'd0},col0);
 vchar<=text_byte({vtext,56'd0},col0);error_char<=hexchar(scene[11:8]);
 if(rst)begin cjk2<=0;half2<=0;end
 else begin cjk2<=character[7];half2<=character[6];end
end
always @*begin
 custom_valid=0;custom_character=0;
 case(value_kind)
  15:if(value_column>=18 && value_column<28)begin custom_valid=1;custom_character=rchar;end
  16:if(value_column>=18 && value_column<21)begin custom_valid=1;custom_character=bchar;end
  17:if(value_column>=18 && value_column<21)begin custom_valid=1;custom_character=cchar;end
  18:if(value_column>=18 && value_column<20)begin custom_valid=1;custom_character=dchar;end
  19:if(value_column>=18 && value_column<22)begin custom_valid=1;custom_character=fchar;end
  20:if(value_column>=18 && value_column<26)begin custom_valid=1;custom_character=echar;end
  21:if(value_column>=18 && value_column<22)begin custom_valid=1;custom_character=tchar;end
  22:if(value_column>=18 && value_column<26)begin custom_valid=1;custom_character=achar;end
  23:if(value_column>=18 && value_column<21)begin custom_valid=1;custom_character=vchar;end
  4:if(value_column==12)begin custom_valid=1;custom_character=error_char;end
 endcase
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  scroll<=0;x<=0;y<=0;de_d<=0;vs_d<=0;lid0<=31;col0<=0;gx0<=0;row_base0<=0;row_y0<=0;row_hd0<=0;t0<=0;h0<=0;v0<=0;d0<=0;bg0<=0;gx1<=0;gx2<=0;gy1<=0;t1<=0;t2<=0;
  h1<=0;v1<=0;d1<=0;h2<=0;v2<=0;d2<=0;bg1<=0;bg2<=0;bg3<=0;h3<=0;v3<=0;d3<=0;t3<=0;coverage3<=0;
  panel0<=0;panel1<=0;panel2<=0;panel3<=0;painted3<=0;sticky0<=0;sticky1<=0;sticky2<=0;sticky3<=0;
  h4<=0;v4<=0;d4<=0;h5<=0;v5<=0;d5<=0;over4<=0;base4<=0;base5<=0;alpha4<=0;fade_r<=0;fade_g<=0;fade_b<=0;
  hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;
 end else begin
  de_d<=de_in;vs_d<=vs_in;
  if(!de_in)x<=0;else if(x==(mode_hd?1279:639))x<=0;else x<=x+1'b1;
  if(vs_d && !vs_in)begin y<=0;scroll<=scroll>=1278?0:scroll+2;end
  else if(de_d && !de_in)begin if(y==(mode_hd?719:479))y<=0;else y<=y+1'b1;end
  lid0<=lid;col0<=col;gx0<=gx;row_base0<=row_base;row_y0<=y[4:0];row_hd0<=mode_hd;t0<=on && !(INTRO_SUPPRESSION && intro_active);h0<=hs_in;v0<=vs_in;d0<=de_in;bg0<=bg;
  panel0<=INTRO_SUPPRESSION && intro_active?3'd0:panel;panel1<=panel0;panel2<=panel1;panel3<=panel2;
  sticky0<=sticky && !(INTRO_SUPPRESSION && intro_active);sticky1<=sticky0;sticky2<=sticky1;sticky3<=sticky2;
  gx1<=gx0;gy1<=row_hd0?(row_y0-row_base0):((row_y0-row_base0)<<1);t1<=t0;h1<=h0;v1<=v0;d1<=d0;bg1<=bg0;
  gx2<=gx1;t2<=t1;h2<=h1;v2<=v1;d2<=d1;bg2<=bg1;
  coverage3<=coverage;painted3<=painted_bg;h3<=h2;v3<=v2;d3<=d2;t3<=t2;bg3<=bg2;
  h4<=h3;v4<=v3;d4<=d3;base4<=bg3;alpha4<=sticky3?5'd16:status_opacity;
  if(!t3 || coverage3==0)over4<=painted3;
  else case(coverage3)
   1:over4<={er[9:2],eg[9:2],eb[9:2]};
   2:over4<={hr[8:1],hg[8:1],hb[8:1]};
   default:over4<=24'hf5f8ff;
  endcase
  fade_r<=($signed({1'b0,over4[23:16]})-$signed({1'b0,base4[23:16]}))*$signed({1'b0,alpha4});
  fade_g<=($signed({1'b0,over4[15:8]})-$signed({1'b0,base4[15:8]}))*$signed({1'b0,alpha4});
  fade_b<=($signed({1'b0,over4[7:0]})-$signed({1'b0,base4[7:0]}))*$signed({1'b0,alpha4});
  base5<=base4;h5<=h4;v5<=v4;d5<=d4;
  hs_out<=h5;vs_out<=v5;de_out<=d5;
  rgb_out<=d5?{finish_fade(base5[23:16],fade_r),finish_fade(base5[15:8],fade_g),finish_fade(base5[7:0],fade_b)}:24'd0;
 end
end
endmodule

module exhibit_menu_zh_plane #(parameter INIT_A="",INIT_B="")(
 input clk,input [10:0] address,output [15:0] q
) /* fehdl keep_hierarchy="true" */;
wire [15:0] qa,qb;reg bank;
exhibit_menu_zh_rom1024 #(.INIT_FILE(INIT_A)) a(clk,address[9:0],qa);
exhibit_menu_zh_rom1024 #(.INIT_FILE(INIT_B)) b(clk,address[9:0],qb);
always @(posedge clk)bank<=address[10];
assign q=bank?qb:qa;
endmodule
module exhibit_menu_zh_rom1024 #(parameter INIT_FILE="")(
 input clk,input [9:0] address,output reg [15:0] q
) /* fehdl keep_hierarchy="true" */;
(* rom_style="bram" *) reg [15:0] data[0:1023];
initial $readmemh(INIT_FILE,data);
always @(posedge clk)q<=data[address];
endmodule
module exhibit_menu_zh_rom512 #(parameter INIT_FILE="")(
 input clk,input [8:0] address,output reg [15:0] q
) /* fehdl keep_hierarchy="true" */;
(* rom_style="bram" *) reg [15:0] data[0:511];
initial $readmemh(INIT_FILE,data);
always @(posedge clk)q<=data[address];
endmodule
