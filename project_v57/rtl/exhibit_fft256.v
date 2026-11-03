// Sequential 256-point radix-2 DIT FFT. Real signed Q15 input, bit-reversed
// capture; each stage divides by two. One synchronous simple-dual-port RAM.
// Input is collected in contiguous 256-sample blocks; samples during compute
// are intentionally skipped between blocks (visualizer, not an audio sink).
module exhibit_fft256(input clk,rst,enable,sample_valid,input signed [15:0] sample,
 output reg [95:0] levels,output reg spectrum_valid);
localparam CAP=0,RA=1,WA=2,LA=3,RB=4,WB=5,LB=6,MUL=7,WRITE_A=8,WRITE_B=9,MR=10,MW=11,ML=12,MA=13,MH=14,MIX=15;
reg [3:0] state;
reg [7:0] capture_count,offset,base,bin;
reg [3:0] stage;
reg [8:0] span;
wire [7:0] half_span=span>>1;
wire [7:0] addr_a=base+offset;
wire [7:0] addr_b=base+offset+half_span;
wire [6:0] twiddle_index=offset<<(7-stage);
(* rom_style="bram" *) reg [31:0] twiddles[0:127];
initial $readmemh("E:/FPGA/anxian_contest/project_v57/rtl/fft_twiddle.hex",twiddles);
reg [31:0] twiddle_q;
wire twiddle_read=enable && state==LB;
always @(posedge clk)if(twiddle_read)twiddle_q<=twiddles[twiddle_index];
wire signed [15:0] wr=twiddle_q[31:16];
wire signed [15:0] wi=twiddle_q[15:0];
reg [31:0] ram[0:255];
reg [7:0] raddr,waddr;
reg [31:0] wdata,q;
reg we;
reg signed [15:0] ar,ai,br,bi;
reg signed [31:0] prr,pii,pri,pir;
// Separate complex-product addition from the butterfly and RAM write.
// After Q15 scaling, signed 18 bits retain the full 33-bit sum's range.
reg signed [17:0] tr,ti;
reg [95:0] work_levels;
reg [15:0] level_select;integer level_index;
reg [15:0] magnitude_r,magnitude_i;reg [16:0] magnitude_q;
function [7:0] reverse8;input [7:0] a;integer k;begin for(k=0;k<8;k=k+1)reverse8[k]=a[7-k];end endfunction
function [15:0] sat16;input signed [33:0] a;begin if(a>32767)sat16=16'h7fff;else if(a< -32768)sat16=16'h8000;else sat16=a[15:0];end endfunction
function [5:0] height;input [16:0] magnitude;begin
 if(magnitude>4032)height=63;else height=magnitude>>6;
end endfunction
always @* begin
 we=0;waddr=0;wdata=0;
 if(enable && state==CAP && sample_valid)begin we=1;waddr=reverse8(capture_count);wdata={sample,16'd0};end
 if(enable && state==WRITE_A)begin we=1;waddr=addr_a;wdata={sat16(($signed(ar)+tr)>>>1),sat16(($signed(ai)+ti)>>>1)};end
 if(enable && state==WRITE_B)begin we=1;waddr=addr_b;wdata={sat16(($signed(ar)-tr)>>>1),sat16(($signed(ai)-ti)>>>1)};end
end
wire data_read=enable && (state==WA || state==WB || state==MW);
always @(posedge clk)begin
 if(we)ram[waddr]<=wdata;
 if(data_read)q<=ram[raddr];
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  magnitude_r<=0;magnitude_i<=0;magnitude_q<=0;state<=CAP;capture_count<=0;offset<=0;base<=0;bin<=1;stage<=0;span<=2;raddr<=0;
  ar<=0;ai<=0;br<=0;bi<=0;prr<=0;pii<=0;pri<=0;pir<=0;tr<=0;ti<=0;work_levels<=0;levels<=0;spectrum_valid<=0;level_select<=0;
 end else if(!enable)begin
  // Hidden analysis never consumes the audio FIFO. Discard incomplete blocks
  // and restart with256 fresh samples; leave published levels held meanwhile.
  state<=CAP;capture_count<=0;spectrum_valid<=0;
 end else begin
  spectrum_valid<=0;
  case(state)
   CAP:if(sample_valid)begin
    if(capture_count==255)begin capture_count<=0;offset<=0;base<=0;stage<=0;span<=2;state<=RA;end
    else capture_count<=capture_count+1;
   end
   RA:begin raddr<=addr_a;state<=WA;end
   WA:state<=LA;
   LA:begin ar<=q[31:16];ai<=q[15:0];state<=RB;end
   RB:begin raddr<=addr_b;state<=WB;end
   WB:state<=LB;
   LB:begin br<=q[31:16];bi<=q[15:0];state<=MUL;end
   MUL:begin prr<=br*wr;pii<=bi*wi;pri<=br*wi;pir<=bi*wr;state<=MIX;end
   MIX:begin
    tr<=($signed({prr[31],prr})-$signed({pii[31],pii}))>>>15;
    ti<=($signed({pri[31],pri})+$signed({pir[31],pir}))>>>15;
    state<=WRITE_A;
   end
   WRITE_A:state<=WRITE_B;
   WRITE_B:begin
    if(offset==half_span-1)begin
     offset<=0;
     if({1'b0,base}+span>=256)begin
      base<=0;
      if(stage==7)begin bin<=1;state<=MR;end
      else begin stage<=stage+1;span<=span<<1;state<=RA;end
     end else begin base<=base+span;state<=RA;end
    end else begin offset<=offset+1;state<=RA;end
   end
   MR:begin raddr<=bin;level_select<=16'b1<<(bin[3:0]-1'b1);state<=MW;end
   MW:state<=MA;
   MA:begin magnitude_r<=q[31]?(~q[31:16]+16'd1):q[31:16];magnitude_i<=q[15]?(~q[15:0]+16'd1):q[15:0];state<=MH;end
   MH:begin magnitude_q<={1'b0,magnitude_r}+{1'b0,magnitude_i};state<=ML;end
   ML:begin
    for(level_index=0;level_index<16;level_index=level_index+1)
     if(level_select[level_index])work_levels[level_index*6+:6]<=height(magnitude_q);
    if(bin==16)begin levels<={height(magnitude_q),work_levels[89:0]};spectrum_valid<=1;state<=CAP;end
    else begin bin<=bin+1;state<=MR;end
   end
   default:state<=CAP;
  endcase
 end
end
endmodule
