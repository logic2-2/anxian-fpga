// Mutually exclusive clock gates change only on falling edges.
// Reset the video/serializer logic throughout the clock handover.
module exhibit_glitchless_clock_mux(
 input clk0,clk1,rst,select1,output clk_out
);
reg gate0,gate1;
reg [1:0] other0,other1,sel0,sel1;
always @(negedge clk0 or posedge rst) begin
 if(rst) begin gate0<=0;other0<=0;sel0<=0;end
 else begin
  other0<={other0[0],gate1};sel0<={sel0[0],select1};
  gate0<=!sel0[1] && !other0[1];
 end
end
always @(negedge clk1 or posedge rst) begin
 if(rst) begin gate1<=0;other1<=0;sel1<=0;end
 else begin
  other1<={other1[0],gate0};sel1<={sel1[0],select1};
  gate1<=sel1[1] && !other1[1];
 end
end
assign clk_out=(clk0 & gate0)|(clk1 & gate1);
endmodule

module exhibit_video_switch #(
 parameter integer GUARD_CYCLES=5_000_000
)(
 input clk,rst,request,requested_mode,hi_locked,
 output reg active_mode,output video_hold,output busy
);
reg [1:0] state;
reg [23:0] guard;
reg pending_mode;
assign video_hold=state!=0;
assign busy=state!=0;
always @(posedge clk or posedge rst) begin
 if(rst) begin state<=1;guard<=0;active_mode<=1;pending_mode<=1;end
 else case(state)
 0: if(request && requested_mode!=active_mode && (!requested_mode || hi_locked)) begin
     pending_mode<=requested_mode;guard<=0;state<=1;
    end
 1: if(guard==GUARD_CYCLES-1) begin
     active_mode<=pending_mode;guard<=0;state<=2;
    end else guard<=guard+1;
 2: if(guard==GUARD_CYCLES-1) begin guard<=0;state<=0;end
    else guard<=guard+1;
 default: begin state<=1;guard<=0;pending_mode<=0;end
 endcase
end
endmodule
