// HX4S20: eight common-anode digits. Segment outputs are active low;
// digit enables are ACTIVE LOW through PNP9012 high-side drivers. Confirmed
// against 5_DIG_VGA schematic and the supplied DEMO/5_seg_SCAN example.
// Blank each digit before changing its segment data to prevent ghosting.
module exhibit_hx4s20_seg_scan #(
 parameter integer CLK_HZ=50000000,SCAN_HZ=200
)(input clk,rst,input [63:0] digits,
 output reg [7:0] select,segments);
localparam integer SLOT_CYCLES=CLK_HZ/(SCAN_HZ*8);
localparam integer C_BITS=SLOT_CYCLES>1?$clog2(SLOT_CYCLES):1;
reg [C_BITS-1:0] count;
reg [2:0] index;
reg [7:0] desired;
always @*case(index)
 0:desired=digits[63:56];1:desired=digits[55:48];
 2:desired=digits[47:40];3:desired=digits[39:32];
 4:desired=digits[31:24];5:desired=digits[23:16];
 6:desired=digits[15:8];default:desired=digits[7:0];
endcase
always @(posedge clk)begin
 if(rst)begin count<=0;index<=0;select<=8'hff;segments<=8'hff;end
 else begin
  if(count==SLOT_CYCLES-1)begin count<=0;index<=index+1'b1;end
  else count<=count+1'b1;
  if(count==0)begin select<=8'hff;segments<=desired;end
  else if(count==1)select<=~(8'b1<<index);
 end
end
endmodule
