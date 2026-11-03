module exhibit_video_gain(
 input clk,rst,hs,vs,de,input [23:0] rgb,input [8:0] gain,
 output reg ohs,ovs,ode,output reg [23:0] orgb
);
reg [16:0] r,g,b;reg h1,v1,d1;
always @(posedge clk or posedge rst) begin
 if(rst)begin r<=0;g<=0;b<=0;h1<=0;v1<=0;d1<=0;ohs<=0;ovs<=0;ode<=0;orgb<=0;end
 else begin
  r<=rgb[23:16]*gain;g<=rgb[15:8]*gain;b<=rgb[7:0]*gain;
  h1<=hs;v1<=vs;d1<=de;ohs<=h1;ovs<=v1;ode<=d1;
  orgb<=d1?{r[15:8],g[15:8],b[15:8]}:24'd0;
 end
end
endmodule

// PCM and transition envelope already share the video clock domain.
// Sample-by-sample gain slew avoids discontinuities at the frame steps.
module exhibit_audio_gain(
 input clk,rst,sample_valid,input signed [23:0] left_in,right_in,
 input [8:0] target_gain,
 output reg sample_out_valid,output reg signed [23:0] left_out,right_out,output [8:0] applied_gain
);
reg [8:0] gain;
assign applied_gain=gain;
reg signed [33:0] pl,pr;
reg valid_d;
always @(posedge clk or posedge rst) begin
 if(rst)begin gain<=0;pl<=0;pr<=0;valid_d<=0;sample_out_valid<=0;left_out<=0;right_out<=0;end
 else begin
  valid_d<=sample_valid;sample_out_valid<=valid_d;
  if(sample_valid)begin
   if(gain<target_gain)gain<=gain+1;else if(gain>target_gain)gain<=gain-1;
   pl<=left_in*$signed({1'b0,gain});pr<=right_in*$signed({1'b0,gain});
  end
  if(valid_d)begin left_out<=pl>>>8;right_out<=pr>>>8;end
 end
end
endmodule

// Two first-order shelving bands, shared arithmetic across stereo channels.
// At48kHz: low pole alpha1/32 (~240Hz), high pole alpha1/4 (~2.2kHz).
// Inputs retain the I2S receiver's24-bit units (PCM16 occupies bits23:8).
// Nominal shelf gains: -24,-18,-12,-6,0,+3,+6dB.
// Cut-dependent poles keep attenuation useful through the bass/treble bands;
// midpoint0dB remains a bit-exact bypass, with saturating boosted output.
module exhibit_audio_eq_v48(
 input clk,rst,sample_valid,input signed [23:0] left_in,right_in,
 input [2:0] bass,treble,input [1:0] effect,
 output reg sample_out_valid,output reg signed [23:0] left_out,right_out
);
reg [3:0] state;reg [2:0] bass_q,treble_q;reg [1:0] effect_q;
reg signed [23:0] xl,xr,lo_l,lo_r,hi_l,hi_r,base;
reg signed [24:0] low_band,high_band;
reg signed [26:0] gain_delta,partial;
reg signed [26:0] left_work,right_work;
wire right_channel=state==5;
wire signed [23:0] x=right_channel?xr:xl;
wire signed [23:0] lo=right_channel?lo_r:lo_l,hi=right_channel?hi_r:hi_l;
wire signed [24:0] dlo={x[23],x}-{lo[23],lo},dhi={x[23],x}-{hi[23],hi};
reg signed [24:0] low_step;
always @*case(bass_q)
 0:low_step=dlo>>>2;
 1,2:low_step=dlo>>>3;
 6:low_step=dlo>>>5;
 default:low_step=dlo>>>4;
endcase
wire signed [24:0] high_step=treble_q<=1?(dhi>>>3):(dhi>>>2);
wire signed [24:0] high_component=treble_q<=1?dhi-(dhi>>>4):dhi-(dhi>>>3);
wire signed [24:0] new_lo=$signed({lo[23],lo})+low_step,new_hi=$signed({hi[23],hi})+high_step;
function signed [26:0] shelf;
 input signed [24:0] v;input [2:0] gain;reg signed [26:0] s,cut_fraction;
 begin
  s={{2{v[24]}},v};
  case(gain)
   0:cut_fraction=s>>>4;1:cut_fraction=s>>>3;default:cut_fraction=s>>>2;
  endcase
  case(gain)
   0,1,2:shelf=cut_fraction-s;
   3:shelf=-(s>>>1);
   5:shelf=(s>>>2)+(s>>>3)+(s>>>5)+(s>>>7);
   6:shelf=s;
   default:shelf=0;
  endcase
 end
endfunction
wire use_high=state==3 || state==7;
wire signed [26:0] gain_result=shelf(use_high?high_band:low_band,use_high?treble_q:bass_q);
wire signed [26:0] add_source=use_high?{{3{base[23]}},base}:partial;
wire signed [26:0] shaped=add_source+gain_delta;
wire signed [27:0] mid=($signed({left_work[26],left_work})+$signed({right_work[26],right_work}))>>>1;
wire signed [27:0] side=($signed({left_work[26],left_work})-$signed({right_work[26],right_work}))>>>2;
wire signed [27:0] fx_l=effect_q==1?mid:effect_q==2?$signed({left_work[26],left_work})+side:$signed({left_work[26],left_work});
wire signed [27:0] fx_r=effect_q==1?mid:effect_q==2?$signed({right_work[26],right_work})-side:$signed({right_work[26],right_work});
function [23:0] sat;input signed [27:0] v;begin
 if(v>28'sd8388607)sat=24'h7fffff;else if(v< -28'sd8388608)sat=24'h800000;else sat=v[23:0];
end endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin
  state<=0;bass_q<=4;treble_q<=4;effect_q<=0;xl<=0;xr<=0;lo_l<=0;lo_r<=0;hi_l<=0;hi_r<=0;base<=0;
  low_band<=0;high_band<=0;gain_delta<=0;partial<=0;left_work<=0;right_work<=0;sample_out_valid<=0;left_out<=0;right_out<=0;
 end else begin
  sample_out_valid<=0;
  case(state)
   0:if(sample_valid)begin xl<=left_in;xr<=right_in;bass_q<=bass;treble_q<=treble;effect_q<=effect;state<=1;end
   1,5:begin
    base<=x;low_band<={lo[23],lo};high_band<=high_component;
    if(right_channel)begin lo_r<=new_lo[23:0];hi_r<=new_hi[23:0];end
    else begin lo_l<=new_lo[23:0];hi_l<=new_hi[23:0];end
    state<=state+1'b1;
   end
   2,6:begin gain_delta<=gain_result;state<=state+1'b1;end
   3,7:begin partial<=shaped;gain_delta<=gain_result;state<=state+1'b1;end
   4:begin left_work<=shaped;state<=5;end
   8:begin right_work<=shaped;state<=9;end
   9:begin left_out<=sat(fx_l);right_out<=sat(fx_r);sample_out_valid<=1;state<=0;end
   default:state<=0;
  endcase
 end
end
endmodule
