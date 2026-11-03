// 1024 stereo PCM16 frames in one spare BRAM32K, independent of image SDRAM.
module exhibit_pcm_fifo #(parameter integer ADDR_BITS=10,parameter RAM_KIND="32K")(
 input wr_clk,wr_rst,wr_en,input [31:0] wr_data,
 output [ADDR_BITS:0] wr_used,output wr_full,
 input rd_clk,rd_rst,rd_pop,output [31:0] rd_data,output rd_empty
);
reg [ADDR_BITS:0] wbin,wgray,rbin,rgray;
(* async_reg="true" *) reg [ADDR_BITS:0] rg1,rg2,wg1,wg2;
function [ADDR_BITS:0] ungray;input [ADDR_BITS:0] g;integer k;begin
 ungray[ADDR_BITS]=g[ADDR_BITS];for(k=ADDR_BITS-1;k>=0;k=k-1)ungray[k]=ungray[k+1]^g[k];
end endfunction
assign wr_used=wbin-ungray(rg2);
assign wr_full=wr_used==(1<<ADDR_BITS);
assign rd_empty=rgray==wg2;
wire [ADDR_BITS:0] wn=wbin+1'b1,rn=rbin+1'b1;
always @(posedge wr_clk or posedge wr_rst)begin
 if(wr_rst)begin wbin<=0;wgray<=0;rg1<=0;rg2<=0;end
 else begin
  rg1<=rgray;rg2<=rg1;
  if(wr_en && !wr_full)begin wbin<=wn;wgray<=(wn>>1)^wn;end
 end
end
always @(posedge rd_clk or posedge rd_rst)begin
 if(rd_rst)begin rbin<=0;rgray<=0;wg1<=0;wg2<=0;end
 else begin
  wg1<=wgray;wg2<=wg1;
  if(rd_pop && !rd_empty)begin rbin<=rn;rgray<=(rn>>1)^rn;end
 end
end
// Read address is held for a full audio sample interval before consumption.
EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(ADDR_BITS),.ADDR_WIDTH_B(ADDR_BITS),
 .DATA_DEPTH_A(1<<ADDR_BITS),.DATA_DEPTH_B(1<<ADDR_BITS),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT(RAM_KIND)) pcm_ram(
 .dia(wr_data),.addra(wbin[ADDR_BITS-1:0]),.cea(1'b1),.ocea(1'b1),.clka(wr_clk),
 .wea(wr_en && !wr_full && !wr_rst),.rsta(1'b0),.bea(1'b1),.doa(),
 .dib(32'd0),.addrb(rbin[ADDR_BITS-1:0]),.ceb(1'b1),.oceb(1'b1),.clkb(rd_clk),
 .web(1'b0),.rstb(1'b0),.beb(1'b1),.dob(rd_data));
endmodule

// Retains the previously verified 64-bit-per-channel I2S timing and 48k cadence.
module exhibit_pcm_i2s(
 input clk,rst,input [31:0] pcm,input empty,
 output pop,output reg bclk,lrck,dout
);
reg [5:0] bit_count;
reg [63:0] shift;
reg [15:0] right_sample;
assign pop=bclk && bit_count==63 && lrck && !empty;
always @(posedge clk or posedge rst)begin
 if(rst)begin bclk<=0;lrck<=0;dout<=0;bit_count<=0;shift<=0;right_sample<=0;end
 else begin
  bclk<=~bclk;
  if(bclk)begin
   dout<=shift[63];shift<={shift[62:0],1'b0};
   if(bit_count==63)begin
    bit_count<=0;
    if(!lrck)begin lrck<=1;shift<={right_sample,48'd0};end
    else begin
     lrck<=0;right_sample<=empty?16'd0:pcm[31:16];
     shift<=empty?64'd0:{pcm[15:0],48'd0};
    end
   end else bit_count<=bit_count+1'b1;
  end
 end
end
endmodule

// Source PCM-rate conversion by repeat/drop. Pitch follows playback speed.
// The HDMI/I2S output clock remains48kHz; each FIFO pointer still moves by1.
module exhibit_audio_speed_v48(
 input clk,rst,enable,input [1:0] speed,input consume,empty,input [31:0] pcm,
 output [31:0] out_pcm,output pop
);
reg half_phase;reg [1:0] previous_speed;reg [1:0] extra_delay;
wire [2:0] advance={1'b0,speed}+3'd1+half_phase;
wire primary=consume && (!enable || advance>=2);
assign out_pcm=pcm;
assign pop=!rst && !empty && (primary || extra_delay==1);
always @(posedge clk or posedge rst)begin
 if(rst)begin half_phase<=0;previous_speed<=1;extra_delay<=0;end
 else begin
  previous_speed<=speed;
  if(extra_delay!=0)extra_delay<=extra_delay-1'b1;
  if(!enable || speed!=previous_speed)half_phase<=0;
  if(consume && !empty)begin
   if(enable)begin
    half_phase<=advance[0];
    if(advance>=4)extra_delay<=2;
   end else half_phase<=0;
  end
 end
end
endmodule
