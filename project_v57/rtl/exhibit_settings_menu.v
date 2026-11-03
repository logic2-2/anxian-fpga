// Physical KEY3: menu/back. KEY2: next row/minus. KEY4: confirm/plus.
// Numeric keys repeat on hold. No two-key actions are required.
// Holding KEY3 for two seconds restores brightness100 in any state.
module exhibit_settings_menu #(parameter integer CLK_HZ=50_000_000)(
 input clk,rst,next_n,view_n,menu_n,active_mode,
 output reg menu_open,output reg [3:0] cursor,
 output reg mode_request,requested_mode,
 output reg next_event,view_event,output style_event,
 output [31:0] options,
 output reg [6:0] brightness_payload,output reg brightness_toggle,input brightness_ack,
 output reg adaptive_enable
);
wire ns,nl,vs,vl,ms,ml;
reg [6:0] brightness,volume;reg [7:0] contrast;reg [2:0] effect;
reg [1:0] dwell,spectrum,preset;reg subtitle,editing;
reg [1:0] next_sync,view_sync,menu_sync;
reg nr_active,vr_active,nr_pulse,vr_pulse;
localparam integer REPEAT_CYCLES=CLK_HZ/15>0?CLK_HZ/15:1;
localparam integer REPEAT_BITS=REPEAT_CYCLES>1?$clog2(REPEAT_CYCLES):1;
reg [REPEAT_BITS-1:0] nr_count,vr_count;
wire numeric_row=cursor==1 || cursor==2 || cursor==7;
wire minus_event=ns || nl || nr_pulse;
wire plus_event=vs || vl || vr_pulse;
reg [2:0] brightness_ack_sync;
assign options={editing,menu_open,volume,spectrum,subtitle,effect,dwell,contrast,brightness};
assign style_event=0;
exhibit_select_key #(.CLK_HZ(CLK_HZ)) kn(clk,rst,next_n,ns,nl);
exhibit_select_key #(.CLK_HZ(CLK_HZ)) kv(clk,rst,view_n,vs,vl);
exhibit_select_key #(.CLK_HZ(CLK_HZ),.HOLD_CYCLES(CLK_HZ*2)) km(clk,rst,menu_n,ms,ml);
// Separate held request/ack channel: dimming/recovery also works during TF loading.
always @(posedge clk or posedge rst)begin
 if(rst)begin brightness_payload<=100;brightness_toggle<=0;brightness_ack_sync<=0;end
 else begin
  brightness_ack_sync<={brightness_ack_sync[1:0],brightness_ack};
  if(brightness_ack_sync[2]==brightness_toggle && brightness_payload!=brightness)begin
   brightness_payload<=brightness;brightness_toggle<=!brightness_toggle;
  end
 end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin next_sync<=3;view_sync<=3;menu_sync<=3;end
 else begin
  next_sync<={next_sync[0],next_n};view_sync<={view_sync[0],view_n};menu_sync<={menu_sync[0],menu_n};
 end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin nr_active<=0;vr_active<=0;nr_pulse<=0;vr_pulse<=0;nr_count<=0;vr_count<=0;end
 else begin
  nr_pulse<=0;vr_pulse<=0;
  if(!menu_open || !editing || !numeric_row || !menu_sync[1] || ms || ml)begin nr_active<=0;vr_active<=0;nr_count<=0;vr_count<=0;end
  else begin
   if(next_sync[1])begin nr_active<=0;nr_count<=0;end
   else if(nl)begin nr_active<=1;nr_count<=0;end
   else if(nr_active)begin
    if(nr_count==REPEAT_CYCLES-1)begin nr_count<=0;nr_pulse<=1;end else nr_count<=nr_count+1'b1;
   end
   if(view_sync[1])begin vr_active<=0;vr_count<=0;end
   else if(vl)begin vr_active<=1;vr_count<=0;end
   else if(vr_active)begin
    if(vr_count==REPEAT_CYCLES-1)begin vr_count<=0;vr_pulse<=1;end else vr_count<=vr_count+1'b1;
   end
  end
 end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  menu_open<=0;cursor<=0;editing<=0;mode_request<=0;requested_mode<=0;next_event<=0;view_event<=0;
  brightness<=100;contrast<=100;volume<=100;dwell<=0;spectrum<=1;preset<=0;effect<=0;subtitle<=1;adaptive_enable<=0;
 end else begin
  mode_request<=0;next_event<=0;view_event<=0;
  if(ml)begin brightness<=100;menu_open<=0;editing<=0;cursor<=0;preset<=0;end
  else if(ms)begin
   if(editing)editing<=0;
   else begin menu_open<=!menu_open;cursor<=0;end
  end
  else if(!menu_sync[1])begin end
  else if(menu_open && editing)begin
   if(minus_event)case(cursor)
    1:begin if(brightness!=0)brightness<=brightness-1'b1;preset<=0;end
    2:begin if(contrast>50)contrast<=contrast-1'b1;preset<=0;end
    7:if(volume!=0)volume<=volume-1'b1;
   endcase
   else if(plus_event)case(cursor)
    1:begin if(brightness<100)brightness<=brightness+1'b1;preset<=0;end
    2:begin if(contrast<150)contrast<=contrast+1'b1;preset<=0;end
    7:if(volume<100)volume<=volume+1'b1;
   endcase
  end else if(menu_open)begin
   if(ns)cursor<=cursor==8?0:cursor+1'b1;
   else if(vs)case(cursor)
    0:begin requested_mode<=!active_mode;mode_request<=1;end
    1,2,7:editing<=1;
    3:dwell<=dwell+1'b1;
    4:effect<=effect==5?0:effect+1'b1;
    5:subtitle<=!subtitle;
    6:spectrum<=spectrum==2?0:spectrum+1'b1;
    8:adaptive_enable<=!adaptive_enable;
   endcase
  end else begin
   next_event<=ns;view_event<=vs;
   if(vl)begin
    preset<=preset+1'b1;
    case(preset)
     0:begin brightness<=90;contrast<=100;end
     1:begin brightness<=100;contrast<=125;end
     2:begin brightness<=85;contrast<=75;end
     3:begin brightness<=100;contrast<=100;end
    endcase
   end
  end
 end
end
endmodule
