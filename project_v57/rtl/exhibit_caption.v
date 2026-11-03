// Playback timestamps use consumed PCM frames, including FIFO read-ahead.
module exhibit_caption_track(
 input clk,rst,active,clear,input [2:0] track,input [24:0] position_bytes,
 input [10:0] fifo_used,output reg [5:0] cue
);
`include "E:/FPGA/anxian_contest/project_v57/rtl/caption_tracks.vh"
reg [11:0] buffered_frames;
reg [12:0] played_units;
reg cue_wait;
reg [2:0] previous_track;
wire [15:0] end_units;
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(6),.ADDR_WIDTH_B(6),
 .DATA_DEPTH_A(64),.DATA_DEPTH_B(64),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("32K"),.FORCE_KEEP("ON"),
 .INIT_FILE("E:/FPGA/anxian_contest/project_v57/rtl/caption_ends.dath")) timeline(
 .dia(16'd0),.addra(cue),.cea(1'b1),.ocea(1'b1),.clka(clk),.wea(1'b0),.rsta(1'b0),.bea(1'b1),.doa(end_units),
 .dib(16'd0),.addrb(6'd0),.ceb(1'b0),.oceb(1'b0),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b1),.dob());
always @(posedge clk or posedge rst)begin
 if(rst)begin cue<=0;buffered_frames<=11;played_units<=0;previous_track<=0;cue_wait<=0;end
 else begin
  previous_track<=track;
  buffered_frames<={1'b0,fifo_used}+12'd11;
  played_units<=(position_bytes[24:2]-{11'd0,buffered_frames})>>10;
  if(!active || track==0)begin cue<=0;cue_wait<=1;end
  else if(clear || track!=previous_track || cue==0)begin cue<=first_caption(track);played_units<=0;cue_wait<=1;end
  else if(cue_wait)cue_wait<=0;
  else if(cue<last_caption(track) && {3'd0,played_units}>=end_units)begin cue<=cue+1'b1;cue_wait<=1;end
 end
end
endmodule

// Held-payload/toggle mailbox: a caption ID stays stable until video ACK.
// Captions commit only in vertical blank, so a line cannot tear mid-frame.
module exhibit_caption_osd(
 input source_clk,source_rst,input [5:0] source_cue,
 input clk,rst,mode_hd,enable,hs,vs,de,input [23:0] rgb,
 output reg ohs,ovs,ode,output reg [23:0] orgb
);
reg [5:0] payload;
reg request,ack;
(* async_reg="true" *) reg [2:0] ack_sync,request_sync;
reg [5:0] active_cue;
always @(posedge source_clk or posedge source_rst)begin
 if(source_rst)begin payload<=0;request<=0;ack_sync<=0;end
 else begin
  ack_sync<={ack_sync[1:0],ack};
  if(ack_sync[2]==request && payload!=source_cue)begin payload<=source_cue;request<=~request;end
 end
end
reg [10:0] x;reg [9:0] y;reg de_d,vs_d;
wire mailbox_rst;
media_reset_sync mailbox_reset(clk,source_rst,mailbox_rst);
// Keep the caption handshake alive across a video-mode-only reset, matching
// the source mailbox lifetime. The raster pipeline still resets per mode.
always @(posedge clk or posedge mailbox_rst)begin
 if(mailbox_rst)begin request_sync<=0;ack<=0;active_cue<=0;end
 else begin
  request_sync<={request_sync[1:0],request};
  if(vs_d && !vs && request_sync[2]!=ack)begin active_cue<=payload;ack<=request_sync[2];end
 end
end
wire [4:0] col=x[9:5]-(mode_hd?5'd11:5'd1);
wire in_x=mode_hd?(x>=352 && x<928):(x>=32 && x<608);
// Bottom caption strip is separated from the spectrum (HD ends at646,
// VGA ends at436). Moving by whole32-row cells preserves the font row index.
wire in_y=mode_hd?(y>=672 && y<696):(y>=448 && y<472);
wire panel_y=mode_hd?(y>=668 && y<700):(y>=444 && y<476);
reg line_ink,line_panel;
// These predicates settle during horizontal blank before active pixels.
always @(posedge clk or posedge rst)begin
 if(rst)begin line_ink<=0;line_panel<=0;end
 else begin line_ink<=in_y;line_panel<=panel_y;end
end
wire [7:0] character;
reg [4:0] row0,gx0,gx1;
reg panel0,panel1,panel2,ink_area0,ink_area1,ink_q;
reg h0,v0,d0,h1,v1,d1,h2,v2,d2;
reg [23:0] rgb0,rgb1,rgb2;
wire [23:0] glyph;
wire [12:0] font_address={character,row0};
wire text_read=enable && active_cue!=0 && de && in_x && line_ink;
EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
 .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("32K"),.FORCE_KEEP("ON"),
 .INIT_FILE("E:/FPGA/anxian_contest/project_v57/rtl/caption_text.dath")) text_rom(
 .dia(8'd0),.addra({active_cue,col}),.cea(text_read),.ocea(1'b1),.clka(clk),.wea(1'b0),.rsta(1'b0),.bea(1'b1),.doa(character),
 .dib(8'd0),.addrb(11'd0),.ceb(1'b0),.oceb(1'b0),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b1),.dob());
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(13),.ADDR_WIDTH_B(13),
 .DATA_DEPTH_A(8192),.DATA_DEPTH_B(8192),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("32K"),.FORCE_KEEP("ON"),
 .INIT_FILE("E:/FPGA/anxian_contest/project_v57/rtl/caption_font_hi.dath")) glyph_hi(
 .dia(16'd0),.addra(font_address),.cea(ink_area0),.ocea(1'b1),.clka(clk),.wea(1'b0),.rsta(1'b0),.bea(1'b1),.doa(glyph[23:8]),
 .dib(16'd0),.addrb(13'd0),.ceb(1'b0),.oceb(1'b0),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b1),.dob());
EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(13),.ADDR_WIDTH_B(13),
 .DATA_DEPTH_A(8192),.DATA_DEPTH_B(8192),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("32K"),.FORCE_KEEP("ON"),
 .INIT_FILE("E:/FPGA/anxian_contest/project_v57/rtl/caption_font_lo.dath")) glyph_lo(
 .dia(8'd0),.addra(font_address),.cea(ink_area0),.ocea(1'b1),.clka(clk),.wea(1'b0),.rsta(1'b0),.bea(1'b1),.doa(glyph[7:0]),
 .dib(8'd0),.addrb(13'd0),.ceb(1'b0),.oceb(1'b0),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b1),.dob());
wire ink=ink_area1 && gx1>=4 && gx1<28 && glyph[5'd27-gx1];
always @(posedge clk or posedge rst)begin
 if(rst)begin
  x<=0;y<=0;de_d<=0;vs_d<=0;
  row0<=0;gx0<=0;gx1<=0;panel0<=0;panel1<=0;panel2<=0;ink_area0<=0;ink_area1<=0;ink_q<=0;
  h0<=0;v0<=0;d0<=0;h1<=0;v1<=0;d1<=0;h2<=0;v2<=0;d2<=0;rgb0<=0;rgb1<=0;rgb2<=0;
  ohs<=0;ovs<=0;ode<=0;orgb<=0;
 end else begin
  de_d<=de;vs_d<=vs;
  if(vs_d && !vs)begin
   y<=0;
  end else if(de_d && !de)y<=y==(mode_hd?719:479)?0:y+1'b1;
  if(!de)x<=0;else x<=x==(mode_hd?1279:639)?0:x+1'b1;
  row0<=y[4:0];gx0<=x[4:0];gx1<=gx0;ink_q<=ink;
  panel0<=enable && active_cue!=0 && in_x && line_panel;
  ink_area0<=enable && active_cue!=0 && in_x && line_ink;
  panel1<=panel0;ink_area1<=ink_area0;panel2<=panel1;
  h0<=hs;v0<=vs;d0<=de;rgb0<=rgb;h1<=h0;v1<=v0;d1<=d0;rgb1<=rgb0;
  h2<=h1;v2<=v1;d2<=d1;rgb2<=rgb1;
  ohs<=h2;ovs<=v2;ode<=d2;
  orgb<=!d2?24'd0:!panel2?rgb2:ink_q?24'hffffff:{2'b00,rgb2[23:18],2'b00,rgb2[15:10],2'b00,rgb2[7:2]};
 end
end
endmodule
