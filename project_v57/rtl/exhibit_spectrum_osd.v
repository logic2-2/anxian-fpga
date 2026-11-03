// Measured FFT spectrum with frame-atomic state in one9K block.
// Sequential blanking-time updates replace sixteen parallel peak/decay ALUs.
module exhibit_spectrum_osd(input split_video,input clk,rst,mode_hd,hs,vs,de,enable,input [23:0] rgb,
 input [95:0] levels,output reg ohs,ovs,ode,output reg [23:0] orgb);
localparam INIT=0,IDLE=1,FETCH=2,CALC=3,WRITE=4;
reg [2:0] state;reg [3:0] update_index;reg update_pending;
reg [95:0] frame_levels;
wire [15:0] update_q,band_q;
reg [15:0] new_word;
wire update_write=state==INIT || state==WRITE;
wire [15:0] update_data=state==INIT?16'd0:new_word;
wire [5:0] new_level=frame_levels[update_index*6+:6];
wire [5:0] old_shown=update_q[5:0],old_peak=update_q[11:6];
wire [3:0] old_hold=update_q[15:12];
reg [5:0] next_shown,next_peak;reg [3:0] next_hold;
always @*begin
 next_shown=new_level>=old_shown?new_level:(old_shown!=0?old_shown-1'b1:6'd0);
 next_peak=old_peak;next_hold=old_hold;
 if(new_level>=old_peak)begin next_peak=new_level;next_hold=12;end
 else if(old_hold!=0)next_hold=old_hold-1'b1;
 else if(old_peak!=0)next_peak=old_peak-1'b1;
end
reg [10:0] x;reg [9:0] y;reg de_d,vs_d;
wire [3:0] column=split_video?(x[8:5]-4'd6):(mode_hd?x[9:6]:x[8:5])-4'd2;
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(4),.ADDR_WIDTH_B(4),
 .DATA_DEPTH_A(16),.DATA_DEPTH_B(16),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K"),.FORCE_KEEP("ON"),
 .INIT_FILE("E:/FPGA/anxian_contest/project_v57/rtl/spectrum_state_zero.dath")) band_state(
 .dia(update_data),.addra(update_index),.cea(1'b1),.ocea(1'b1),.clka(clk),.wea(update_write),.rsta(1'b0),.bea(1'b1),.doa(update_q),
 .dib(16'd0),.addrb(column),.ceb(1'b1),.oceb(1'b1),.clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b1),.dob(band_q));
wire [9:0] baseline=split_video?10'd628:mode_hd?10'd644:10'd434;
wire in_x=split_video?(x>=704 && x<1216 && x[4:0]<26):mode_hd?(x>=128 && x<1152 && x[5:0]<52):(x>=64 && x<576 && x[4:0]<26);
reg h0,v0,d0,h1,v1,d1;
reg [23:0] rgb0,rgb1,panel1;
reg [9:0] distance0;
reg in_x0,below0,at_or_below0,hd0,area0,area1,grid0,grid1,bar1,peak1;
reg [1:0] colour0,colour1;
wire [5:0] bar_height=hd0?band_q[5:0]:band_q[5:0]>>1;
wire [5:0] peak_height=hd0?band_q[11:6]:band_q[11:6]>>1;
wire [23:0] bar_colour=colour1==0?24'hff7e83:colour1==1?24'hfbbf45:24'h35d8e6;
wire [8:0] pr={1'b0,rgb0[23:16]}+9'd17;
wire [8:0] pg={1'b0,rgb0[15:8]}+9'd29;
wire [8:0] pb={1'b0,rgb0[7:0]}+9'd44;
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=INIT;update_index<=0;update_pending<=0;frame_levels<=0;new_word<=0;end
 else begin
  if(vs_d && !vs)begin frame_levels<=levels;update_pending<=1;end
  case(state)
   INIT:if(update_index==15)begin update_index<=0;state<=IDLE;end else update_index<=update_index+1'b1;
   IDLE:if(update_pending)begin update_index<=0;update_pending<=0;state<=FETCH;end
   FETCH:state<=CALC;
   CALC:begin new_word<={next_hold,next_peak,next_shown};state<=WRITE;end
   WRITE:if(update_index==15)state<=IDLE;else begin update_index<=update_index+1'b1;state<=FETCH;end
   default:state<=INIT;
  endcase
 end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  x<=0;y<=0;de_d<=0;vs_d<=0;
  h0<=0;v0<=0;d0<=0;h1<=0;v1<=0;d1<=0;rgb0<=0;rgb1<=0;panel1<=0;
  distance0<=0;in_x0<=0;below0<=0;at_or_below0<=0;hd0<=0;
  area0<=0;area1<=0;grid0<=0;grid1<=0;bar1<=0;peak1<=0;colour0<=0;colour1<=0;
  ohs<=0;ovs<=0;ode<=0;orgb<=0;
 end else begin
  de_d<=de;vs_d<=vs;
  if(!de)x<=0;else x<=x==(mode_hd?1279:639)?0:x+1'b1;
  if(vs_d && !vs)y<=0;else if(de_d && !de)y<=y==(mode_hd?719:479)?0:y+1'b1;
  h0<=hs;v0<=vs;d0<=de;rgb0<=rgb;
  distance0<=baseline-y;in_x0<=in_x;below0<=y<baseline;at_or_below0<=y<=baseline;hd0<=mode_hd;
  area0<=enable && (split_video?(x>=680 && x<1240 && y>=552 && y<630):mode_hd?(y>=568 && y<646):(y>=396 && y<436));
  grid0<=y[3:0]==0;
  colour0<=y<baseline-(mode_hd?48:24)?0:y<baseline-(mode_hd?28:14)?1:2;
  h1<=h0;v1<=v0;d1<=d0;rgb1<=rgb0;panel1<={pr[8:1],pg[8:1],pb[8:1]};
  bar1<=in_x0 && below0 && distance0<={4'd0,bar_height};
  peak1<=in_x0 && peak_height!=0 && at_or_below0 && distance0=={4'd0,peak_height};
  area1<=area0;grid1<=grid0;colour1<=colour0;
  ohs<=h1;ovs<=v1;ode<=d1;
  orgb<=!d1?24'd0:!area1?rgb1:peak1?24'heef6ff:bar1?bar_colour:grid1?24'h314257:panel1;
 end
end
endmodule
