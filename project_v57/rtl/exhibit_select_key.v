// Debounced short event on release, long event once at HOLD_CYCLES.
module exhibit_select_key #(parameter integer CLK_HZ=50000000,
 parameter integer DEBOUNCE_CYCLES=CLK_HZ/50,
 parameter integer HOLD_CYCLES=CLK_HZ*4/5)(
 input clk,rst,button_n,output reg short_press,long_press
);
reg [1:0] sync;
reg stable,held;
localparam integer DEBOUNCE_BITS=DEBOUNCE_CYCLES>1?$clog2(DEBOUNCE_CYCLES):1;
reg [DEBOUNCE_BITS-1:0] debounce_count;
// The dedicated menu key uses a two-second hold (100M clocks at 50MHz).
// Keep enough bits for that threshold; the original 26 bits fit only 1.34s.
localparam integer HOLD_COUNT_BITS=$clog2(HOLD_CYCLES+1);
reg [HOLD_COUNT_BITS-1:0] hold_count;
wire release_now=sync[1] && !stable && debounce_count==DEBOUNCE_CYCLES-1;
always @(posedge clk or posedge rst) begin
 if(rst) begin sync<=3;stable<=1;held<=0;debounce_count<=0;hold_count<=0;short_press<=0;long_press<=0;end
 else begin
  sync<={sync[0],button_n};short_press<=0;long_press<=0;
  if(sync[1]==stable) debounce_count<=0;
  else if(debounce_count==DEBOUNCE_CYCLES-1) begin
   stable<=sync[1];debounce_count<=0;
   if(sync[1]) begin if(!held) short_press<=1;hold_count<=0;held<=0;end
  end else debounce_count<=debounce_count+1;
  if(!stable && !held && !release_now) begin
   if(hold_count==HOLD_CYCLES-1) begin long_press<=1;held<=1;end
   else hold_count<=hold_count+1;
  end
 end
end
endmodule
