// Native SD command serializer. All state uses the 50 MHz host clock;
// rise/fall are enables for the externally generated SD clock.
module sd_native4_cmd(
 input clk,rst,rise,fall,cmd_in,start,
 input [5:0] command,input [31:0] argument,
 input long_response,no_response,
 output reg cmd_out,cmd_oe,busy,done,error,output reg [1:0] error_reason,
 output [31:0] response
);
localparam IDLE=0,TX=1,RELEASE=2,WAIT=3,RX=4,CHECK=5,TRAIL=6;
reg [2:0] state;
reg [47:0] tx,response_bits;
reg [7:0] remaining,wait_count;
reg [6:0] rx_crc;
reg [5:0] index;
reg is_long,is_none;
assign response=response_bits[39:8];
function [6:0] crc7_bit;
 input [6:0] c;input b;
 begin crc7_bit={c[5:0],1'b0} ^ ((c[6]^b)?7'h09:7'h00); end
endfunction
function [6:0] command_crc;
 input [39:0] bits;
 integer i;reg [6:0] c;
 begin c=0;for(i=39;i>=0;i=i-1)c=crc7_bit(c,bits[i]);command_crc=c;end
endfunction
always @(posedge clk)begin
 if(rst)begin
  state<=IDLE;cmd_out<=1;cmd_oe<=0;busy<=0;done<=0;error<=0;error_reason<=0;
  tx<=0;response_bits<=0;remaining<=0;wait_count<=0;rx_crc<=0;
  index<=0;is_long<=0;is_none<=0;
 end else begin
  done<=0;
  case(state)
   IDLE:if(start)begin
    tx<={2'b01,command,argument,command_crc({2'b01,command,argument}),1'b1};
    index<=command;is_long<=long_response;is_none<=no_response;
    remaining<=48;busy<=1;error<=0;error_reason<=0;state<=TX;
   end
   TX:if(fall)begin
    cmd_oe<=1;cmd_out<=tx[47];tx<={tx[46:0],1'b1};
    remaining<=remaining-1'b1;
    if(remaining==1)state<=RELEASE;
   end
   RELEASE:if(fall)begin
    cmd_oe<=0;cmd_out<=1;wait_count<=0;response_bits<=0;rx_crc<=0;
    state<=is_none?TRAIL:WAIT;
   end
   WAIT:if(rise)begin
    if(!cmd_in)begin
     // Start bit is zero and leaves CRC at zero. R2 excludes its header.
     remaining<=is_long?135:47;response_bits<=0;state<=RX;
    end else if(wait_count==255)begin error<=1;error_reason<=1;state<=TRAIL;wait_count<=0;end
    else wait_count<=wait_count+1'b1;
   end
   RX:if(rise)begin
    response_bits<={response_bits[46:0],cmd_in};
    if(remaining>8 && (!is_long || remaining<=128))rx_crc<=crc7_bit(rx_crc,cmd_in);
    remaining<=remaining-1'b1;
    if(remaining==1)state<=CHECK;
   end
   CHECK:begin
    if(!response_bits[0])begin error<=1;error_reason<=3;end
    if(index!=41 && rx_crc!=response_bits[7:1])begin error<=1;error_reason<=2;end
    if(!is_long && (response_bits[47:46]!=0 ||
      (index!=41 && response_bits[45:40]!=index)))begin error<=1;error_reason<=3;end
    wait_count<=0;state<=TRAIL;
   end
   TRAIL:if(rise)begin
    if(wait_count==7)begin busy<=0;done<=1;state<=IDLE;end
    else wait_count<=wait_count+1'b1;
   end
   default:state<=IDLE;
  endcase
 end
end
endmodule
