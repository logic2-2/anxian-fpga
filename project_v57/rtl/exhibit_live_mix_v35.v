// Opening is exclusive: Jazz is silent and its read pointer is held.
// Afterwards reuse the original two multipliers for a gentle Jazz onset.
module exhibit_live_mix_v35 #(parameter integer OPEN_FADE_SAMPLES=75)(
 input bgm_mute,output reg bgm_muted,
 input clk,rst,sample_tick,duck,exclusive_opening,opening_play,voice_is_opening,
 input [31:0] bgm,voice,input bgm_empty,voice_empty,
 output [31:0] mixed,output empty,bgm_pop,voice_pop
);
(* async_reg="true" *) reg [1:0] duck_sync,exclusive_sync,play_sync,opening_voice_sync;
(* async_reg="true" *)reg [1:0] bgm_mute_sync;reg bgm_mute_d;
reg [8:0] music_gain;
reg had_opening,ramping;
localparam integer FADE_BITS=OPEN_FADE_SAMPLES>1?$clog2(OPEN_FADE_SAMPLES):1;
reg [FADE_BITS-1:0] fade_count;
wire [8:0] target=bgm_mute_sync[1]?9'd0:duck_sync[1]?9'd26:9'd256;
wire opening_voice_allowed=exclusive_sync[1] && play_sync[1] && opening_voice_sync[1];
wire normal_voice_allowed=!exclusive_sync[1] && !opening_voice_sync[1];
assign empty=exclusive_sync[1]?(!opening_voice_allowed || voice_empty):
 (bgm_empty && (voice_empty || !normal_voice_allowed));
assign bgm_pop=sample_tick && !exclusive_sync[1] && !bgm_empty && !(bgm_mute_sync[1] && music_gain==0);
assign voice_pop=sample_tick && !voice_empty && (opening_voice_allowed || normal_voice_allowed);
always @(posedge clk or posedge rst)begin
 if(rst)begin
  duck_sync<=0;exclusive_sync<=0;play_sync<=0;opening_voice_sync<=0;
  bgm_mute_sync<=0;bgm_mute_d<=0;bgm_muted<=0;
  music_gain<=256;had_opening<=0;ramping<=0;fade_count<=0;
 end else begin
  bgm_mute_sync<={bgm_mute_sync[0],bgm_mute};bgm_mute_d<=bgm_mute_sync[1];
  bgm_muted<=music_gain==0 && (bgm_mute_sync[1] || exclusive_sync[1]);
  duck_sync<={duck_sync[0],duck};exclusive_sync<={exclusive_sync[0],exclusive_opening};
  play_sync<={play_sync[0],opening_play};opening_voice_sync<={opening_voice_sync[0],voice_is_opening};
  if(exclusive_sync[1])begin music_gain<=0;had_opening<=1;ramping<=1;fade_count<=0;end
  else if(bgm_mute_d!=bgm_mute_sync[1])begin had_opening<=1;ramping<=1;fade_count<=0;end
  else if(sample_tick)begin
   if(had_opening && ramping)begin
    if(music_gain==target)begin ramping<=0;fade_count<=0;end
    else if(fade_count==OPEN_FADE_SAMPLES-1)begin
     fade_count<=0;if(music_gain<target)music_gain<=music_gain+1'b1;else music_gain<=music_gain-1'b1;
    end else fade_count<=fade_count+1'b1;
   end else begin
    if(music_gain<target)music_gain<=music_gain+1'b1;
    else if(music_gain>target)music_gain<=music_gain-1'b1;
   end
  end
 end
end
wire signed [15:0] bl=(exclusive_sync[1]||bgm_empty)?16'sd0:$signed(bgm[15:0]);
wire signed [15:0] br=(exclusive_sync[1]||bgm_empty)?16'sd0:$signed(bgm[31:16]);
wire signed [15:0] vl=(voice_empty||!(opening_voice_allowed||normal_voice_allowed))?16'sd0:$signed(voice[15:0]);
wire signed [15:0] vr=(voice_empty||!(opening_voice_allowed||normal_voice_allowed))?16'sd0:$signed(voice[31:16]);
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
endmodule
