// Both FIFOs advance on one I2S frame boundary. Page changes affect only voice.
module exhibit_live_mix(
 input clk,rst,sample_tick,duck,
 input [31:0] bgm,voice,input bgm_empty,voice_empty,
 output [31:0] mixed,output empty
);
(* async_reg="true" *) reg [1:0] duck_sync;
reg [8:0] music_gain;
wire [8:0] target=duck_sync[1]?9'd26:9'd256;
always @(posedge clk or posedge rst)begin
 if(rst)begin duck_sync<=0;music_gain<=256;end
 else begin
  duck_sync<={duck_sync[0],duck};
  if(sample_tick)begin
   if(music_gain<target)music_gain<=music_gain+1'b1;
   else if(music_gain>target)music_gain<=music_gain-1'b1;
  end
 end
end
wire signed [15:0] bl=bgm_empty?16'sd0:$signed(bgm[15:0]);
wire signed [15:0] br=bgm_empty?16'sd0:$signed(bgm[31:16]);
wire signed [15:0] vl=voice_empty?16'sd0:$signed(voice[15:0]);
wire signed [15:0] vr=voice_empty?16'sd0:$signed(voice[31:16]);
wire signed [24:0] left_product=bl*$signed({1'b0,music_gain[7:0]});
wire signed [24:0] right_product=br*$signed({1'b0,music_gain[7:0]});
wire signed [15:0] left_bgm=music_gain[8]?bl:left_product[23:8];
wire signed [15:0] right_bgm=music_gain[8]?br:right_product[23:8];
wire signed [16:0] left_sum={left_bgm[15],left_bgm}+{vl[15],vl};
wire signed [16:0] right_sum={right_bgm[15],right_bgm}+{vr[15],vr};
function [15:0] saturate;input signed [16:0] s;begin
 if(s[16]!=s[15])saturate=s[16]?16'h8000:16'h7fff;else saturate=s[15:0];
end endfunction
assign mixed={saturate(right_sum),saturate(left_sum)};
assign empty=bgm_empty && voice_empty;
endmodule
