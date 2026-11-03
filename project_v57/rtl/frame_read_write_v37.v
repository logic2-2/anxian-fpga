`timescale 1ns/1ps
module frame_read_write_v37
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter READ_DATA_BITS         = 32,
	parameter WRITE_DATA_BITS        = 32,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,//
	parameter BURST_SIZE             = 256,
    parameter READ_FIFO_AW           = 9,
    parameter READ_BURST_SIZE        = BURST_SIZE,
	parameter WRITE_V_FLIP           = 1,      // 1: vertical flip when writing TF/BMP frame into SDRAM
	parameter FRAME_WIDTH            = 640,
	parameter FRAME_HEIGHT           = 480
) 
(
	input                            rst,
    input                            monitor_rst,
    output reg [15:0]                 underflows,overflows,                  
	input                            mem_clk,                    // external memory controller user interface clock
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,
	
    /*
    output                           rd_burst_req,               // to external memory controller,send out a burst read request
	output[BURST_BITS - 1:0]         rd_burst_len,               // to external memory controller,data length of the burst read request, not bytes
	output[ADDR_BITS - 1:0]          rd_burst_addr,              // to external memory controller,base address of the burst read request 
	input                            rd_burst_data_valid,        // from external memory controller,read data valid 
	input[MEM_DATA_BITS - 1:0]       rd_burst_data,              // from external memory controller,read request data
	input                            rd_burst_finish,            // from external memory controller,burst read finish
	*/
	output							 App_rd_en,
	output[ADDR_BITS - 1:0]			 App_rd_addr,
	input							 Sdr_rd_en,					 //read_data_valid
	input[MEM_DATA_BITS - 1:0]		 Sdr_rd_dout,
	
	input                            read_clk,                   // data read module clock
	input                            read_req,                   // data read module read request,keep '1' until read_req_ack = '1'
	output                           read_req_ack,               // data read module read request response
	output                           read_finish,                // data read module read request finish
	input[ADDR_BITS - 1:0]           read_addr_0,                // data read module read request base address 0, used when read_addr_index = 0
	input[ADDR_BITS - 1:0]           read_addr_1,                // data read module read request base address 1, used when read_addr_index = 1
	input[ADDR_BITS - 1:0]           read_addr_2,                // data read module read request base address 1, used when read_addr_index = 2
	input[ADDR_BITS - 1:0]           read_addr_3,                // data read module read request base address 1, used when read_addr_index = 3
	input[1:0]                       read_addr_index,            // select valid base address from read_addr_0 read_addr_1 read_addr_2 read_addr_3
	input[ADDR_BITS - 1:0]           read_len,                   // data read module read request data length
	input                            read_en,                    // data read module read request for one data, read_data valid next clock
	output[READ_DATA_BITS  - 1:0]    read_data,                  // read data
	/*
	output                           wr_burst_req,               // to external memory controller,send out a burst write request
	output[BURST_BITS - 1:0]         wr_burst_len,               // to external memory controller,data length of the burst write request, not bytes
	output[ADDR_BITS - 1:0]          wr_burst_addr,              // to external memory controller,base address of the burst write request 
	input                            wr_burst_data_req,          // from external memory controller,write data request ,before data 1 clock
	output[MEM_DATA_BITS - 1:0]      wr_burst_data,              // to external memory controller,write data
	input                            wr_burst_finish,            // from external memory controller,burst write finish
	*/
	output							 App_wr_en,
	output[ADDR_BITS - 1:0]			 App_wr_addr,
	output[MEM_DATA_BITS - 1:0]	 App_wr_din,
	output[3:0]						 App_wr_dm,
	
	//
	input                            write_clk,                  // data write module clock
	input                            write_req,                  // data write module write request,keep '1' until read_req_ack = '1'
	output                           write_req_ack,              // data write module write request response
	output                           write_finish,               // data write module write request finish
	input[ADDR_BITS - 1:0]           write_addr_0,               // data write module write request base address 0, used when write_addr_index = 0
	input[ADDR_BITS - 1:0]           write_addr_1,               // data write module write request base address 1, used when write_addr_index = 1
	input[ADDR_BITS - 1:0]           write_addr_2,               // data write module write request base address 1, used when write_addr_index = 2
	input[ADDR_BITS - 1:0]           write_addr_3,               // data write module write request base address 1, used when write_addr_index = 3
	input[1:0]                       write_addr_index,           // select valid base address from write_addr_0 write_addr_1 write_addr_2 write_addr_3
	input[ADDR_BITS - 1:0]           write_len,                  // data write module write request data length
	input                            write_en,                   // data write module write request for one data
	input[WRITE_DATA_BITS - 1:0]     write_data,                // write data
    output write_active,read_active,
    input movie_page,movie_hd,linear_write,
    input compact_page,compact_repeat,compact_skip

);
wire[READ_FIFO_AW-1:0]                          wrusedw;                    // write used words
wire[8:0]                                      rdusedw;                    // read used words

wire 								 App_rd_busy;
wire								 App_wr_busy;

wire read_empty,read_full;
wire [15:0] scan_pixel16;
assign read_data={16'd0,scan_pixel16};
// Align the PHY's data with Sdr_rd_en at the read-FIFO write edge.
// Direct sampling skips a 32-bit word at burst boundaries. V11 R1/W0
// (data delayed one memory clock, write path unchanged) passed the board's
// known-pixel comparison; R0/W0, R0/W1 and R1/W1 did not.
wire read_fifo_aclr;
reg [MEM_DATA_BITS-1:0] read_phy_data_d;
reg decimate_half;
reg [15:0] decimate_hold;
wire compact_we=Sdr_rd_en && (!compact_skip || decimate_half);
wire [31:0] compact_data=compact_skip?{read_phy_data_d[15:0],decimate_hold}:read_phy_data_d;
always @(posedge mem_clk or posedge rst)begin
 if(rst)begin decimate_half<=0;decimate_hold<=0;end
 else if(read_fifo_aclr)decimate_half<=0;
 else if(Sdr_rd_en && compact_skip)begin decimate_half<=!decimate_half;decimate_hold<=read_phy_data_d[15:0];end
end
always @(posedge mem_clk or posedge rst)begin
 if(rst)read_phy_data_d<=0;
 else read_phy_data_d<=Sdr_rd_dout;
end
reg [1:0] monitor_ack;
reg monitor_ack_d;
reg [2:0] monitor_frames;
always @(posedge read_clk or posedge monitor_rst)begin
 if(monitor_rst)begin underflows<=0;monitor_ack<=0;monitor_ack_d<=0;monitor_frames<=0;end
 else begin
  monitor_ack<={monitor_ack[0],read_req_ack};monitor_ack_d<=monitor_ack[1];
  if(monitor_ack[1] && !monitor_ack_d && monitor_frames<4)monitor_frames<=monitor_frames+1'b1;
  if(monitor_frames<4)underflows<=0;
  else if(read_en && read_empty && underflows!=16'hffff)underflows<=underflows+1'b1;
 end
end
always @(posedge mem_clk or posedge rst)begin
 if(rst)overflows<=0;
 else if(Sdr_rd_en && read_full && overflows!=16'hffff)overflows<=overflows+1'b1;
end
wire                                 write_fifo_aclr;            // fifo Asynchronous clear

wire O_wr_busy;
wire write_waiting;
// Do not reserve the main port while the shared cache has granted its owner
// to the intro/thumbnail reader-writer. That owner must finish its burst.
wire write_claim=write_waiting && !Sdr_busy && !Sdr_init_ref_vld;
wire O_rd_busy;

assign write_active=O_wr_busy | write_claim;
assign read_active=O_rd_busy;
assign App_wr_busy = O_wr_busy | write_claim;//下个时钟写指令拉高
assign App_rd_busy = O_rd_busy;//读指令还没有过去十个时钟;因为写指令优先，不需要在意下个时钟是否是读指令
assign App_wr_dm = 4'b0000;

//instantiate an asynchronous FIFO 
wfifo_32_32_512 write_buf
	(
	.clkr                      	(mem_clk                  ),          // Read side clock
	.clkw                      	(write_clk                ),          // Write side clock
	.rst                       	(rst | write_fifo_aclr    ),          // Asynchronous clear
	.we                      	(write_en                 ),          // Write Request
	.re                      	(App_wr_en        		  ),          // Read Request
	.di                       	(write_data               ),          // Input Data
	.empty_flag                 (                         ),          // Read side Empty flag
	.full_flag                  (                         ),          // Write side Full flag
	.wrusedw                	(              	  		  ),          // Read Used Words
	.rdusedw                	(rdusedw),          // Write Used Words
	.dout                       (App_wr_din		          )
);

frame_fifo_write_v37
#
(
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BURST_BITS                 (BURST_BITS               ),
	.BURST_SIZE                 (BURST_SIZE               ),
	.WRITE_V_FLIP               (WRITE_V_FLIP             ),
	.FRAME_WIDTH                (FRAME_WIDTH              ),
	.FRAME_HEIGHT               (FRAME_HEIGHT             )
) 
frame_fifo_write_m0              
(  .linear_write(linear_write),
	.rst                        (rst                      ),
	.mem_clk                    (mem_clk                  ),
    .Sdr_init_done				(Sdr_init_done),
	.Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .Sdr_busy					(Sdr_busy),
	.App_rd_busy				(App_rd_busy),
    .O_wr_busy					(O_wr_busy),
    .write_ready(write_waiting),
	
	.App_wr_en					(App_wr_en),
    .App_wr_addr				(App_wr_addr),
	.write_req                  (write_req                ),
	.write_req_ack              (write_req_ack            ),
	.write_finish               (write_finish             ),
	.write_addr_0               (write_addr_0             ),
	.write_addr_1               (write_addr_1             ),
	.write_addr_2               (write_addr_2             ),
	.write_addr_3               (write_addr_3             ),
	.write_addr_index           (write_addr_index         ),    
	.write_len                  (write_len                ),
	.fifo_aclr                  (write_fifo_aclr    ),
	.rdusedw                 	({1'b0,rdusedw})
);

//instantiate an asynchronous FIFO 
rfifo_32_32_512 #(.DATA_WIDTH_R(16),.ADDR_WIDTH_W(READ_FIFO_AW),.ADDR_WIDTH_R(READ_FIFO_AW+1),.AL_FULL_NUM((1<<READ_FIFO_AW)-3)) read_buf
	(
	.clkr                     	(read_clk                   ),          // Read side clock
	.clkw                     	(mem_clk                    ),          // Write side clock
	.rst                      	(rst | read_fifo_aclr       ),          // Asynchronous clear
	.we                     	(compact_we),
	.re                     	(read_en                    ),          // Read Request
	.di                      	(compact_data),
	.empty_flag(read_empty),          // Read side Empty flag
	.full_flag(read_full),          // Write side Full flag
	.wrusedw                	(wrusedw),          // Read Used Words
	.rdusedw                	(                  			 ),          // Write Used Words
	.dout(scan_pixel16)
);

frame_fifo_read_v37
#
(
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BURST_BITS                 (BURST_BITS               ),
	.BURST_SIZE(READ_BURST_SIZE),
    .FIFO_DEPTH(1<<READ_FIFO_AW),
    .FIFO_COUNT_BITS(READ_FIFO_AW)
)
frame_fifo_read_m0
(
	.rst                        (rst                      ),
	.mem_clk                    (mem_clk                  ),
    .Sdr_init_done				(Sdr_init_done),
	.Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .Sdr_busy					(Sdr_busy),
    .Sdr_rd_en					(Sdr_rd_en),
	.App_wr_busy				(App_wr_busy),
    .O_rd_busy					(O_rd_busy),
	
    .App_rd_en					(App_rd_en),
    .App_rd_addr				(App_rd_addr),
	.read_req                   (read_req                 ),
	.read_req_ack               (read_req_ack             ),
	.read_finish                (read_finish              ),
	.read_addr_0                (read_addr_0              ),
	.read_addr_1                (read_addr_1              ),
	.read_addr_2                (read_addr_2              ),
	.read_addr_3                (read_addr_3              ),
	.read_addr_index            (read_addr_index          ),    
	.read_len                   (read_len                 ),
	.fifo_aclr                  (read_fifo_aclr           ),
	.wrusedw                	(wrusedw),
    .movie_page(movie_page),.movie_hd(movie_hd),.compact_page(compact_page),.compact_repeat(compact_repeat),.compact_skip(compact_skip)
);

endmodule





