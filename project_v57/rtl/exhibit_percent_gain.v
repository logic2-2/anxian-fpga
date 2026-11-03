// round(percent*256/100), exact for integer percentages 0..150.
// Parameter-only pipeline: settings settle during vertical blank, not pixels.
module exhibit_percent_gain(input clk,rst,input [7:0] percent,output reg [8:0] gain);
reg [15:0] numerator;reg [28:0] reciprocal_product;
always @(posedge clk or posedge rst)begin
 if(rst)begin numerator<=25650;reciprocal_product<=134482950;gain<=256;end
 else begin
  numerator<={percent,8'd0}+16'd50;
  reciprocal_product<=numerator*13'd5243;
  gain<=reciprocal_product[27:19];
 end
end
endmodule
