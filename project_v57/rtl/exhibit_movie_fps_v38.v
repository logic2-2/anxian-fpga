// Count newly presented movie frames, not SDRAM writes or HDMI refreshes.
// Sample the bundled frame id at the first active pixel of each output frame.
// V37 PLLs produce exactly74MHz HD and25MHz VGA (not nominal74.25/25.175).
module exhibit_movie_fps_v38 #(
 parameter integer HD_CLOCK_HZ=74_000_000,VGA_CLOCK_HZ=25_000_000
)(
 input clk,rst,mode_hd,enable,vs,de,input [15:0] frame_id,
 output reg [6:0] fps,output reg valid
);
localparam integer MAX_CLOCK=HD_CLOCK_HZ>VGA_CLOCK_HZ?HD_CLOCK_HZ:VGA_CLOCK_HZ;
localparam integer TIMER_BITS=MAX_CLOCK>1?$clog2(MAX_CLOCK):1;
reg [TIMER_BITS-1:0] timer;
reg [6:0] count;
reg [15:0] last_id;
reg have_id,frame_seen,vs_d,mode_d;
wire vs_start=vs_d && !vs;
wire new_frame=enable && de && !frame_seen && !vs_start && (!have_id || frame_id!=last_id);
wire [6:0] count_next=count==99?7'd99:count+new_frame;
wire window_end=mode_hd?timer==HD_CLOCK_HZ-1:timer==VGA_CLOCK_HZ-1;
always @(posedge clk or posedge rst)begin
 if(rst)begin timer<=0;count<=0;last_id<=0;have_id<=0;frame_seen<=0;vs_d<=0;mode_d<=0;fps<=0;valid<=0;end
 else begin
  vs_d<=vs;mode_d<=mode_hd;
  if(!enable || mode_d!=mode_hd)begin
   timer<=0;count<=0;have_id<=0;frame_seen<=0;fps<=0;valid<=0;
  end else begin
   if(vs_start)frame_seen<=0;
   else if(de && !frame_seen)begin frame_seen<=1;last_id<=frame_id;have_id<=1;end
   if(window_end)begin timer<=0;fps<=count_next;count<=0;valid<=1;end
   else begin timer<=timer+1'b1;count<=count_next;end
  end
 end
end
endmodule
