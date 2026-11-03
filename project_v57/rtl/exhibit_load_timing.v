// Diagnostic stopwatch: A = reset-to-all-slots-ready; b = cumulative time
// spent waiting on the physical sector API. Both freeze at ready or fault.
// Four BCD digits show seconds with hundredths, saturated at 99.99 seconds.
module exhibit_load_timing #(
 parameter integer CENTI_CYCLES=500000,PAGE_CYCLES=100000000
)(input clk,rst,ready,fault,card_request,
 output [47:0] segments,output reg [15:0] total_bcd,card_bcd);
localparam C_BITS=CENTI_CYCLES>1?$clog2(CENTI_CYCLES):1;
localparam P_BITS=PAGE_CYCLES>1?$clog2(PAGE_CYCLES):1;
reg [C_BITS-1:0] total_fraction,card_fraction;
reg [P_BITS-1:0] page_count;
reg page;
function [15:0] increment_bcd;
 input [15:0] value;
 begin
  if(value[3:0]!=9)increment_bcd=value+1;
  else if(value[7:4]!=9)increment_bcd={value[15:4]+12'd1,4'd0};
  else if(value[11:8]!=9)increment_bcd={value[15:8]+8'd1,8'd0};
  else if(value[15:12]!=9)increment_bcd={value[15:12]+4'd1,12'd0};
  else increment_bcd=16'h9999;
 end
endfunction
wire [15:0] value=page?card_bcd:total_bcd;
wire [6:0] d0,d1,d2,d3,marker;
seg_decoder dec0(value[3:0],d0);
seg_decoder dec1(value[7:4],d1);
seg_decoder dec2(value[11:8],d2);
seg_decoder dec3(value[15:12],d3);
seg_decoder dec_marker(page?4'hb:4'ha,marker);
assign segments={{1'b1,7'b0011001},{1'b1,marker},{1'b1,d3},{1'b0,d2},{1'b1,d1},{1'b1,d0}};
always @(posedge clk)begin
 if(rst)begin
  total_fraction<=0;card_fraction<=0;page_count<=0;page<=0;total_bcd<=0;card_bcd<=0;
 end else begin
  if(page_count==PAGE_CYCLES-1)begin page_count<=0;page<=!page;end
  else page_count<=page_count+1'b1;
  if(!ready && !fault)begin
   if(total_fraction==CENTI_CYCLES-1)begin total_fraction<=0;total_bcd<=increment_bcd(total_bcd);end
   else total_fraction<=total_fraction+1'b1;
   if(card_request)begin
    if(card_fraction==CENTI_CYCLES-1)begin card_fraction<=0;card_bcd<=increment_bcd(card_bcd);end
    else card_fraction<=card_fraction+1'b1;
   end
  end
 end
end
endmodule
