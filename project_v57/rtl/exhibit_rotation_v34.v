// Shared one9K line cache: V33 rotation or a boot-only RLE brand clip.
module exhibit_rotation_v34 #(parameter integer CLOCK_HZ=50_000_000,ENABLE_BRAND_INTRO=0)(
 input mem_clk,mem_rst,video_clk,video_rst,enable,firstpage,mode_hd,fit,
 input hs,vs,de,input [23:0] rgb,
 output reg ohs,ovs,ode,output reg [23:0] orgb,
 output want,release_bus,input grant,mem_busy,refresh,mem_valid,
 input [31:0] mem_data,output rd_en,output [20:0] rd_addr,
 output reg [15:0] missed_groups,
 input intro_request,intro_ready,input [5:0] intro_frame_gray,
 output reg intro_visible,intro_presented,decoder_fault
);
localparam IDLE=0,JOB_ADDRESS=1,GRANT=2,ISSUE=3,DRAIN=4,COMPLETE=5,RAW_STORE=6,
 INTRO_ADDRESS=7,META_RESOLVE=8,SKIP_BYTES=9,TOKEN=10,EXPAND=11;
reg [3:0] state;
reg [22:0] phase_clock;
reg [7:0] phase_frame;
reg [20:0] frame_base,address;
reg [6:0] job_group;
reg job_epoch,job_toggle,job_intro,job_bad,reading_descriptor;
reg [5:0] saved_intro_frame;
reg [6:0] received;
reg [3:0] issued,store_count;
reg [31:0] aligned_data,descriptor;
reg [255:0] packet;
reg [7:0] ram_cursor;
reg [8:0] bank0_tag,bank1_tag;
reg [2:0] request_sync;
reg acknowledge;
reg request_toggle,request_epoch,request_intro;
reg [6:0] request_group;
reg [5:0] request_frame;
reg [16:0] logical_word;
reg [2:0] meta_select;
reg [5:0] byte_left,skip_left;
reg [4:0] run_left;
reg [3:0] run_colour;
reg [9:0] decoded;
reg [15:0] rle_pack;
wire [20:0] phase_offset=({13'd0,phase_frame}<<11)+({13'd0,phase_frame}<<7)+({13'd0,phase_frame}<<6);
wire [20:0] group_offset=({14'd0,job_group}<<6)+({14'd0,job_group}<<4);
wire [16:0] meta_word=17'd32+({11'd0,saved_intro_frame}<<6)+({11'd0,saved_intro_frame}<<4)+
 ({11'd0,saved_intro_frame}<<3)+({11'd0,saved_intro_frame}<<1)+{10'd0,job_group};
function [20:0] map_intro;input [16:0] n;begin
 if(n<57600)map_intro=21'd1843200+{4'd0,n};
 else if(n<80640)map_intro=21'd437760+{4'd0,n}-21'd57600;
 else map_intro=21'd2073600+{4'd0,n}-21'd80640;
end endfunction
assign want=state==GRANT;
assign release_bus=state==IDLE;
assign rd_en=state==ISSUE && (issued!=0 || (!mem_busy && !refresh));
assign rd_addr=address;
always @(posedge mem_clk or posedge mem_rst)begin
 if(mem_rst)begin
  state<=IDLE;phase_clock<=0;phase_frame<=0;frame_base<=115200;address<=0;
  job_group<=0;job_epoch<=0;job_toggle<=0;job_intro<=0;job_bad<=0;reading_descriptor<=0;saved_intro_frame<=0;
  received<=0;issued<=0;aligned_data<=0;packet<=0;store_count<=0;ram_cursor<=0;
  bank0_tag<=9'h1ff;bank1_tag<=9'h1ff;request_sync<=0;acknowledge<=0;
  logical_word<=0;meta_select<=0;descriptor<=0;byte_left<=0;skip_left<=0;
  run_left<=0;run_colour<=0;decoded<=0;rle_pack<=0;decoder_fault<=0;
 end else begin
  request_sync<={request_sync[1:0],request_toggle};
  // Prime before the first SDRAM response and retain the existing one-cycle
  // capture pipeline throughout ownership. Other clients do not toggle it.
  if(grant || state==GRANT)aligned_data<=mem_data;
  if(phase_clock==CLOCK_HZ/12-1)begin phase_clock<=0;if(phase_frame==143)phase_frame<=0;else phase_frame<=phase_frame+1'b1;end
  else phase_clock<=phase_clock+1'b1;
  case(state)
   IDLE:if(enable && request_sync[2]!=acknowledge)begin
    job_group<=request_group;job_epoch<=request_epoch;job_toggle<=request_sync[2];job_intro<=ENABLE_BRAND_INTRO && request_intro;
    job_bad<=0;received<=0;issued<=0;ram_cursor<=0;decoded<=0;rle_pack<=0;
    if(request_group==0)begin frame_base<=21'd115200+phase_offset;saved_intro_frame<=request_frame;end
    state<=JOB_ADDRESS;
   end
   JOB_ADDRESS:if(job_intro)begin
    if(saved_intro_frame>=40 || job_group>=90)begin job_bad<=1;state<=COMPLETE;end
    else begin meta_select<=meta_word[2:0];logical_word<={meta_word[16:3],3'd0};reading_descriptor<=1;state<=INTRO_ADDRESS;end
   end else begin address<=frame_base+group_offset;state<=GRANT;end
   INTRO_ADDRESS:begin address<=map_intro(logical_word);state<=GRANT;end
   GRANT:if(grant && !mem_busy && !refresh)begin issued<=0;state<=ISSUE;end
   ISSUE:if(rd_en)begin
    address<=address+1'b1;if(job_intro)logical_word<=logical_word+1'b1;
    issued<=issued+1'b1;if(issued==7)state<=DRAIN;
   end
   DRAIN:if(!mem_busy && !refresh && !mem_valid && received!=0 && received[2:0]==0)begin
    if(job_intro)begin
     received<=0;
     if(reading_descriptor)state<=META_RESOLVE;
     else begin byte_left<=32;state<=SKIP_BYTES;end
    end else begin store_count<=0;state<=RAW_STORE;end
   end
   RAW_STORE:begin
    packet<={16'd0,packet[255:16]};ram_cursor<=ram_cursor+1'b1;store_count<=store_count+1'b1;
    if(store_count==15)begin if(received==80)state<=COMPLETE;else begin issued<=0;state<=GRANT;end end
   end
   META_RESOLVE:begin
    if(descriptor<14528 || descriptor>=401147)begin job_bad<=1;state<=COMPLETE;end
    else begin logical_word<={descriptor[18:5],3'd0};skip_left<={1'b0,descriptor[4:0]};reading_descriptor<=0;state<=INTRO_ADDRESS;end
   end
   SKIP_BYTES:if(skip_left!=0)begin
    packet<={8'd0,packet[255:8]};skip_left<=skip_left-1'b1;byte_left<=byte_left-1'b1;
   end else state<=TOKEN;
   TOKEN:if(byte_left==0)begin
    if(logical_word>104184)begin job_bad<=1;state<=COMPLETE;end
    else state<=INTRO_ADDRESS;
   end else begin
    run_left<={1'b0,packet[7:4]}+1'b1;run_colour<=packet[3:0];packet<={8'd0,packet[255:8]};byte_left<=byte_left-1'b1;state<=EXPAND;
   end
   EXPAND:begin
    rle_pack<={run_colour,rle_pack[15:4]};decoded<=decoded+1'b1;run_left<=run_left-1'b1;
    if(decoded[1:0]==3)ram_cursor<=ram_cursor+1'b1;
    if(decoded==639)begin if(run_left!=1)job_bad<=1;state<=COMPLETE;end
    else if(run_left==1)state<=TOKEN;
   end
   COMPLETE:begin
    if(!job_bad)begin
     if(job_group[0])bank1_tag<={job_intro,job_epoch,job_group};else bank0_tag<={job_intro,job_epoch,job_group};
    end else if(job_intro)decoder_fault<=1;
    acknowledge<=job_toggle;state<=IDLE;
   end
   default:begin decoder_fault<=1;state<=IDLE;end
  endcase
  if(mem_valid && grant)begin
   received<=received+1'b1;packet<={aligned_data,packet[255:32]};
   if(job_intro && reading_descriptor && received=={4'd0,meta_select})descriptor<=aligned_data;
  end
 end
end

reg [10:0] x;reg [9:0] y;
reg de_d,vs_d,epoch;
reg [6:0] last_group;
reg [1:0] ack_sync,intro_sync;
(* async_reg="true" *) reg [5:0] gray0,gray1;
reg [8:0] t00,t01,t10,t11;
function [5:0] ungray;input [5:0] g;integer k;begin ungray[5]=g[5];for(k=4;k>=0;k=k-1)ungray[k]=ungray[k+1]^g[k];end endfunction
wire desired_intro=ENABLE_BRAND_INTRO && intro_sync[1];
wire [10:0] origin_x=mode_hd?11'd640:11'd320;
wire [9:0] origin_y=mode_hd?(fit?10'd144:10'd252):(fit?10'd132:10'd186);
wire [10:0] dx=x-origin_x;wire [9:0] dy=y-origin_y;
wire [9:0] intro_y=y-(mode_hd?10'd0:10'd60);
wire [8:0] sx=intro_visible?(mode_hd?x[10:2]:x[9:1]):
 (mode_hd && fit?{1'b0,dx[9:2]}:(mode_hd || fit?{1'b0,dx[8:1]}:{1'b0,dx[7:0]}));
wire [7:0] sy=intro_visible?(mode_hd?y[9:2]:intro_y[8:1]):
 (mode_hd && fit?{1'b0,dy[8:2]}:(mode_hd || fit?{1'b0,dy[7:1]}:{1'b0,dy[6:0]}));
wire [10:0] extent_x=mode_hd && fit?11'd640:(mode_hd || fit?11'd320:11'd160);
wire [9:0] extent_y=mode_hd && fit?10'd448:(mode_hd || fit?10'd224:10'd112);
wire in_sprite=de && firstpage && (intro_visible?(mode_hd || (y>=60 && y<420)):
 (x>=origin_x && dx<extent_x && y>=origin_y && dy<extent_y));
wire [6:0] group=intro_visible?sy[7:1]:{2'd0,sy[6:2]};
wire tag_match=(group[0]?t11:t01)=={intro_visible,epoch,group};
wire [7:0] row_word=intro_visible?((sy[0]?8'd80:8'd0)+{1'b0,sx[8:2]}):
 (({6'd0,sy[1:0]}<<5)+({6'd0,sy[1:0]}<<3)+{2'd0,sx[7:2]});
wire [8:0] video_address={group[0],row_word};
wire [15:0] line_word;
wire ram_write=state==RAW_STORE || (state==EXPAND && decoded[1:0]==3);
wire [15:0] ram_data=state==RAW_STORE?packet[15:0]:{run_colour,rle_pack[15:4]};
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
 .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) sprite_lines(
 .dia(ram_data),.addra({job_group[0],ram_cursor}),.cea(ram_write),.ocea(1'b1),.clka(mem_clk),.wea(ram_write),.rsta(1'b0),.bea(1'b1),.doa(),
 .dib(16'd0),.addrb(video_address),.ceb(in_sprite && tag_match),.oceb(1'b1),.clkb(video_clk),.web(1'b0),.rstb(1'b0),.beb(1'b1),.dob(line_word));
function [23:0] palette;input [3:0] i;begin case(i)
 0:palette=24'h000000;1:palette=24'h090c10;2:palette=24'h151b22;3:palette=24'h222a33;
 4:palette=24'h323d48;5:palette=24'h465360;6:palette=24'h5f6e7b;7:palette=24'h7c8b96;
 8:palette=24'ha0adb5;9:palette=24'hc4cdd2;10:palette=24'he8ecee;11:palette=24'h486c82;
 12:palette=24'h77b0c8;13:palette=24'h3e827c;14:palette=24'ha9956a;15:palette=24'hbed5df;
endcase end endfunction
function [23:0] intro_palette;input [3:0] i;begin case(i)
 0:intro_palette=24'h080f1d;1:intro_palette=24'h0b192b;2:intro_palette=24'h10243c;3:intro_palette=24'h193450;
 4:intro_palette=24'h244260;5:intro_palette=24'h315479;6:intro_palette=24'h436b95;7:intro_palette=24'h628cb6;
 8:intro_palette=24'h88aacb;9:intro_palette=24'hb2c9df;10:intro_palette=24'hd6e2ef;11:intro_palette=24'hf3f7fc;
 12:intro_palette=24'hef3342;13:intro_palette=24'hc82a38;14:intro_palette=24'h951c2c;15:intro_palette=24'h541926;
endcase end endfunction
reg [2:0] sync0,sync1;
reg [23:0] bg0,bg1,palette1;
reg show0,show1,intro0;
reg [1:0] nibble0;
always @(posedge video_clk or posedge video_rst)begin
 if(video_rst)begin
  x<=0;y<=0;de_d<=0;vs_d<=0;epoch<=0;last_group<=127;ack_sync<=0;
  intro_sync<=0;gray0<=0;gray1<=0;intro_visible<=0;intro_presented<=0;
  request_toggle<=0;request_epoch<=0;request_group<=0;request_intro<=0;request_frame<=0;
  t00<=9'h1ff;t01<=9'h1ff;t10<=9'h1ff;t11<=9'h1ff;missed_groups<=0;
  sync0<=0;sync1<=0;bg0<=0;bg1<=0;palette1<=0;show0<=0;show1<=0;nibble0<=0;intro0<=0;
  ohs<=0;ovs<=0;ode<=0;orgb<=0;
 end else begin
  ack_sync<={ack_sync[0],acknowledge};t00<=bank0_tag;t01<=t00;t10<=bank1_tag;t11<=t10;
  intro_sync<={intro_sync[0],intro_request};gray0<=intro_frame_gray;gray1<=gray0;
  de_d<=de;vs_d<=vs;
  if(!de)x<=0;else x<=x+1'b1;
  if(vs_d && !vs)begin
   y<=0;epoch<=~epoch;last_group<=127;intro_visible<=desired_intro && firstpage;
   if(firstpage && request_toggle==ack_sync[1])begin
    request_group<=0;request_epoch<=~epoch;request_toggle<=~request_toggle;request_intro<=desired_intro;request_frame<=ungray(gray1);
   end
  end else if(de_d && !de)y<=y+1'b1;
  if(intro_visible && in_sprite && x==0 && sy==0 && tag_match && intro_ready)intro_presented<=1;
  if(in_sprite && x==(intro_visible?11'd0:origin_x) && group!=last_group)begin
   last_group<=group;
   if(!tag_match && missed_groups!=65535)missed_groups<=missed_groups+1'b1;
   if(group<(intro_visible?7'd89:7'd27) && request_toggle==ack_sync[1])begin
    request_group<=group+1'b1;request_epoch<=epoch;request_toggle<=~request_toggle;request_intro<=intro_visible;
   end
  end
  sync0<={hs,vs,de};sync1<=sync0;{ohs,ovs,ode}<=sync1;
  bg0<=intro_visible?24'd0:rgb;bg1<=bg0;
  if(in_sprite)begin nibble0<=sx[1:0];intro0<=intro_visible;end
  show0<=in_sprite && tag_match;show1<=show0;
  if(show0)palette1<=intro0?intro_palette((line_word>>{nibble0,2'b00})&4'hf):palette((line_word>>{nibble0,2'b00})&4'hf);
  orgb<=show1?palette1:bg1;
 end
end
endmodule
