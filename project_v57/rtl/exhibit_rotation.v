// V32: a four-line double-buffered palette sprite, preloaded in H01's SDRAM.
// No runtime SD requests, PCM resets, DSPs, or full-frame animation buffers.
module exhibit_rotation #(parameter integer CLOCK_HZ=50_000_000)(
 input mem_clk,mem_rst,video_clk,video_rst,enable,firstpage,mode_hd,fit,
 input hs,vs,de,input [23:0] rgb,
 output reg ohs,ovs,ode,output reg [23:0] orgb,
 output want,release_bus,input grant,mem_busy,refresh,mem_valid,
 input [31:0] mem_data,output rd_en,output [20:0] rd_addr,
 output reg [15:0] missed_groups
);
localparam IDLE=0,ADDRESS=1,GRANT=2,ISSUE=3,DRAIN=4,COMPLETE=5,STORE=6;
reg [2:0] state;
reg [22:0] phase_clock;
reg [7:0] phase_frame;
reg [20:0] frame_base,address;
reg [4:0] job_group;
reg job_epoch,job_toggle;
reg [6:0] received;
reg [4:0] issued;
reg [31:0] aligned_data;
reg [255:0] packet;
reg [3:0] store_count;
reg [7:0] ram_cursor;
reg [5:0] bank0_tag,bank1_tag;
reg [2:0] request_sync;
reg acknowledge;
reg request_toggle,request_epoch;
reg [4:0] request_group;
wire [20:0] phase_offset=({13'd0,phase_frame}<<11)+({13'd0,phase_frame}<<7)+({13'd0,phase_frame}<<6);
wire [20:0] group_offset=({16'd0,job_group}<<6)+({16'd0,job_group}<<4);
assign want=state==GRANT;
assign release_bus=state==IDLE;
assign rd_en=state==ISSUE && (issued!=0 || (!mem_busy && !refresh));
assign rd_addr=address;
always @(posedge mem_clk or posedge mem_rst)begin
 if(mem_rst)begin
  state<=IDLE;phase_clock<=0;phase_frame<=0;frame_base<=115200;address<=0;
  job_group<=0;job_epoch<=0;job_toggle<=0;received<=0;issued<=0;aligned_data<=0;
  packet<=0;store_count<=0;ram_cursor<=0;
  bank0_tag<=31;bank1_tag<=31;request_sync<=0;acknowledge<=0;
 end else begin
  request_sync<={request_sync[1:0],request_toggle};aligned_data<=mem_data;
  if(phase_clock==CLOCK_HZ/12-1)begin phase_clock<=0;if(phase_frame==143)phase_frame<=0;else phase_frame<=phase_frame+1'b1;end
  else phase_clock<=phase_clock+1'b1;
  case(state)
   IDLE:if(enable && request_sync[2]!=acknowledge)begin
    job_group<=request_group;job_epoch<=request_epoch;job_toggle<=request_sync[2];received<=0;issued<=0;ram_cursor<=0;
    if(request_group==0)frame_base<=21'd115200+phase_offset;
    state<=ADDRESS;
   end
   ADDRESS:begin address<=frame_base+group_offset;state<=GRANT;end
   GRANT:if(grant && !mem_busy && !refresh)begin issued<=0;state<=ISSUE;end
   ISSUE:if(rd_en)begin address<=address+1'b1;issued<=issued+1'b1;if(issued==7)state<=DRAIN;end
   DRAIN:if(!mem_busy && !refresh && !mem_valid && received!=0 && received[2:0]==0)begin store_count<=0;state<=STORE;end
   STORE:begin
    packet<={16'd0,packet[255:16]};ram_cursor<=ram_cursor+1'b1;store_count<=store_count+1'b1;
    if(store_count==15)begin
     if(received==80)state<=COMPLETE;else begin issued<=0;state<=GRANT;end
    end
   end
   COMPLETE:begin
    if(job_group[0])bank1_tag<={job_epoch,job_group};else bank0_tag<={job_epoch,job_group};
    acknowledge<=job_toggle;state<=IDLE;
   end
  endcase
  if(mem_valid && grant)begin
   received<=received+1'b1;packet<={aligned_data,packet[255:32]};
  end
  // Ten eight-word bursts fill four rows; serialize to a single 16-bit 9K RAM.
 end
end

reg [10:0] x;
reg [9:0] y;
reg de_d,vs_d,epoch;
reg [4:0] last_group;
reg [1:0] ack_sync;
reg [5:0] t00,t01,t10,t11;
wire [10:0] origin_x=mode_hd?11'd640:11'd320;
wire [9:0] origin_y=mode_hd?(fit?10'd144:10'd252):(fit?10'd132:10'd186);
wire [10:0] dx=x-origin_x;
wire [9:0] dy=y-origin_y;
wire [7:0] sx=mode_hd && fit?dx[9:2]:(mode_hd || fit?dx[8:1]:dx[7:0]);
wire [6:0] sy=mode_hd && fit?dy[8:2]:(mode_hd || fit?dy[7:1]:dy[6:0]);
wire [10:0] extent_x=mode_hd && fit?11'd640:(mode_hd || fit?11'd320:11'd160);
wire [9:0] extent_y=mode_hd && fit?10'd448:(mode_hd || fit?10'd224:10'd112);
wire in_sprite=de && firstpage && x>=origin_x && dx<extent_x && y>=origin_y && dy<extent_y;
wire [4:0] group=sy[6:2];
wire tag_match=(group[0]?t11:t01)=={epoch,group};
wire [7:0] row_word=({6'd0,sy[1:0]}<<5)+({6'd0,sy[1:0]}<<3)+{2'd0,sx[7:2]};
wire [8:0] video_address={sy[2],row_word};
wire [15:0] line_word;
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
 .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) sprite_lines(
 .dia(packet[15:0]),.addra({job_group[0],ram_cursor}),.cea(1'b1),.ocea(1'b1),.clka(mem_clk),
 .wea(state==STORE),.rsta(1'b0),.bea(1'b1),.doa(),
 .dib(16'd0),.addrb(video_address),.ceb(1'b1),.oceb(1'b1),.clkb(video_clk),
 .web(1'b0),.rstb(1'b0),.beb(1'b1),.dob(line_word));
function [23:0] palette;input [3:0] i;begin case(i)
 0:palette=24'h000000;1:palette=24'h090c10;2:palette=24'h151b22;3:palette=24'h222a33;
 4:palette=24'h323d48;5:palette=24'h465360;6:palette=24'h5f6e7b;7:palette=24'h7c8b96;
 8:palette=24'ha0adb5;9:palette=24'hc4cdd2;10:palette=24'he8ecee;11:palette=24'h486c82;
 12:palette=24'h77b0c8;13:palette=24'h3e827c;14:palette=24'ha9956a;15:palette=24'hbed5df;
endcase end endfunction
reg [2:0] sync0,sync1;
reg [23:0] bg0,bg1,palette1;
reg show0,show1;
reg [1:0] nibble0;
always @(posedge video_clk or posedge video_rst)begin
 if(video_rst)begin
  x<=0;y<=0;de_d<=0;vs_d<=0;epoch<=0;last_group<=31;
  ack_sync<=0;request_toggle<=0;request_epoch<=0;request_group<=0;
  t00<=31;t01<=31;t10<=31;t11<=31;missed_groups<=0;
  sync0<=0;sync1<=0;bg0<=0;bg1<=0;palette1<=0;show0<=0;show1<=0;nibble0<=0;
  ohs<=0;ovs<=0;ode<=0;orgb<=0;
 end else begin
  ack_sync<={ack_sync[0],acknowledge};t00<=bank0_tag;t01<=t00;t10<=bank1_tag;t11<=t10;
  de_d<=de;vs_d<=vs;
  if(!de)x<=0;else x<=x+1'b1;
  if(vs_d && !vs)begin
   y<=0;epoch<=~epoch;last_group<=31;
   if(firstpage && request_toggle==ack_sync[1])begin request_group<=0;request_epoch<=~epoch;request_toggle<=~request_toggle;end
  end else if(de_d && !de)y<=y+1'b1;
  if(in_sprite && x==origin_x && group!=last_group)begin
   last_group<=group;
   if(!tag_match && missed_groups!=65535)missed_groups<=missed_groups+1'b1;
   if(group<27 && request_toggle==ack_sync[1])begin request_group<=group+1'b1;request_epoch<=epoch;request_toggle<=~request_toggle;end
  end
  sync0<={hs,vs,de};sync1<=sync0;{ohs,ovs,ode}<=sync1;
  bg0<=rgb;bg1<=bg0;nibble0<=sx[1:0];show0<=in_sprite && tag_match;show1<=show0;
  palette1<=palette((line_word>>{nibble0,2'b00}) & 4'hf);
  orgb<=show1?palette1:bg1;
 end
end
endmodule
