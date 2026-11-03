// 异步置位、当地时钟同步释放；PLL未锁定时保持复位。
module media_reset_sync(input clk, input async_reset, output rst);
reg [3:0] release_pipe = 4'b1111;
always @(posedge clk or posedge async_reset)
    if(async_reset) release_pipe <= 4'b1111;
    else release_pipe <= {release_pipe[2:0],1'b0};
assign rst=release_pipe[3];
endmodule
