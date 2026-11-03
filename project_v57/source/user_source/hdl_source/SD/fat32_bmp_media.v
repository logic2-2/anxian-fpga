// FAT32元数据层与已验证BMP解析器的适配；load_sector在此是文件句柄0..3。
module fat32_bmp_media #(
 parameter integer TIMEOUT_CYCLES=50_000_000, HD_FILES_ONLY=0, SCALE_TO_HD=0,SCAN_AUDIO_INDEX=0
)(
 input clk,rst,scan_start,input [31:0] scan_start_sector,scan_max_sector,
 input [2:0] scan_target_count,
 output ready,scan_done,scan_found_valid,output [31:0] scan_found_sector,output [2:0] scan_found_total,
 input load_start,input [31:0] load_sector,input sd_init_done,adaptive_enable,
 output [3:0] state_code,input [15:0] bmp_width,bmp_height,
 output write_req,input write_req_ack,
 output sd_sec_read,output [31:0] sd_sec_read_addr,
 input [7:0] sd_sec_read_data,input sd_sec_read_data_valid,sd_sec_read_end,
 output bmp_data_wr_en,output [23:0] bmp_data,output fault,
 output [31:0] diagnostic,
 output [3:0] error_detail,
 output audio_index_valid,output [31:0] audio_index_lba,fs_begin,fs_end,fs_data
);
wire selected,fs_fault,bmp_error,bmp_ready,logical_req,logical_valid,logical_end,logical_ready;
wire [31:0] selected_size,logical_addr,bmp_debug,fs_debug;
wire [7:0] logical_data;
wire [3:0] fs_code,bmp_code;
reg [2:0] phase;
reg select_pulse,bmp_start,local_fault;
localparam integer ACK_BITS=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES):1;
localparam integer INIT_BITS=5*TIMEOUT_CYCLES>1?$clog2(5*TIMEOUT_CYCLES):1;
reg [ACK_BITS-1:0] ack_timer;
reg [INIT_BITS-1:0] init_timer;
reg local_timeout;
reg [3:0] local_code;
assign diagnostic=fs_fault?fs_debug:(local_fault && local_code==9)?bmp_debug:{4'd0,load_sector[3:0],logical_addr[15:0],4'd0,bmp_code};
wire raw_write_req,raw_write_en,physical_req;
assign fault=fs_fault|local_fault;
assign error_detail=fs_fault ? fs_code : (local_fault ? local_code : 4'd0);
assign ready=bmp_ready && phase==0 && !fault;
assign write_req=raw_write_req && !fault;
assign bmp_data_wr_en=raw_write_en && !fault;
assign sd_sec_read=physical_req && !fault;
assign state_code=fault ? ((fs_code==8 || local_timeout)?4'hf:4'he) : (!sd_init_done?0:(!scan_done?2:(phase==0?1:(phase<4?3:bmp_code))));
always @(posedge clk or posedge rst) begin
 if(rst) begin phase<=0; select_pulse<=0; bmp_start<=0; local_fault<=0; ack_timer<=0; init_timer<=0; local_timeout<=0; local_code<=0; end
 else begin
  select_pulse<=0; bmp_start<=0;
  // 初始化最多等待5秒；插好卡后按K2/KEY1重新开始，不能按CONFIG。
  if(!sd_init_done && !fault) begin
   if(init_timer>=5*TIMEOUT_CYCLES-1) begin local_fault<=1; local_timeout<=1; local_code<=4'hb; end
   else init_timer<=init_timer+1;
  end else init_timer<=0;
  if(raw_write_req && !write_req_ack && !fault) begin
   if(ack_timer>=TIMEOUT_CYCLES-1) begin local_fault<=1; local_timeout<=1; local_code<=4'hc; end
   else ack_timer<=ack_timer+1;
  end else ack_timer<=0;
  if(bmp_error && !fault) begin local_fault<=1; local_code<=4'h9; end
  if(!fault) case(phase)
   0: if(load_start) begin
    if(!scan_done || load_sector>=scan_found_total || load_sector>=4) begin local_fault<=1; local_code<=4'ha; end
    else begin select_pulse<=1; phase<=1; end
   end
   1: phase<=2;
   2: if(!selected) phase<=3;
   3: if(selected) begin bmp_start<=1; phase<=4; end
   4: if(!bmp_ready) phase<=5;
   5: if(bmp_ready) phase<=0;
   default: begin local_fault<=1; local_code<=4'hf; end
  endcase
 end
end
fat32_volume #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.HD_FILES_ONLY(HD_FILES_ONLY),.FILE_BACKPRESSURE(SCALE_TO_HD),.SCAN_AUDIO_INDEX(SCAN_AUDIO_INDEX)) volume(
 .clk(clk),.rst(rst),.sd_ready(sd_init_done),.mount_start(scan_start),
 .mount_done(scan_done),.found_valid(scan_found_valid),.found_handle(scan_found_sector),.found_count(scan_found_total),
 .select_start(select_pulse),.select_handle(load_sector[1:0]),.selected(selected),.selected_size(selected_size),
 .file_req(logical_req && !fault),.file_sector(logical_addr),.file_ready(logical_ready),.file_data(logical_data),.file_valid(logical_valid),.file_end(logical_end),
 .sd_req(physical_req),.sd_addr(sd_sec_read_addr),.sd_data(sd_sec_read_data),.sd_valid(sd_sec_read_data_valid),.sd_end(sd_sec_read_end),
 .fault(fs_fault),.error_code(fs_code),.diagnostic(fs_debug),.audio_index_valid(audio_index_valid),
 .audio_index_lba(audio_index_lba),.fs_begin(fs_begin),.fs_end(fs_end),.fs_data(fs_data));
generate if(SCALE_TO_HD)begin: adaptive
exhibit_bmp_fit decoder(
 .clk(clk),.rst(rst),.load_start(bmp_start),.sd_init_done(sd_init_done),.adaptive_enable(adaptive_enable),.file_size_limit(selected_size),
 .ready(bmp_ready),.load_error(bmp_error),.load_debug(bmp_debug),.state_code(bmp_code),
 .write_req(raw_write_req),.write_req_ack(write_req_ack),
 .sd_sec_read(logical_req),.sd_sec_read_addr(logical_addr),.sd_sec_read_data(logical_data),
 .sd_sec_read_data_valid(logical_valid && !fault),.sd_sec_read_end(logical_end),.file_ready(logical_ready),
 .bmp_data_wr_en(raw_write_en),.bmp_data(bmp_data),.source_width(),.source_height());
end else begin: fixed_size
assign logical_ready=1'b1;
bmp_read decoder(
 .clk(clk),.rst(rst),.ready(bmp_ready),.file_size_limit(selected_size),.load_error(bmp_error),.load_debug(bmp_debug),
 .scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),.scan_target_count(3'd0),
 .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),
 .load_start(bmp_start),.load_sector(32'd0),.sd_init_done(sd_init_done),.state_code(bmp_code),
 .bmp_width(bmp_width),.bmp_height(bmp_height),.write_req(raw_write_req),.write_req_ack(write_req_ack),
 .sd_sec_read(logical_req),.sd_sec_read_addr(logical_addr),.sd_sec_read_data(logical_data),
 .sd_sec_read_data_valid(logical_valid && !fault),.sd_sec_read_end(logical_end),
 .bmp_data_wr_en(raw_write_en),.bmp_data(bmp_data));
end endgenerate
endmodule

