// Immutable four-slot cache and interaction policy. All inputs are in clk domain
// except write_finish_toggle and publish_ack_toggle (synchronized below).
module exhibit_control #(
 parameter integer CLK_HZ=50_000_000,
 parameter integer FRAME_WORDS=307200,
 parameter integer DWELL_SECONDS=5,
 parameter integer REQUIRE_ALL_READY=0,
 parameter integer IDLE_SECONDS=30,USE_BOOT_STATE=0,HAS_AUDIO_HOLD=0,HAS_BOOT_HOLD=0,
 parameter integer ONE_SHOT_NARRATION=0
)(
 input clk,rst,sd_ready,media_ready,media_fault,
 input [3:0] media_error,
 input scan_done,found_valid,input [31:0] found_handle,
 input [2:0] found_total,
 input pixel_valid,write_finish_toggle,key_next,key_select,key_style,publish_ack_toggle,
 input [31:0] options,input [1:0] boot_theme,boot_mode,input detail_audio_active,detail_audio_done,boot_hold,
 output reg scan_start,load_start,output reg [31:0] load_handle,
 output reg [1:0] write_slot,
 output reg [3:0] ready_mask,
 output reg [47:0] publish_scene,
 output reg publish_toggle,
 output display_valid,output fault,output [3:0] error_detail,
 output [1:0] mode,theme
);
localparam AUTO=2'd0,PREVIEW=2'd1,DETAIL=2'd2;
reg scan_kicked,loading,saw_busy,source_done,write_done,cache_fault;
reg [3:0] cache_error;
reg [2:0] preload;
reg [31:0] handles[0:3];
localparam integer SECOND_BITS=CLK_HZ>1?$clog2(CLK_HZ):1;
localparam integer IDLE_BITS=IDLE_SECONDS>1?$clog2(IDLE_SECONDS):1;
localparam integer WORD_BITS=FRAME_WORDS>0?$clog2(FRAME_WORDS+2):1;
reg [WORD_BITS-1:0] words;
reg [SECOND_BITS-1:0] write_wait,second_count;
reg [3:0] dwell;
reg pending_audio_advance;
reg [IDLE_BITS-1:0] idle_seconds;
reg [1:0] ui_mode,ui_theme,ui_profile;
reg [2:0] wr_sync,ack_sync;
wire wr_pulse=wr_sync[2]^wr_sync[1];
wire second_tick=second_count==CLK_HZ-1;
wire [47:0] desired_scene={options,ui_profile,display_valid,fault,error_detail,ready_mask,ui_mode,ui_theme};
reg [3:0] dwell_target;
always @*case(options[16:15])
 0:dwell_target=3;1:dwell_target=5;2:dwell_target=8;default:dwell_target=12;
endcase
assign display_valid=REQUIRE_ALL_READY?(&ready_mask):(|ready_mask);
assign fault=media_fault|cache_fault;
assign error_detail=media_fault?media_error:cache_error;
assign mode=ui_mode;
assign theme=ui_theme;
function [1:0] next_ready;
 input [1:0] current;
 input [3:0] mask;
 integer k;
 reg [1:0] candidate;
 reg chosen;
 begin
  next_ready=current;chosen=0;
  for(k=1;k<=4;k=k+1) begin
   candidate=current+k;
   if(!chosen && mask[candidate]) begin next_ready=candidate;chosen=1;end
  end
 end
endfunction
integer n;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  scan_kicked<=0;scan_start<=0;load_start<=0;load_handle<=0;
  loading<=0;saw_busy<=0;source_done<=0;write_done<=0;
  cache_fault<=0;cache_error<=0;preload<=0;write_slot<=0;ready_mask<=0;
  words<=0;write_wait<=0;wr_sync<=0;ack_sync<=0;
  publish_scene<=0;publish_toggle<=0;ui_mode<=USE_BOOT_STATE?boot_mode:AUTO;ui_theme<=USE_BOOT_STATE?boot_theme:2'd0;ui_profile<=0;
  second_count<=0;dwell<=0;idle_seconds<=0;pending_audio_advance<=0;
  for(n=0;n<4;n=n+1) handles[n]<=0;
 end else begin
  scan_start<=0;load_start<=0;
  if(HAS_AUDIO_HOLD && detail_audio_done && ui_mode==DETAIL)pending_audio_advance<=1;
  if(ui_mode!=DETAIL)pending_audio_advance<=0;
  wr_sync<={wr_sync[1:0],write_finish_toggle};
  ack_sync<={ack_sync[1:0],publish_ack_toggle};
  // Bundled-data mailbox: payload remains frozen until destination ACK.
  // UI changes during an outstanding publication coalesce into the next one.
  if(ack_sync[2]==publish_toggle && desired_scene!=publish_scene) begin
   publish_scene<=desired_scene;publish_toggle<=~publish_toggle;
  end
  if(found_valid && found_handle<4) handles[found_handle[1:0]]<=found_handle;
  if(sd_ready && media_ready && !scan_kicked && !fault) begin
   scan_start<=1;scan_kicked<=1;
  end
  if(!fault) begin
   if(scan_done && media_ready && !loading && preload<found_total && preload<4) begin
    // Each slot is written exactly once until reset. Ready/displayed slots
    // cannot be selected for a subsequent write, even during interaction.
    if(!ready_mask[preload[1:0]]) begin
     write_slot<=preload[1:0];load_handle<=handles[preload[1:0]];
     load_start<=1;loading<=1;saw_busy<=0;source_done<=0;write_done<=0;
     words<=0;write_wait<=0;
    end
   end
   if(loading) begin
    if(!media_ready) saw_busy<=1;
    if(saw_busy && media_ready) source_done<=1;
    // Keep one extra invalid value so an oversized stream cannot wrap back
    // to FRAME_WORDS and accidentally pass the exact-length check.
    if(pixel_valid && words<FRAME_WORDS+1) words<=words+1'b1;
    if(wr_pulse) write_done<=1;
    // Completion is the conjunction of file completion, exact pixel count,
    // and the SDRAM controller's drained write completion, in either order.
    if(source_done && (write_done || wr_pulse)) begin
     if(words==FRAME_WORDS) begin
      ready_mask[write_slot]<=1;preload<=preload+1;loading<=0;
     end else begin cache_fault<=1;cache_error<=4'hd;end
    end else if(source_done) begin
     if(write_wait==CLK_HZ-1) begin cache_fault<=1;cache_error<=4'hc;end
     else write_wait<=write_wait+1;
    end
   end
  end
  // A media error freezes preload, but already committed immutable slots
  // remain available to the visitor and are never replaced by failed data.
  if(!display_valid || (HAS_BOOT_HOLD && boot_hold)) begin second_count<=0;dwell<=0;idle_seconds<=0;end
  else if(options[30] || options!=publish_scene[47:16])begin
   second_count<=0;dwell<=0;idle_seconds<=0;
  end else if(key_next || key_select || key_style) begin
   pending_audio_advance<=0;
   second_count<=0;dwell<=0;idle_seconds<=0;
   if(key_style) ui_profile<=ui_profile+1;
   // KEY2 retains its original NEXT+PREVIEW action. Notifications watch the
   // mode rather than the theme, so subsequent NEXTs in PREVIEW stay quiet.
   else if(key_next) begin ui_theme<=next_ready(ui_theme,ready_mask);ui_mode<=PREVIEW;end
   else case(ui_mode)
    AUTO: ui_mode<=PREVIEW;
    PREVIEW: begin
     ui_mode<=DETAIL;
     // A guided narration always starts with the first ready exhibit.
     if(ONE_SHOT_NARRATION)ui_theme<=next_ready(2'd3,ready_mask);
    end
    default: ui_mode<=PREVIEW;
   endcase
  end else if(HAS_AUDIO_HOLD && ui_mode==DETAIL && (pending_audio_advance || detail_audio_done))begin
   // End of the consumed narration, not read-ahead EOF, advances the tour.
   ui_theme<=next_ready(ui_theme,ready_mask);pending_audio_advance<=0;
   // Finish one ascending pass, then restart the ordinary automatic tour.
   if(ONE_SHOT_NARRATION && next_ready(ui_theme,ready_mask)<=ui_theme)
    ui_mode<=AUTO;
   second_count<=0;dwell<=0;idle_seconds<=0;
  end else if(second_tick) begin
   second_count<=0;
   if(ui_mode==AUTO) begin
    idle_seconds<=0;
    if(dwell>=dwell_target-1) begin ui_theme<=next_ready(ui_theme,ready_mask);dwell<=0;end
    else dwell<=dwell+1;
   end else begin
    dwell<=0;
    if(HAS_AUDIO_HOLD && ui_mode==DETAIL && detail_audio_active)idle_seconds<=0;
    else if(idle_seconds==IDLE_SECONDS-1) begin ui_mode<=AUTO;idle_seconds<=0;end
    else idle_seconds<=idle_seconds+1;
   end
  end else second_count<=second_count+1;
 end
end
endmodule
