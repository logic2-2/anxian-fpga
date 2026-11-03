// Frame-clocked notification lifetime. Theme changes never retrigger,
// whether initiated by autoplay or NEXT. Mode/settings changes still do.
// Loading/errors and the settings menu stay legible until they are resolved.
module exhibit_status_toast #(
 parameter integer HOLD_HD=100,HOLD_VGA=120,
 parameter integer FADE_STEP_HD=3,FADE_STEP_VGA=4
)(
 input clk,rst,vs,mode_hd,menu_open,
 input [13:0] scene,input [29:0] options,
 output reg [4:0] opacity
);
reg vs_d,last_menu;
reg [42:0] last_key;
reg [7:0] hold_left;
reg [2:0] fade_count;
reg changed_q,change_pending;
wire [42:0] key={mode_hd,scene[13:2],options};
wire new_state=key!=last_key || menu_open!=last_menu;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  vs_d<=0;last_menu<=0;last_key<=0;changed_q<=0;change_pending<=0;
  opacity<=16;hold_left<=0;fade_count<=0;
 end else begin
  vs_d<=vs;
  // Detect changes separately from the frame timer. Keep an event until a
  // frame consumes it, including changes arriving exactly at a VS edge.
  last_key<=key;last_menu<=menu_open;changed_q<=new_state;
  if(changed_q)change_pending<=1;
  if(vs_d && !vs)begin
   change_pending<=0;
   if(menu_open || !scene[13] || scene[12] || change_pending || changed_q)begin
    opacity<=16;hold_left<=mode_hd?HOLD_HD:HOLD_VGA;fade_count<=0;
   end else if(hold_left!=0)begin hold_left<=hold_left-1'b1;fade_count<=0;end
   else if(opacity!=0)begin
    if(fade_count==(mode_hd?FADE_STEP_HD:FADE_STEP_VGA)-1)begin
     fade_count<=0;opacity<=opacity-1'b1;
    end else fade_count<=fade_count+1'b1;
   end
  end
 end
end
endmodule
