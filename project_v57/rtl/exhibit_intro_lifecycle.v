// One opening per board/UI reset; media/fit reloads cannot replay it.
module exhibit_intro_lifecycle #(parameter integer CLOCK_HZ=50_000_000)(
 input clk,rst,asset_checked,asset_valid,presented,decoder_fault,
 output hold_tour,output [5:0] frame_gray,output reg finished
);
reg [5:0] frame;
reg [5:0] registered_gray;
wire [5:0] next_frame=frame+1'b1;
reg [22:0] ticks;
(* async_reg="true" *) reg [1:0] presented_sync;
(* async_reg="true" *) reg [1:0] fault_sync;
assign hold_tour=asset_valid && !finished;
assign frame_gray=registered_gray;
always @(posedge clk or posedge rst)begin
 if(rst)begin frame<=0;registered_gray<=0;ticks<=0;finished<=0;presented_sync<=0;fault_sync<=0;end
 else begin
  presented_sync<={presented_sync[0],presented};
  fault_sync<={fault_sync[0],decoder_fault};
  if((asset_checked && !asset_valid) || fault_sync[1])finished<=1;
  if(hold_tour && presented_sync[1])begin
   if(ticks==CLOCK_HZ/10-1)begin
    ticks<=0;if(frame==39)finished<=1;else begin frame<=next_frame;registered_gray<=(next_frame>>1)^next_frame;end
   end else ticks<=ticks+1'b1;
  end
 end
end
endmodule
