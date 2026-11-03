// Load-time BMP resampler. Reuses the FAT32 sector RAM with byte backpressure;
// no line/frame RAM is added. Emits a fixed 1280x720 canvas bottom row first,
// matching the existing cache's WRITE_V_FLIP convention.
// Supports uncompressed 24-bit Windows BMP (40-byte BITMAPINFOHEADER), positive/negative height and
// padded rows, with dimensions 1..4096 and validated file byte bounds.
module exhibit_bmp_fit #(
 parameter integer OUT_W=1280,OUT_H=720,PIXEL_PERIOD=16
)(
 input clk,rst,load_start,sd_init_done,adaptive_enable,input [31:0] file_size_limit,
 output ready,output reg load_error,output reg [31:0] load_debug,
 output reg [3:0] state_code,
 output reg write_req,input write_req_ack,
 output reg sd_sec_read,output [31:0] sd_sec_read_addr,
 input [7:0] sd_sec_read_data,input sd_sec_read_data_valid,sd_sec_read_end,
 output file_ready,output reg bmp_data_wr_en,output reg [23:0] bmp_data,
 output reg [12:0] source_width,source_height
);
localparam IDLE=0,HDR_ISSUE=1,HDR_RX=2,HDR_CHECK=3,GEOM=4,BOUNDS=5,
 DIVIDE=6,LAYOUT=7,WAIT_ACK=8,ROW_START=9,PREFIX=10,ISSUE=11,
 READ_PIX=12,EMIT=13,X_STEP=14,X_REDUCE=15,DRAIN=16,SUFFIX=17,
 NEXT_ROW=18,Y_STEP=19,Y_REDUCE=20,ROW_GAP=21,DONE=22,CROP_ROWS=23;
reg [4:0] state;
reg [8:0] header_index,skip_bytes;
// Validate discarded high bytes as they arrive, instead of retaining wide
// fields that are needed only once per file. This reduces packing pressure.
reg signature_ok,dib_ok,planes_ok,bpp_ok,uncompressed,invalid_width,invalid_height;
reg invalid_size,invalid_offset;
// Admit <=16MiB files and reject discarded high header bytes explicitly.
reg [24:0] file_len;
reg [23:0] pixel_offset;
reg [12:0] width_field;
reg [15:0] height_field;
wire [15:0] abs_height=height_field[15]?(~height_field+16'd1):height_field;
reg top_down,width_limited,sector_done,fit_latched;
reg [13:0] row_stride;
// max payload=4096*4096*3; plus a 24-bit offset is strictly below 2^26.
reg [25:0] payload_bytes,pixel_end;
// Validated files are <=16MiB: 24-bit byte / 15-bit sector addresses suffice.
reg [23:0] row_base;
reg [14:0] sector_number;
reg [12:0] crop_x,crop_rows_left;
wire [23:0] next_row_base=top_down?row_base-row_stride:row_base+row_stride;
wire [23:0] row_start_byte=row_base+({11'd0,crop_x}<<1)+{11'd0,crop_x};
assign sd_sec_read_addr={17'd0,sector_number};
reg [10:0] fit_w,left_pad,canvas_x,inside_x;
reg [9:0] fit_h,bottom_pad,canvas_y,inside_y;
reg [12:0] wanted_x,source_next_x,sampled_x;
reg [13:0] x_rem,y_rem;
reg [1:0] component;
reg [7:0] blue,green;
reg [23:0] held_pixel;
reg [$clog2(PIXEL_PERIOD)-1:0] pace;
reg [22:0] div_work;
reg [13:0] div_rem;
reg [12:0] div_den;
reg [5:0] div_count;
wire [13:0] div_shift={div_rem[12:0],div_work[22]};
wire div_ge=div_shift>={1'b0,div_den};
wire [22:0] div_next={div_work[21:0],div_ge};
wire [23:0] width_cross=source_width*OUT_H;
wire [23:0] height_cross=source_height*OUT_W;
wire vertical_inside=canvas_y>=bottom_pad && canvas_y<bottom_pad+fit_h;
assign ready=state==IDLE;
assign file_ready=state==HDR_RX || state==READ_PIX || state==DRAIN;

task bad_header;
 input [3:0] code;
 begin load_error<=1;load_debug<={code,width_field[11:0],height_field[11:0],4'd0};sd_sec_read<=0;write_req<=0;state<=IDLE;end
endtask

always @(posedge clk or posedge rst)begin
 if(rst)begin
  state<=IDLE;state_code<=0;load_error<=0;load_debug<=0;
  write_req<=0;sd_sec_read<=0;sector_number<=0;
  bmp_data_wr_en<=0;bmp_data<=0;source_width<=0;source_height<=0;
  signature_ok<=0;dib_ok<=0;planes_ok<=0;bpp_ok<=0;uncompressed<=1;invalid_width<=0;invalid_height<=0;invalid_size<=0;invalid_offset<=0;
  file_len<=0;pixel_offset<=0;width_field<=0;height_field<=0;
  header_index<=0;skip_bytes<=0;top_down<=0;width_limited<=0;sector_done<=0;fit_latched<=0;crop_x<=0;crop_rows_left<=0;
  row_stride<=0;payload_bytes<=0;pixel_end<=0;row_base<=0;
  fit_w<=0;fit_h<=0;left_pad<=0;bottom_pad<=0;canvas_x<=0;canvas_y<=0;inside_x<=0;inside_y<=0;
  wanted_x<=0;source_next_x<=0;sampled_x<=0;x_rem<=0;y_rem<=0;component<=0;blue<=0;green<=0;held_pixel<=0;pace<=0;
  div_work<=0;div_rem<=0;div_den<=0;div_count<=0;
 end else begin
  bmp_data_wr_en<=0;
  pace<=pace+1'b1;
  if(sd_sec_read_end)begin sd_sec_read<=0;sector_done<=1;end
  if(!sd_init_done)begin state<=IDLE;write_req<=0;sd_sec_read<=0;load_error<=0;end
  else case(state)
   IDLE: begin
    state_code<=1;write_req<=0;sd_sec_read<=0;
    if(load_start)begin
     load_error<=0;load_debug<=0;header_index<=0;sector_done<=0;fit_latched<=adaptive_enable;
     signature_ok<=0;dib_ok<=0;planes_ok<=0;bpp_ok<=0;uncompressed<=1;invalid_width<=0;invalid_height<=0;invalid_size<=0;invalid_offset<=0;
     file_len<=0;pixel_offset<=0;width_field<=0;height_field<=0;
     state<=HDR_ISSUE;
    end
   end
   HDR_ISSUE: begin sector_number<=0;sd_sec_read<=1;state_code<=2;state<=HDR_RX;end
   HDR_RX: begin
    if(sd_sec_read_data_valid)begin
     header_index<=header_index+1'b1;
     case(header_index)
      0:signature_ok<=sd_sec_read_data=="B";1:if(sd_sec_read_data!="M")signature_ok<=0;
      2:file_len[7:0]<=sd_sec_read_data;3:file_len[15:8]<=sd_sec_read_data;4:file_len[23:16]<=sd_sec_read_data;
      5:begin file_len[24]<=sd_sec_read_data[0];if(|sd_sec_read_data[7:1])invalid_size<=1;end
      10:pixel_offset[7:0]<=sd_sec_read_data;11:pixel_offset[15:8]<=sd_sec_read_data;12:pixel_offset[23:16]<=sd_sec_read_data;
      13:if(sd_sec_read_data!=0)invalid_offset<=1;
      14:dib_ok<=sd_sec_read_data==40;
      15,16,17:if(sd_sec_read_data!=0)dib_ok<=0;
      18:width_field[7:0]<=sd_sec_read_data;
      19:begin width_field[12:8]<=sd_sec_read_data[4:0];if(|sd_sec_read_data[7:5])invalid_width<=1;end
      20,21:if(sd_sec_read_data!=0)invalid_width<=1;
      22:height_field[7:0]<=sd_sec_read_data;23:height_field[15:8]<=sd_sec_read_data;
      24,25:if(sd_sec_read_data!={8{height_field[15]}})invalid_height<=1;
      26:planes_ok<=sd_sec_read_data==1;27:if(sd_sec_read_data!=0)planes_ok<=0;
      28:bpp_ok<=sd_sec_read_data==24;29:if(sd_sec_read_data!=0)bpp_ok<=0;
      30,31,32,33:if(sd_sec_read_data!=0)uncompressed<=0;
     endcase
    end
    if(sd_sec_read_end)state<=HDR_CHECK;
   end
   HDR_CHECK:begin
    if(!signature_ok)bad_header(1);
    else if(invalid_width || invalid_height || width_field==0 || width_field>4096 || abs_height==0 || abs_height>4096)bad_header(2);
    else if(!dib_ok || !planes_ok || !bpp_ok)bad_header(3);
    else if(!uncompressed)bad_header(4);
    else if(invalid_size)bad_header(6);
    else if(invalid_offset || pixel_offset<54)bad_header(7);
    else begin source_width<=width_field;source_height<=abs_height[12:0];top_down<=height_field[15];state<=GEOM;end
   end
   GEOM:begin row_stride<=((source_width*14'd3+14'd3)>>2)<<2;state<=BOUNDS;end
   BOUNDS:begin
    payload_bytes<=row_stride*source_height;
    width_limited<=width_cross>=height_cross;
    div_work<=width_cross>=height_cross?height_cross[22:0]:width_cross[22:0];
    div_den<=width_cross>=height_cross?source_width:source_height;
    div_rem<=0;div_count<=0;state<=DIVIDE;
   end
   DIVIDE:begin
    pixel_end<={2'd0,pixel_offset}+payload_bytes;
    div_work<=div_next;div_rem<=div_ge?div_shift-{1'b0,div_den}:div_shift;
    if(div_count==22)begin
     if(fit_latched)begin
      fit_w<=width_limited?OUT_W:(div_next==0?11'd1:div_next[10:0]);
      fit_h<=width_limited?(div_next==0?10'd1:div_next[9:0]):OUT_H;
      crop_x<=0;crop_rows_left<=0;
     end else begin
      fit_w<=source_width>OUT_W?OUT_W:source_width[10:0];
      fit_h<=source_height>OUT_H?OUT_H:source_height[9:0];
      crop_x<=source_width>OUT_W?(source_width-OUT_W)>>1:13'd0;
      crop_rows_left<=source_height>OUT_H?(source_height-OUT_H)>>1:13'd0;
     end
     state<=LAYOUT;
    end else div_count<=div_count+1'b1;
   end
   LAYOUT:begin
    if(file_len<pixel_end)bad_header(5);
    else if(file_len>32'd16777216 || (file_size_limit!=0 && file_len>file_size_limit))bad_header(6);
    else begin
     left_pad<=(OUT_W-fit_w)>>1;bottom_pad<=(OUT_H-fit_h)>>1;
     row_base<=top_down?(pixel_end-row_stride):pixel_offset;
     canvas_x<=0;canvas_y<=0;inside_y<=0;y_rem<=0;state_code<=3;state<=CROP_ROWS;
    end
   end
   CROP_ROWS:begin
    if(crop_rows_left!=0)begin row_base<=next_row_base;crop_rows_left<=crop_rows_left-1'b1;end
    else begin write_req<=1;state<=WAIT_ACK;end
   end
   WAIT_ACK:if(write_req_ack)begin write_req<=0;state<=ROW_START;end
   ROW_START:begin
    canvas_x<=0;inside_x<=0;wanted_x<=crop_x;source_next_x<=crop_x;sampled_x<=crop_x;x_rem<=0;component<=0;
    if(vertical_inside)state<=PREFIX;else state<=SUFFIX;
   end
   PREFIX:begin
    if(canvas_x==left_pad)begin sector_number<=row_start_byte[23:9];skip_bytes<=row_start_byte[8:0];state<=ROW_GAP;end
    else if(pace==0)begin bmp_data_wr_en<=1;bmp_data<=0;canvas_x<=canvas_x+1'b1;end
   end
   ROW_GAP:state<=ISSUE;
   ISSUE:begin sector_done<=0;sd_sec_read<=1;state_code<=4;state<=READ_PIX;end
   READ_PIX:begin
    if(sd_sec_read_data_valid)begin
     if(skip_bytes!=0)skip_bytes<=skip_bytes-1'b1;
     else case(component)
      0:begin blue<=sd_sec_read_data;component<=1;end
      1:begin green<=sd_sec_read_data;component<=2;end
      2:begin
       component<=0;source_next_x<=source_next_x+1'b1;
       if(source_next_x==wanted_x)begin held_pixel<={sd_sec_read_data,green,blue};sampled_x<=source_next_x;state<=EMIT;end
      end
     endcase
    end else if(sector_done)begin sector_number<=sector_number+1'b1;state<=ROW_GAP;end
   end
   EMIT:if(pace==0)begin
    bmp_data_wr_en<=1;bmp_data<=held_pixel;canvas_x<=canvas_x+1'b1;
    if(inside_x==fit_w-1)state<=DRAIN;
    else begin inside_x<=inside_x+1'b1;state<=X_STEP;end
   end
   X_STEP:begin
    if(fit_latched)begin x_rem<=x_rem+source_width;state<=X_REDUCE;end
    else begin wanted_x<=wanted_x+1'b1;state<=READ_PIX;end
   end
   X_REDUCE:begin
    if(x_rem>=fit_w)begin x_rem<=x_rem-fit_w;wanted_x<=wanted_x+1'b1;end
    else if(wanted_x==sampled_x)state<=EMIT;
    else state<=READ_PIX;
   end
   DRAIN:if(sector_done)state<=SUFFIX;
   SUFFIX:begin
    if(canvas_x==OUT_W)state<=NEXT_ROW;
    else if(pace==0)begin bmp_data_wr_en<=1;bmp_data<=0;canvas_x<=canvas_x+1'b1;end
   end
   NEXT_ROW:begin
    if(canvas_y==OUT_H-1)state<=DONE;
    else begin
     canvas_y<=canvas_y+1'b1;
     if(vertical_inside && inside_y!=fit_h-1)begin inside_y<=inside_y+1'b1;state<=Y_STEP;end
     else state<=ROW_START;
    end
   end
   Y_STEP:begin
    if(fit_latched)begin y_rem<=y_rem+source_height;state<=Y_REDUCE;end
    else begin row_base<=next_row_base;state<=ROW_START;end
   end
   Y_REDUCE:begin
    if(y_rem>=fit_h)begin y_rem<=y_rem-fit_h;row_base<=next_row_base;end
    else state<=ROW_START;
   end
   DONE:begin state_code<=1;state<=IDLE;end
   default:bad_header(15);
  endcase
 end
end
endmodule
