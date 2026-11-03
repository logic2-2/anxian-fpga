// Apply on menu close. Media reset does not reset the UI selection.
module exhibit_fit_reload #(parameter integer HOLD_CYCLES=1_000_000)(
 input clk,rst,menu_open,requested_fit,
 output reg applied_fit,output reg media_hold
);
reg [$clog2(HOLD_CYCLES+1)-1:0] count;
always @(posedge clk or posedge rst)begin
 if(rst)begin applied_fit<=0;media_hold<=0;count<=0;end
 else if(!menu_open && requested_fit!=applied_fit)begin
  applied_fit<=requested_fit;media_hold<=1;count<=HOLD_CYCLES-1;
 end else if(media_hold)begin
  if(count==0)media_hold<=0;else count<=count-1'b1;
 end
end
endmodule
