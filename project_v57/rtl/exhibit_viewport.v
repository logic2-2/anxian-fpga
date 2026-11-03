// Runs on the read-enable timing (two cycles before video_delay output).
module exhibit_viewport(input clk,rst,vs,de,small_view,output consume);
reg [9:0] x,y;reg de_d,vs_d;
assign consume=de && (!small_view || (x>=160 && x<480 && y>=120 && y<360));
always @(posedge clk or posedge rst) begin
 if(rst)begin x<=0;y<=0;de_d<=0;vs_d<=0;end
 else begin
  de_d<=de;vs_d<=vs;
  if(!de) x<=0;else if(x==639)x<=0;else x<=x+1;
  if(vs_d && !vs)y<=0;
  else if(de_d && !de)begin if(y==479)y<=0;else y<=y+1;end
 end
end
endmodule
