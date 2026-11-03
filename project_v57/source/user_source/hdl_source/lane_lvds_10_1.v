// Pixel words are latched in alternating banks. All four lanes share one
// serial cadence controller, which locks once and emits exactly five DDR
// cycles per word. The selected word is prepared a serial cycle before load.
module lane_lvds_10_1 #(parameter DEVICE="EG")(
 input wire I_pixel_clk,I_serial_clk,I_rst,
 input wire [9:0] I_data_in,
 input wire I_write_bank,I_serial_rst,I_prepare,I_read_bank,I_load,
 output wire O_serial_out
);
wire serial_rst=I_serial_rst;
reg [9:0] word_buf0,word_buf1,S_word_ready,S_shift_data;
reg [1:0] S_oddr_data;
always @(posedge I_pixel_clk or posedge I_rst)begin
 if(I_rst)begin word_buf0<=0;word_buf1<=0;end
 else if(I_write_bank)word_buf1<=I_data_in;
 else word_buf0<=I_data_in;
end
always @(posedge I_serial_clk or posedge serial_rst)begin
 if(serial_rst)S_word_ready<=0;
 else if(I_prepare)S_word_ready<=I_read_bank?word_buf1:word_buf0;
end
always @(posedge I_serial_clk or posedge serial_rst)begin
 if(serial_rst)S_shift_data<=0;
 else if(I_load)S_shift_data<=S_word_ready;
 else S_shift_data<=S_shift_data<<2;
end
always @(posedge I_serial_clk or posedge serial_rst)begin
 if(serial_rst)S_oddr_data<=0;
 else S_oddr_data<=S_shift_data[9:8];
end
    generate
        if(DEVICE == "EF2")
            begin
                EF2_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
        else if(DEVICE == "EF3")
            begin
                EF3_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
        else if(DEVICE == "EF4")
            begin
                EF4_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
        else if(DEVICE == "SF1")
            begin
                SF1_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
        else if(DEVICE == "EG")
            begin
                EG_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
        else if(DEVICE == "PH1A")
            begin
                PH1_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
        else if(DEVICE == "PH1P")
            begin
                PH1P_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
        else if(DEVICE == "DR1")
            begin
                DR1_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
    endgenerate
    
endmodule


// The event synchronizer is used only to establish the initial phase. Once
// locked, a modulo-five counter prevents per-pixel CDC latency variation
// from changing the length of a TMDS symbol.
module hdmi_serial_control(
 input I_pixel_clk,I_serial_clk,I_rst,
 output write_bank,serial_rst,output reg prepare_now,read_bank,load_now
);
reg S_odd_even,S_odd_even_1d,S_odd_even_2d;
reg S_load_en,S_load_en_1d,S_load_en_2d;
reg bank0,bank1,bank2;
reg locked,next_bank;
reg [4:0] phase;
media_reset_sync serial_reset(I_serial_clk,I_rst,serial_rst);
assign write_bank=S_odd_even;
// Register all three control fields together. All lanes, including the
// forwarded clock, gain the same serial-cycle latency; word cadence/order
// and the prepare-before-load interval are preserved.
always @(posedge I_serial_clk or posedge serial_rst)begin
 if(serial_rst)begin prepare_now<=0;read_bank<=0;load_now<=0;end
 else begin
  prepare_now<=locked?phase[3]:S_load_en_1d;
  read_bank<=locked?next_bank:bank1;
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
  end else begin
   phase<={phase[3:0],phase[4]};
   if(phase[4])next_bank<=!next_bank;
  end
 end
end
endmodule
