module hdmi_serial_control_v37(
 input I_pixel_clk,I_serial_clk,I_rst,
 output write_bank,serial_rst,output reg prepare_now,read_bank,load_now
);
reg S_odd_even,S_odd_even_1d,S_odd_even_2d;
reg S_load_en,S_load_en_1d,S_load_en_2d;
reg bank0,bank1,bank2;
reg locked,next_bank;
reg [4:0] phase;
// Retain asynchronous assertion and4-stage local synchronous release.
// A dedicated vendor logic buffer gives the related-clock reset path its
// required data delay without changing the serializer or waiving checks.
wire reset_req_delayed;
(* keep="true" *) EG_LOGIC_BUF reset_delay(.o(reset_req_delayed),.i(I_rst));
media_reset_sync serial_reset(I_serial_clk,reset_req_delayed,serial_rst);
assign write_bank=S_odd_even;
// Register all three control fields together. All lanes, including the
// forwarded clock, gain the same serial-cycle latency; word cadence/order
// and the prepare-before-load interval are preserved.
always @(posedge I_serial_clk or posedge serial_rst)begin
 if(serial_rst)begin prepare_now<=0;read_bank<=0;load_now<=0;end
 else begin
  prepare_now<=locked?phase[3]:S_load_en_1d;
  // While unlocked next_bank tracks bank1 exactly. At lock acquisition
  // it switches to the original phase-driven bank sequence. This removes
  // the mux from the370MHz output register without changing any output edge.
  read_bank<=next_bank;
  load_now<=locked?phase[4]:S_load_en_2d;
 end
end
always @(posedge I_pixel_clk or posedge I_rst)begin
 if(I_rst)S_odd_even<=0;else S_odd_even<=!S_odd_even;
end
always @(posedge I_serial_clk or posedge serial_rst)begin
 if(serial_rst)begin
  S_odd_even_1d<=0;S_odd_even_2d<=0;S_load_en<=0;S_load_en_1d<=0;S_load_en_2d<=0;
  bank0<=0;bank1<=0;bank2<=0;locked<=0;next_bank<=0;phase<=0;
 end else begin
  S_odd_even_1d<=S_odd_even;S_odd_even_2d<=S_odd_even_1d;
  S_load_en<=S_odd_even_1d^S_odd_even_2d;
  S_load_en_1d<=S_load_en;S_load_en_2d<=S_load_en_1d;
  if(S_odd_even_1d^S_odd_even_2d)bank0<=!S_odd_even_1d;
  bank1<=bank0;bank2<=bank1;
  if(!locked)begin
   if(S_load_en_2d)begin locked<=1;phase<=5'b00001;next_bank<=!bank2;end
   else next_bank<=bank0;
  end else begin
   phase<={phase[3:0],phase[4]};
   if(phase[4])next_bank<=!next_bank;
  end
 end
end
endmodule
