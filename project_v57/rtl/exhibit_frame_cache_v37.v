// Four 1280x720 RGB565 frames plus four 640x360 RGB332 thumbnails.
// 2073600 32-bit words total, below the 2097152-word SDRAM capacity.
// Both write streams originate from the same BMP decode, so no extra TF read.
module exhibit_frame_cache_v37 #(
 parameter WRITE_V_FLIP=1,FRAME_WIDTH=640,FRAME_HEIGHT=720,ENABLE_BRAND_INTRO=0
)(
 output [15:0] underflows,overflows,
 input rst,video_rst,packed_read,mem_clk,Sdr_init_done,Sdr_init_ref_vld,Sdr_busy,small_view,
 output App_rd_en,output [20:0] App_rd_addr,input Sdr_rd_en,input [31:0] Sdr_rd_dout,
 input read_clk,read_req,output read_req_ack,read_finish,
 input [20:0] read_addr_0,read_addr_1,read_addr_2,read_addr_3,
 input [1:0] read_addr_index,input [20:0] read_len,input read_en,output [31:0] read_data,
 output App_wr_en,output [20:0] App_wr_addr,output [31:0] App_wr_din,output [3:0] App_wr_dm,
 input write_clk,write_req,output write_req_ack,output reg write_finish,
 input [20:0] write_addr_0,write_addr_1,write_addr_2,write_addr_3,
 input [1:0] write_addr_index,input [20:0] write_len,input write_en,input [31:0] write_data,
 input movie_split_read,movie_split_display,
 input movie_read,movie_display,movie_write,movie_write_slot,movie_read_slot,
 input first_video,fit,
 input anim_want,anim_release,anim_rd_en,input [20:0] anim_rd_addr,
 output anim_grant,anim_valid,output reg intro_valid,intro_checked
);
wire main_we,main_ack,main_finish,main_write_active,main_read_active;
wire main_rd_en;wire [20:0] main_rd_addr;
reg anim_owner,thumb_owner;
wire compact=read_addr_index==0;
wire repeat_hd=compact && packed_read && fit;
wire skip_vga=compact && !packed_read && !fit;
assign anim_grant=anim_owner;
assign anim_valid=Sdr_rd_en && anim_owner;
assign App_rd_en=anim_owner?anim_rd_en:main_rd_en;
assign App_rd_addr=anim_owner?anim_rd_addr:main_rd_addr;
always @(posedge mem_clk or posedge rst)begin
 if(rst)anim_owner<=0;
 else if(!anim_owner)begin
  if(anim_want && !thumb_owner && !main_write_active && !main_read_active && !Sdr_busy && !Sdr_init_ref_vld)anim_owner<=1;
 end else if(anim_release && !Sdr_busy && !Sdr_rd_en)anim_owner<=0;
end
wire [20:0] main_wa;wire [31:0] main_wd;
wire thumb_we,thumb_ack,thumb_finish,thumb_busy;
wire [20:0] thumb_wa;wire [31:0] thumb_wd;
wire [8:0] used;
wire thumb_clear;
reg thumb_was_active;
wire thumb_want;
reg full_done,small_done,finished;
reg [10:0] x;
reg [9:0] y;
reg [15:0] even_pixel;
wire [15:0] rgb565={write_data[31:27],write_data[23:18],write_data[15:11]};
wire [31:0] packed_write={rgb565,even_pixel};
// The write enable below is write_en && x[0]. Qualify inactive halfwords
// as zero as well, keeping a logic stage on the very short SDRAM/FIFO
// data paths without adding or removing a write cycle.
(* keep="true" *) wire [31:0] valid_packed_write=packed_write & {32{x[0]}};

wire [31:0] raw_read_data;
reg preview_half,pending_preview_half;
reg pixel_repeat;reg [1:0] movie_repeat;
always @(posedge read_clk or posedge video_rst)begin
 if(video_rst)movie_repeat<=0;else if(!read_en || !movie_display)movie_repeat<=0;else movie_repeat<=movie_repeat==((packed_read && !movie_split_display)?1:0)?0:movie_repeat+1'b1;
end
always @(posedge read_clk or posedge video_rst)begin
 if(video_rst)pixel_repeat<=0;
 else if(!read_en)pixel_repeat<=0;
 else if(first_video && packed_read && fit)pixel_repeat<=!pixel_repeat;
end
reg [15:0] held_halfword;
reg [23:0] thumb_pack;
wire [7:0] rgb332={write_data[31:29],write_data[23:21],write_data[15:14]};
wire thumb_write_sample=x[2:0]==6 && y[0];
(* keep="true" *) wire [31:0] valid_thumb_write={rgb332,thumb_pack} & {32{thumb_write_sample}};
reg [18:0] hidden_count;
reg [23:0] hidden_pack;
reg [31:0] header_word;
reg header_bad;
wire [7:0] hidden_byte={write_data[26:24],write_data[17:16],write_data[10:8]};
wire [31:0] hidden_word={hidden_byte,header_word[31:8]};
wire intro_slot=ENABLE_BRAND_INTRO && !movie_write && write_addr_index==0;
wire hidden_take=intro_slot && hidden_count<19'd416768;
wire hidden_we=hidden_take && hidden_count[1:0]==3;
wire [31:0] packed_hidden={hidden_byte,hidden_pack};
function [31:0] expected_intro_header;input [4:0] at;begin case(at)
 0:expected_intro_header=32'h49424e41;1:expected_intro_header=1;
 2:expected_intro_header=401147;3:expected_intro_header=40;
 4:expected_intro_header=320;5:expected_intro_header=180;
 6:expected_intro_header=10;7:expected_intro_header=128;
 8:expected_intro_header=14528;9:expected_intro_header=640;
 10:expected_intro_header=4;default:expected_intro_header=0;
endcase end endfunction
always @(posedge write_clk or posedge rst)begin
 if(rst)begin hidden_count<=0;hidden_pack<=0;header_word<=0;header_bad<=0;intro_valid<=0;intro_checked<=0;end
 else if(write_req)begin
  hidden_count<=0;hidden_pack<=0;header_word<=0;
  if(intro_slot)begin header_bad<=0;intro_valid<=0;intro_checked<=0;end
 end else if(write_en && hidden_take)begin
  hidden_count<=hidden_count+1'b1;hidden_pack<={hidden_byte,hidden_pack[23:8]};header_word<=hidden_word;
  if(hidden_count<44 && hidden_count[1:0]==3 && hidden_word!=expected_intro_header(hidden_count[6:2]))header_bad<=1;
  if(hidden_count==127)begin intro_valid<=!header_bad;intro_checked<=1;end
 end
end

// Native mixed-width RAM FIFO emits one RGB565 pixel each read. Preview
// words contain two RGB332 indices per 16-bit output beat.
wire fifo_pop=read_en && (movie_display?(movie_repeat==0):first_video?(packed_read && fit?!pixel_repeat:1'b1):(packed_read || !preview_half));
wire [15:0] selected_pixel=raw_read_data[15:0];
wire [7:0] thumb_pixel=pending_preview_half?held_halfword[15:8]:raw_read_data[7:0];
wire [23:0] expanded565={selected_pixel[15:11],selected_pixel[15:13],selected_pixel[10:5],selected_pixel[10:9],selected_pixel[4:0],selected_pixel[4:2]};
wire [23:0] expanded332={thumb_pixel[7:5],thumb_pixel[7:5],thumb_pixel[7:6],thumb_pixel[4:2],thumb_pixel[4:2],thumb_pixel[4:3],thumb_pixel[1:0],thumb_pixel[1:0],thumb_pixel[1:0],thumb_pixel[1:0]};
assign read_data={(packed_read || first_video || movie_display)?expanded565:expanded332,8'd0};
always @(posedge read_clk or posedge video_rst)begin
 if(video_rst)begin preview_half<=0;pending_preview_half<=0;held_halfword<=0;end
 else begin
  if(read_en && !packed_read)preview_half<=!preview_half;else preview_half<=0;
  pending_preview_half<=preview_half;held_halfword<=raw_read_data[15:0];
 end
end
assign write_req_ack=main_ack && (movie_write || thumb_ack);
assign App_wr_en=thumb_owner?thumb_we:main_we;
assign App_wr_addr=thumb_owner?thumb_wa:main_wa;
assign App_wr_din=thumb_owner?thumb_wd:main_wd;
assign App_wr_dm=0;
always @(posedge mem_clk or posedge rst)begin
 if(rst)begin thumb_owner<=0;thumb_was_active<=0;full_done<=0;small_done<=0;finished<=0;write_finish<=0;end
 else begin
  write_finish<=0;
  if(!thumb_owner)begin
   if(thumb_want && !anim_owner && !anim_want && !main_write_active && !main_read_active && !Sdr_busy && !Sdr_init_ref_vld)begin thumb_owner<=1;thumb_was_active<=0;end
  end else begin
   if(thumb_busy)thumb_was_active<=1;
   if(thumb_was_active && !thumb_busy && !Sdr_busy)begin thumb_owner<=0;thumb_was_active<=0;end
  end
  if(write_req)begin full_done<=0;small_done<=0;finished<=0;end
  else begin
   if(main_finish)full_done<=1;if(thumb_finish)small_done<=1;
   if(!finished && (full_done || main_finish) && (movie_write || small_done || thumb_finish))begin write_finish<=1;finished<=1;end
  end
 end
end
always @(posedge write_clk or posedge rst)begin
 if(rst)begin x<=0;y<=0;even_pixel<=0;thumb_pack<=0;end
 else if(write_req)begin x<=0;y<=0;end
 else if(write_en)begin
  if(!x[0])even_pixel<=rgb565;
  if(!x[0] && y[0])thumb_pack<={rgb332,thumb_pack[23:8]};
  if(x==1279)begin x<=0;if(y==719)y<=0;else y<=y+1;end else x<=x+1;
 end
end
frame_read_write_v37 #(.BURST_SIZE(128),.READ_FIFO_AW(11),.READ_BURST_SIZE(64),.WRITE_V_FLIP(WRITE_V_FLIP),.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT)) main(
 .rst(rst),.monitor_rst(video_rst),.underflows(underflows),.overflows(overflows),.mem_clk(mem_clk),.Sdr_init_done(Sdr_init_done),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy|thumb_owner|anim_owner|anim_want),
 .write_active(main_write_active),.read_active(main_read_active),
 .App_rd_en(main_rd_en),.App_rd_addr(main_rd_addr),.Sdr_rd_en(Sdr_rd_en && !anim_owner),.Sdr_rd_dout(Sdr_rd_dout),
 .read_clk(read_clk),.read_req(read_req),.read_req_ack(read_req_ack),.read_finish(read_finish),
 .read_addr_0(movie_read?(movie_read_slot?21'd1958400:21'd1843200):read_addr_0),.read_addr_1(small_view?21'd1900800:read_addr_1),
 .read_addr_2(small_view?21'd1958400:read_addr_2),.read_addr_3(small_view?21'd2016000:read_addr_3),
 .read_addr_index(read_addr_index),.read_len(movie_read?((packed_read && !movie_split_read)?21'd230400:21'd115200):compact?(repeat_hd?21'd230400:(skip_vga?21'd57600:21'd115200)):(small_view?21'd57600:read_len)),.read_en(fifo_pop),.read_data(raw_read_data),
 .movie_page(movie_read),.movie_hd(packed_read && !movie_split_read),.linear_write(movie_write),.compact_page(compact || movie_read),.compact_repeat(repeat_hd),.compact_skip(skip_vga && !movie_read),
 .App_wr_en(main_we),.App_wr_addr(main_wa),.App_wr_din(main_wd),.App_wr_dm(),
 .write_clk(write_clk),.write_req(write_req),.write_req_ack(main_ack),.write_finish(main_finish),
 .write_addr_0(write_addr_0),.write_addr_1(write_addr_1),.write_addr_2(write_addr_2),.write_addr_3(movie_write?(movie_write_slot?21'd1958400:21'd1843200):write_addr_3),
 .write_addr_index(movie_write?2'd3:write_addr_index),.write_len(movie_write?21'd115200:write_len),.write_en(write_en && x[0]),.write_data(valid_packed_write)
);
wfifo_32_32_512 thumb_fifo(
 .clkr(mem_clk),.clkw(write_clk),.rst(rst|thumb_clear),
 .we(write_en && !movie_write && (intro_slot?hidden_we:thumb_write_sample)),.re(thumb_we),.di(intro_slot?packed_hidden:valid_thumb_write),
 .empty_flag(),.full_flag(),.wrusedw(),.rdusedw(used),.dout(thumb_wd)
);
frame_fifo_write #(.BURST_SIZE(32),.WRITE_V_FLIP(1),.FRAME_WIDTH(160),.FRAME_HEIGHT(360),.INTRO_SCATTER(ENABLE_BRAND_INTRO)) thumb_ctrl(
 .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(Sdr_init_done),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy|!thumb_owner|anim_owner),
 .App_rd_busy(main_write_active|main_read_active),.O_wr_busy(thumb_busy),.App_wr_en(thumb_we),.App_wr_addr(thumb_wa),
 .write_req(write_req && !movie_write),.write_req_ack(thumb_ack),.write_finish(thumb_finish),
 .write_addr_0(21'd1843200),.write_addr_1(21'd1900800),.write_addr_2(21'd1958400),.write_addr_3(21'd2016000),
 .write_addr_index(write_addr_index),.write_len(intro_slot?21'd104192:21'd57600),.write_ready(thumb_want),.fifo_aclr(thumb_clear),.rdusedw({1'b0,used})
);
endmodule
