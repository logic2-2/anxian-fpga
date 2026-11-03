// Read-only native four-bit SD transport for the existing level-held sector API.
// CMD18 stays open at sector boundaries. Repeated LBA replays verified cache;
// adjacent LBA resumes, random LBA issues CMD12 before a new CMD18.
// No byte is published until all four CRC16s and the end token pass.
// Supports SD v2 SDSC/SDHC/SDXC at 3.3 V, default speed (no CMD6/UHS).
module sd_native4_card #(
 parameter integer INIT_HALF_CYCLES=125,FAST_HALF_CYCLES=1,
 parameter integer POWERUP_CYCLES=50000,TIMEOUT_CYCLES=5000000,
 parameter integer INIT_TIMEOUT_CYCLES=100000000
)(
 input clk,rst,
 output reg sd_clk,inout sd_cmd,input [3:0] sd_dat,
 input read_req,input [31:0] read_lba,
 output reg init_done,output reg [7:0] read_data,
 output reg read_valid,read_end,fault,output reg [3:0] error_code,
 output reg [31:0] physical_reads,cache_hits,
 output reg dat3_hold_high,output [5:0] debug_command,output [1:0] debug_command_error
);
localparam POWER=0,CLOCKS=1,INIT_ISSUE=2,COMMAND=3,BUSY_WAIT=4,
 IDLE=5,START_READ=6,TOKEN=7,DATA=8,CRC=9,END_BIT=10,
 PARK=11,REPLAY_ADDR=12,REPLAY_DATA=13,FINISH=14,REARM=15,FAILED=16,
 BOOT_STOP=17,BOOT_QUIET=18,BOOT_CS_HIGH=19;
localparam T_BITS=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES):1;
localparam I_BITS=INIT_TIMEOUT_CYCLES>1?$clog2(INIT_TIMEOUT_CYCLES):1;
localparam P_BITS=POWERUP_CYCLES>1?$clog2(POWERUP_CYCLES):1;
localparam D_BITS=INIT_HALF_CYCLES>1?$clog2(INIT_HALF_CYCLES):1;
reg [4:0] state,command_return,busy_return;
reg [3:0] init_step;
reg [D_BITS-1:0] divider;
reg [P_BITS-1:0] power_timer;
reg [I_BITS-1:0] init_timer;
reg [T_BITS-1:0] timer;
reg fast,clock_run,high_capacity,stream_open,cache_valid;
reg [7:0] startup_clocks;
reg [3:0] quiet_clocks;
reg [15:0] rca;
reg [31:0] requested_lba,cached_lba,next_lba;
reg [9:0] nibble_index;
reg [4:0] crc_index;
reg [3:0] high_nibble;
reg [15:0] crc0,crc1,crc2,crc3;
reg crc_bad;
reg [8:0] replay_index,replay_output;
reg cmd_start,cmd_long,cmd_none,read_command_pending;
reg [5:0] cmd_index;
reg [31:0] cmd_argument;
wire cmd_out,cmd_oe,cmd_busy,cmd_done,cmd_error;
wire [31:0] cmd_response;
assign debug_command=cmd_index;
wire tick=clock_run && divider==(fast?FAST_HALF_CYCLES-1:INIT_HALF_CYCLES-1);
wire clock_rise=tick && !sd_clk;
reg sample_rise;
reg [3:0] dat_sample;
reg cmd_sample;
wire rise=sample_rise;
always @(posedge clk)begin
 dat_sample<=sd_dat;cmd_sample<=sd_cmd;
 if(rst)sample_rise<=0;else sample_rise<=clock_rise;
end
wire fall=tick && sd_clk;
assign sd_cmd=cmd_oe?cmd_out:1'bz;
sd_native4_cmd commands(.clk(clk),.rst(rst),.rise(rise),.fall(fall),.cmd_in(cmd_sample),
 .start(cmd_start),.command(cmd_index),.argument(cmd_argument),
 .long_response(cmd_long),.no_response(cmd_none),.cmd_out(cmd_out),.cmd_oe(cmd_oe),
 .busy(cmd_busy),.done(cmd_done),.error(cmd_error),.error_reason(debug_command_error),.response(cmd_response));
// BRAM9K is already full. Explicitly use one of the 16 spare BRAM32Ks;
// a synchronous one-cycle read matches the sector replay pipeline.
wire [7:0] sector_q;
EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
 .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("32K")) sector_ram(
 .dia({high_nibble,dat_sample}),.addra(nibble_index[9:1]),.cea(1'b1),.ocea(1'b1),
 .clka(clk),.wea(state==DATA && rise && nibble_index[0]),.rsta(1'b0),.bea(1'b1),.doa(),
 .dib(8'd0),.addrb(replay_index),.ceb(1'b1),.oceb(1'b1),.clkb(clk),.web(1'b0),
 .rstb(1'b0),.beb(1'b1),.dob(sector_q));
function [15:0] crc16_bit;
 input [15:0] c;input b;
 begin crc16_bit={c[14:0],1'b0} ^ ((c[15]^b)?16'h1021:16'h0000);end
endfunction
task issue;
 input [5:0] index;input [31:0] arg;input long_r,none_r;input [4:0] ret;
 begin
  cmd_index<=index;cmd_argument<=arg;cmd_long<=long_r;cmd_none<=none_r;
  cmd_start<=1;command_return<=ret;state<=COMMAND;clock_run<=1;timer<=0;
  if(ret==TOKEN)begin state<=TOKEN;read_command_pending<=1;end
 end
endtask
task fail;
 input [3:0] code;
 begin
  fault<=1;error_code<=code;cache_valid<=0;clock_run<=0;state<=FAILED;
  read_valid<=0;read_end<=0;dat3_hold_high<=0;
 end
endtask
always @(posedge clk)begin
 if(rst)begin sd_clk<=0;divider<=0;end
 else if(clock_run)begin
  if(tick)begin sd_clk<=!sd_clk;divider<=0;end
  else divider<=divider+1'b1;
 end else begin sd_clk<=0;divider<=0;end
end
always @(posedge clk)begin
 if(rst)begin
  state<=POWER;command_return<=0;busy_return<=0;init_step<=0;
  power_timer<=0;init_timer<=0;timer<=0;fast<=0;clock_run<=0;
  high_capacity<=0;stream_open<=0;cache_valid<=0;startup_clocks<=0;quiet_clocks<=0;rca<=0;dat3_hold_high<=0;
  requested_lba<=0;cached_lba<=0;next_lba<=0;nibble_index<=0;crc_index<=0;
  high_nibble<=0;crc0<=0;crc1<=0;crc2<=0;crc3<=0;crc_bad<=0;replay_index<=0;replay_output<=0;
  cmd_start<=0;cmd_index<=0;cmd_argument<=0;cmd_long<=0;cmd_none<=0;read_command_pending<=0;
  init_done<=0;read_data<=0;read_valid<=0;read_end<=0;fault<=0;error_code<=0;
  physical_reads<=0;cache_hits<=0;
 end else begin
  cmd_start<=0;read_valid<=0;read_end<=0;
  if(!init_done && state!=FAILED)init_timer<=init_timer+1'b1;
  if(state==COMMAND || state==BUSY_WAIT || state==TOKEN || state==BOOT_QUIET)timer<=timer+1'b1;
  case(state)
   POWER:if(power_timer==POWERUP_CYCLES-1)begin clock_run<=1;state<=CLOCKS;end
    else power_timer<=power_timer+1'b1;
   CLOCKS:if(rise)begin
    // Drain any old response (including136-bit R2) before driving CMD.
    if(startup_clocks==255)state<=BOOT_STOP;
    else startup_clocks<=startup_clocks+1'b1;
   end
   // A powered card may still be inside the previous CMD18. Stop that stream
   // before CMD0 so DAT3 cannot be sampled low as a SPI chip-select request.
   // An idle/cold card may ignore CMD12; that particular timeout is harmless.
   BOOT_STOP:begin quiet_clocks<=0;issue(12,0,0,0,BOOT_QUIET);end
   BOOT_QUIET:if(rise)begin
    if(dat_sample==4'hf)begin
     if(quiet_clocks==7)begin dat3_hold_high<=1;state<=BOOT_CS_HIGH;power_timer<=0;timer<=0;end
     else quiet_clocks<=quiet_clocks+1'b1;
    end else quiet_clocks<=0;
   end
   BOOT_CS_HIGH:if(power_timer==POWERUP_CYCLES-1)state<=INIT_ISSUE;
    else power_timer<=power_timer+1'b1;
   INIT_ISSUE:case(init_step)
    0:issue(0,0,0,1,INIT_ISSUE);
    1:issue(8,32'h1aa,0,0,INIT_ISSUE);
    2:issue(55,0,0,0,INIT_ISSUE);
    3:issue(41,32'h40300000,0,0,INIT_ISSUE);
    4:issue(2,0,1,0,INIT_ISSUE);
    5:issue(3,0,0,0,INIT_ISSUE);
    6:begin busy_return<=INIT_ISSUE;issue(7,{rca,16'd0},0,0,BUSY_WAIT);end
    7:issue(55,{rca,16'd0},0,0,INIT_ISSUE);
    8:issue(6,2,0,0,INIT_ISSUE);
    9:issue(16,512,0,0,INIT_ISSUE);
    default:if(fall)begin init_done<=1;fast<=1;clock_run<=0;state<=IDLE;dat3_hold_high<=0;end
   endcase
   COMMAND:if(cmd_done)begin
    timer<=0;
    if(command_return==BOOT_QUIET)begin state<=BOOT_QUIET;quiet_clocks<=0;end
    else if(cmd_error)fail(1);
    else if(!init_done)begin
     if(init_step==1 && cmd_response!=32'h1aa)fail(2);
     else if((init_step==2 || init_step==6 || init_step==7 || init_step==8 || init_step==9)
       && (cmd_response & 32'hfff98008)!=0)fail(3);
     else if(init_step==5 && (cmd_response[15:13]!=0 || cmd_response[31:16]==0))fail(3);
     else begin
      state<=command_return;
      if(init_step==3 && !cmd_response[31])init_step<=2;
      else begin
       if(init_step==3)high_capacity<=cmd_response[30];
       if(init_step==5)rca<=cmd_response[31:16];
       if(init_step==8 && high_capacity)init_step<=10;
       else init_step<=init_step+1'b1;
      end
     end
    end else if((cmd_response & 32'hfff98008)!=0)fail(3);
    else begin
     state<=command_return;
     if(command_return==TOKEN)begin stream_open<=1;physical_reads<=physical_reads+1'b1;end
    end
   end
   BUSY_WAIT:if(rise && dat_sample[0])begin timer<=0;state<=busy_return;end
   IDLE:if(read_req)begin
    requested_lba<=read_lba;replay_index<=0;replay_output<=0;
    if(cache_valid && cached_lba==read_lba)begin cache_hits<=cache_hits+1'b1;state<=REPLAY_ADDR;end
    else if(stream_open && read_lba==next_lba)begin
     clock_run<=1;timer<=0;state<=TOKEN;physical_reads<=physical_reads+1'b1;cache_valid<=0;
    end else if(stream_open)begin
     stream_open<=0;cache_valid<=0;busy_return<=START_READ;issue(12,0,0,0,BUSY_WAIT);
    end else begin cache_valid<=0;state<=START_READ;end
   end
   START_READ:begin
    if(!high_capacity && |requested_lba[31:23])fail(4);
    else begin
     physical_reads<=physical_reads+1'b1;
     issue(18,high_capacity?requested_lba:(requested_lba<<9),0,0,TOKEN);
    end
   end
   TOKEN:if(rise && !dat_sample[0])begin
    if(dat_sample!=0)fail(5);
    else begin
     nibble_index<=0;crc0<=0;crc1<=0;crc2<=0;crc3<=0;crc_bad<=0;state<=DATA;timer<=0;
    end
   end
   DATA:if(rise)begin
    high_nibble<=dat_sample;nibble_index<=nibble_index+1'b1;
    crc0<=crc16_bit(crc0,dat_sample[0]);crc1<=crc16_bit(crc1,dat_sample[1]);
    crc2<=crc16_bit(crc2,dat_sample[2]);crc3<=crc16_bit(crc3,dat_sample[3]);
    if(nibble_index==1023)begin crc_index<=0;state<=CRC;end
   end
   CRC:if(rise)begin
    if(dat_sample!={crc3[15],crc2[15],crc1[15],crc0[15]})crc_bad<=1;
    crc0<={crc0[14:0],1'b0};crc1<={crc1[14:0],1'b0};
    crc2<={crc2[14:0],1'b0};crc3<={crc3[14:0],1'b0};
    crc_index<=crc_index+1'b1;
    if(crc_index==15)state<=END_BIT;
   end
   END_BIT:if(rise)begin
    if(crc_bad || dat_sample!=4'hf)fail(6);
    else begin
     cached_lba<=requested_lba;next_lba<=requested_lba+1'b1;cache_valid<=1;state<=PARK;
     if(fall)begin clock_run<=0;replay_index<=0;replay_output<=0;state<=REPLAY_ADDR;end
    end
   end
   // Stop on the falling edge directly after the end bit: preserve the next token.
   PARK:if(fall)begin clock_run<=0;replay_index<=0;replay_output<=0;state<=REPLAY_ADDR;end
   REPLAY_ADDR:begin replay_index<=9'd1;state<=REPLAY_DATA;end
   REPLAY_DATA:begin
    read_data<=sector_q;read_valid<=1;
    if(replay_output==511)state<=FINISH;
    else begin replay_index<=replay_index+1'b1;replay_output<=replay_output+1'b1;end
   end
   FINISH:begin read_end<=1;state<=REARM;end
   REARM:if(!read_req)state<=IDLE;
   FAILED:begin clock_run<=0;end
   default:fail(15);
  endcase
  // Data may start before the command serializer's trailing clocks finish.
  // Arm DAT reception at CMD18 issue, and validate R1 independently.
  if(read_command_pending && cmd_done)begin
   read_command_pending<=0;
   if(cmd_error)fail(1);
   else if((cmd_response & 32'hfff98008)!=0)fail(3);
   else stream_open<=1;
  end
  if(!init_done && state!=FAILED && init_timer==INIT_TIMEOUT_CYCLES-1)fail(7);
  if((state==COMMAND || state==BUSY_WAIT || state==TOKEN || state==BOOT_QUIET) && timer==TIMEOUT_CYCLES-1)fail(8);
 end
end
endmodule
