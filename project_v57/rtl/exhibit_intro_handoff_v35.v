// Approximately400ms smoothstep out, a black frame-boundary switch, then400ms in.
// The existing RGB fade multipliers consume this envelope; no extra DSPs/RAM.
module exhibit_intro_handoff_v35(
 input clk,rst,mode_hd,vs,intro_visible,tail_request,
 output reg [8:0] gain,output override_effect,black_ready,output reg done
);
localparam IDLE=0,OUT=1,BLACK=2,IN=3;
reg [1:0] state;reg [4:0] step;reg vs_d;
(* async_reg="true" *) reg [1:0] tail_sync;
wire [4:0] last=mode_hd?5'd20:5'd24;
assign override_effect=intro_visible || state!=IDLE;
assign black_ready=state==BLACK && gain==0;
function [8:0] eased;input hd;input [4:0] n;begin
 if(hd)case(n)
 0:eased=0;1:eased=2;2:eased=7;3:eased=16;4:eased=27;5:eased=40;
 6:eased=55;7:eased=72;8:eased=90;9:eased=109;10:eased=128;
 11:eased=147;12:eased=166;13:eased=184;14:eased=201;15:eased=216;
 16:eased=229;17:eased=240;18:eased=249;19:eased=254;default:eased=256;
 endcase
 else case(n)
 0:eased=0;1:eased=1;2:eased=5;3:eased=11;4:eased=19;5:eased=29;
 6:eased=40;7:eased=53;8:eased=66;9:eased=81;10:eased=96;11:eased=112;
 12:eased=128;13:eased=144;14:eased=160;15:eased=175;16:eased=190;
 17:eased=203;18:eased=216;19:eased=227;20:eased=237;21:eased=245;
 22:eased=251;23:eased=255;default:eased=256;
 endcase
end endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=IDLE;step<=0;gain<=256;vs_d<=0;tail_sync<=0;done<=0;end
 else begin
  vs_d<=vs;tail_sync<={tail_sync[0],tail_request};
  if(vs_d && !vs)case(state)
   IDLE:if(intro_visible && tail_sync[1])begin state<=OUT;step<=0;gain<=256;done<=0;end
   OUT:if(step==last-1)begin step<=last;gain<=0;state<=BLACK;end
       else begin step<=step+1'b1;gain<=256-eased(mode_hd,step+1'b1);end
   BLACK:if(!intro_visible)begin state<=IN;step<=0;gain<=0;end
   IN:if(step==last-1)begin step<=last;gain<=256;state<=IDLE;done<=1;end
      else begin step<=step+1'b1;gain<=eased(mode_hd,step+1'b1);end
  endcase
 end
end
endmodule
