// 只读FAT32扇区映射：根目录前4个BMP短目录项，文件簇链预检后再输出数据。
// 不写卡。不支持GPT/exFAT/FAT16/子目录；错误锁存，K2/KEY1复位后重新挂载。
module fat32_volume #(
 parameter integer TIMEOUT_CYCLES=50_000_000,
 parameter integer MAX_DIR_SECTORS=4096, HD_FILES_ONLY=0,
 parameter integer FILE_BACKPRESSURE=0,SCAN_AUDIO_INDEX=0
)(
 input clk,rst,sd_ready,mount_start,
 output reg mount_done,found_valid,
 output reg [31:0] found_handle,
 output reg [2:0] found_count,
 input select_start,input [1:0] select_handle,
 output reg selected,
 output reg [31:0] selected_size,
 input file_req,input [31:0] file_sector,input file_ready,
 output reg [7:0] file_data,output reg file_valid,file_end,
 output reg sd_req,output reg [31:0] sd_addr,
 input [7:0] sd_data,input sd_valid,sd_end,
 output reg fault,output reg [3:0] error_code,
 output reg [31:0] diagnostic,
 output reg audio_index_valid,output reg [31:0] audio_index_lba,
 output [31:0] fs_begin,fs_end,fs_data
);
localparam IDLE=0,READ=1,MBR=2,BOOT=3,GEOM=4,DIR=5,DIR_NEXT=6,
 FAT=7,PREFLIGHT=8,OPEN=9,MAP=10,SEND=11,RELEASE=12,FAIL=13,
 FAT_ISSUE=14,DATA_ISSUE=15,DIR_CHECK=16,BOOT_APPLY=17,DATA_CHECK=18,WIN_WAIT=19,WIN_GET=20,DIR_LOAD=21,FAT_LOAD=22,SEND_ADDR=23,SEND_WAIT=24,SEEK=25,MBR_CHECK=26,DIR_ISSUE=27;
reg [4:0] state,after_read,after_fat;
reg [9:0] received;
(* ram_style="bram" *) reg [7:0] sector_buf[0:511];
reg [8:0] ram_read_addr,window_base;
reg [7:0] sector_q;
reg [7:0] header_data[0:63],partition_data[0:63],window_data[0:31];
reg [7:0] sig_low,sig_high;
reg [5:0] window_index,window_length;
reg [4:0] window_return;
// One synchronous read and one write port, no reset of the memory array.
always @(posedge clk)begin
 if(state==READ && sd_valid && received<512)sector_buf[received[8:0]]<=sd_data;
 sector_q<=sector_buf[ram_read_addr];
end
reg [8:0] send_idx,entry_offset;
reg [1:0] partition;
reg is_partition;
reg [31:0] volume_start,partition_size,volume_size,fat_start,data_start,fat_size,cluster_count;
assign fs_begin=volume_start;assign fs_end=volume_start+volume_size;assign fs_data=data_start;
reg [7:0] sectors_per_cluster;
reg [3:0] cluster_shift;
reg [31:0] cluster;
// Valid FAT32 sectors/cluster are powers of two in one byte: at most128.
// Directory admission caps a file at16MiB: at most32768 file clusters.
localparam integer DIR_COUNT_BITS=MAX_DIR_SECTORS>0?$clog2(MAX_DIR_SECTORS+1):1;
reg [6:0] sector_in_cluster;
reg [DIR_COUNT_BITS-1:0] dir_sectors;
reg [15:0] chain_left;
reg [31:0] files_cluster[0:3],files_size[0:3];
reg [31:0] first_cluster,next_cluster;
reg [14:0] last_logical;
localparam integer TIMER_BITS=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES):1;
reg [TIMER_BITS-1:0] timer;
reg [32:0] data_lba_q;
reg [8:0] fat_offset;
reg have_last;
reg selected_contiguous;
// Directory admission caps files at 16MiB, hence <=32768 logical sectors.
reg [15:0] seek_left;
// 复用仍在sector_buf内的FAT扇区。任何新物理读取先失效，完整成功后才置有效。
reg fat_cache_valid;
reg [24:0] fat_cache_sector;
reg [31:0] entry_cluster_q,entry_size_q;
reg entry_empty_q,entry_bmp_q;
reg boot_fields_ok,boot_geometry_ok,boot_flags_ok;
reg data_cluster_valid;
reg [3:0] dir_error;
reg [31:0] partition_lba_q;
reg mbr_signature_ok,mbr_superfloppy,mbr_type_ok;
function [15:0] le16;input [8:0] o;begin
 if(o==510)le16={sig_high,sig_low};else le16={header_data[o+1],header_data[o]};
end endfunction
function [31:0] partition32;input [5:0] o;begin
 partition32={partition_data[o+3],partition_data[o+2],partition_data[o+1],partition_data[o]};
end endfunction
function good_cluster; input [31:0] c; begin good_cluster=(c>=2 && c<cluster_count+2 && c<32'h0ffffff0); end endfunction
wire [5:0] po={partition,4'b0};
wire [31:0] b_total={header_data[35],header_data[34],header_data[33],header_data[32]}, b_fatsz={header_data[39],header_data[38],header_data[37],header_data[36]};
wire [15:0] b_reserved={header_data[15],header_data[14]},b_flags={header_data[41],header_data[40]};
wire [31:0] b_root={header_data[47],header_data[46],header_data[45],header_data[44]};
wire [33:0] overhead={18'd0,b_reserved}+({2'b0,b_fatsz} << (header_data[16]==2));
wire [32:0] volume_end={1'b0,volume_start}+{1'b0,b_total};
wire [31:0] entry_cluster={window_data[21],window_data[20],window_data[27],window_data[26]};
wire [31:0] entry_size={window_data[31],window_data[30],window_data[29],window_data[28]};
wire [31:0] fat_value={4'd0,window_data[3][3:0],window_data[2],window_data[1],window_data[0]};
wire [32:0] data_lba={1'b0,data_start}+(({1'b0,cluster}-2)<<cluster_shift)+sector_in_cluster;
wire [31:0] file_sectors=(selected_size>>9)+(|selected_size[8:0]);
wire [31:0] file_clusters=(file_sectors+sectors_per_cluster-1)>>cluster_shift;
task fail; input [3:0] code; begin
 if(code==6)begin
  if(state==FAT)diagnostic<={(after_fat==PREFLIGHT?4'h8:4'h9),cluster[13:0],fat_value[13:0]};
  else if(!good_cluster(cluster))diagnostic<={4'ha,cluster[27:0]};
  else diagnostic<={4'hb,data_lba_q[27:0]};
 end else diagnostic<={code,cluster[27:0]};
 fault<=1; error_code<=code; state<=FAIL; sd_req<=0; selected<=0; file_valid<=0; file_end<=0;
end endtask
task read_sector; input [31:0] addr; input [4:0] ret; begin
 fat_cache_valid<=0;
 sd_addr<=addr; sd_req<=1; received<=0; timer<=0; after_read<=ret; state<=READ;
end endtask
task follow_fat; input [4:0] ret; begin
 after_fat<=ret; state<=FAT_ISSUE;
end endtask
task load_window;input [8:0] offset;input [5:0] count;input [4:0] return_state;begin
 window_base<=offset;ram_read_addr<=offset;window_index<=0;window_length<=count;
 window_return<=return_state;state<=WIN_WAIT;
end endtask
integer k;
always @(posedge clk or posedge rst) begin
 if(rst) begin
 diagnostic<=0;selected_contiguous<=0;
 audio_index_valid<=0;audio_index_lba<=0;
 state<=IDLE; after_read<=IDLE; after_fat<=IDLE; mount_done<=0; found_valid<=0; found_handle<=0; found_count<=0;
 selected<=0; selected_size<=0; sd_req<=0; sd_addr<=0; fault<=0; error_code<=0;
 file_data<=0; file_valid<=0; file_end<=0; received<=0; send_idx<=0; entry_offset<=0; partition<=0;
 is_partition<=0; volume_start<=0; partition_size<=0; volume_size<=0; fat_start<=0; data_start<=0; fat_size<=0; cluster_count<=0;
 sectors_per_cluster<=0; cluster_shift<=0; cluster<=0; sector_in_cluster<=0; dir_sectors<=0; chain_left<=0;
 first_cluster<=0; last_logical<=0; next_cluster<=0; timer<=0; fat_offset<=0; have_last<=0;data_lba_q<=0;seek_left<=0;
 fat_cache_valid<=0; fat_cache_sector<=0;ram_read_addr<=0;window_base<=0;window_index<=0;window_length<=0;window_return<=0;sig_low<=0;sig_high<=0;
 entry_cluster_q<=0; entry_size_q<=0; entry_empty_q<=0; entry_bmp_q<=0;
 boot_fields_ok<=0; boot_geometry_ok<=0; boot_flags_ok<=0;
 data_cluster_valid<=0;dir_error<=0;
 partition_lba_q<=0;mbr_signature_ok<=0;mbr_superfloppy<=0;mbr_type_ok<=0;
 for(k=0;k<4;k=k+1) begin files_cluster[k]<=0; files_size[k]<=0; end
 end else begin
 found_valid<=0; file_valid<=0; file_end<=0;
 case(state)
 IDLE: begin
  if(mount_start && sd_ready) begin
   mount_done<=0; found_count<=0; selected<=0; is_partition<=0; volume_start<=0; partition_size<=0; partition<=0;
   audio_index_valid<=0;audio_index_lba<=0;
   read_sector(0,MBR);
  end else if(select_start && mount_done && select_handle<found_count) begin
   selected_contiguous<=1;diagnostic<=0;
   selected<=0; selected_size<=files_size[select_handle]; first_cluster<=files_cluster[select_handle];
   cluster<=files_cluster[select_handle]; chain_left<=0; state<=OPEN;
  end else if(file_req && selected) begin
   if(file_sector>=file_sectors) fail(7);
   // Fast path is enabled only after every required FAT link was checked
   // in PREFLIGHT and all links proved to be consecutive. Fragmented files
   // keep the original checked FAT-following path below.
   else if(selected_contiguous)begin
    cluster<=first_cluster+(file_sector>>cluster_shift);
    sector_in_cluster<=file_sector&({24'd0,sectors_per_cluster}-1'b1);
    state<=DATA_ISSUE;
   end
   else if(file_sector==0) begin cluster<=first_cluster; sector_in_cluster<=0; state<=DATA_ISSUE; end
   else if(have_last && file_sector==last_logical+1) begin
    if(sector_in_cluster+1<sectors_per_cluster) begin sector_in_cluster<=sector_in_cluster+1; state<=DATA_ISSUE; end
    else follow_fat(MAP);
   end else begin
    // Resampling can revisit a row or seek backwards in a top-down BMP.
    // Contiguous files use the fast path above; fragmented files rewalk
    // their already preflight-validated chain from its first cluster.
    cluster<=first_cluster;seek_left<=file_sector>>cluster_shift;state<=SEEK;
   end
  end
 end
 READ: begin
  timer<=timer+1;
  if(sd_valid) begin
   if(received<512) begin
    received<=received+1;
    if(received<64)header_data[received[5:0]]<=sd_data;
    if(received>=446 && received<510)partition_data[received-446]<=sd_data;
    if(received==510)sig_low<=sd_data;if(received==511)sig_high<=sd_data;
   end
   else fail(8);
  end
  if(sd_end) begin
   sd_req<=0;
   if(received+(sd_valid?1:0)!=512) fail(8);
   else begin
    if(after_read==DIR)state<=DIR_LOAD;
    else if(after_read==FAT)state<=FAT_LOAD;
    else if(after_read==SEND)state<=SEND_ADDR;
    else state<=after_read;
    if(after_read==FAT) begin fat_cache_valid<=1; fat_cache_sector<=cluster[31:7]; end
   end
  end else if(timer>=TIMEOUT_CYCLES-1) fail(8);
 end
 MBR: begin
  // Separate the four-way partition mux from validation and SD request enables.
  partition_lba_q<=partition32(po+8);partition_size<=partition32(po+12);
  mbr_signature_ok<=le16(510)==16'haa55;
  mbr_superfloppy<=le16(11)==512 && header_data[16]!=0 && le16(17)==0 && le16(22)==0;
  mbr_type_ok<=partition_data[po+4]==8'h0b || partition_data[po+4]==8'h0c;
  state<=MBR_CHECK;
 end
 MBR_CHECK: begin
  if(!mbr_signature_ok) fail(1);
  else if(mbr_superfloppy) state<=BOOT;
  else if(mbr_type_ok && partition_lba_q!=0 && partition_size!=0) begin
   volume_start<=partition_lba_q; is_partition<=1; read_sector(partition_lba_q,BOOT);
  end else if(partition==3) fail(1);
  else begin partition<=partition+1;state<=MBR;end
 end
 BOOT: begin
  // 拆开BPB检查与参数写入，避免多级宽位算术直接控制大量寄存器使能。
  boot_fields_ok<=!(le16(510)!=16'haa55 || le16(11)!=512 || le16(17)!=0 || le16(19)!=0 || le16(22)!=0 || le16(42)!=0 ||
     b_reserved==0 || (header_data[16]!=1 && header_data[16]!=2) || b_fatsz==0 || b_total==0 ||
     header_data[13]==0 || header_data[13]>128 || ((header_data[13] & (header_data[13]-1))!=0));
  boot_geometry_ok<=!(overhead>=b_total || volume_end[32] || (is_partition && b_total>partition_size));
  boot_flags_ok<=!(b_flags[7] && b_flags[3:0]>=header_data[16]);
  state<=BOOT_APPLY;
 end
 BOOT_APPLY: begin
  if(!boot_fields_ok || !boot_geometry_ok || !boot_flags_ok) fail(2);
  else begin
   volume_size<=b_total; fat_size<=b_fatsz; sectors_per_cluster<=header_data[13];
   fat_start<=volume_start+b_reserved+((b_flags[7] && b_flags[3:0]==1)?b_fatsz:0);
   data_start<=volume_start+overhead[31:0]; cluster<=b_root;
   case(header_data[13])
   1:cluster_shift<=0; 2:cluster_shift<=1; 4:cluster_shift<=2; 8:cluster_shift<=3;
   16:cluster_shift<=4; 32:cluster_shift<=5; 64:cluster_shift<=6; 128:cluster_shift<=7;
   endcase
   state<=GEOM;
  end
 end
 GEOM: begin
  // 使用已锁存参数，FAT32类型由数据簇数判定，不信任卷标字符串。
  cluster_count<=(volume_size-(data_start-volume_start))>>cluster_shift;
  state<=DIR_NEXT; sector_in_cluster<=0; dir_sectors<=0;
 end
 DIR_NEXT: begin
  // Validate separately from the wide SD-address register enables.
  data_lba_q<=data_lba;
  if(cluster_count<65525 || cluster_count>32'h0fffffee || ({7'd0,fat_size}<<7)<cluster_count+2 || !good_cluster(cluster))dir_error<=2;
  else if(dir_sectors>=MAX_DIR_SECTORS)dir_error<=5;
  else dir_error<=0;
  state<=DIR_ISSUE;
 end
 DIR_ISSUE:begin
  if(dir_error!=0)fail(dir_error);
  else begin
   dir_sectors<=dir_sectors+1; entry_offset<=0;
   read_sector(data_lba_q[31:0],DIR);
  end
 end
 DIR: begin
  // AUDIO.IDX is one sector and must be discovered after the four images too.
  if(SCAN_AUDIO_INDEX && window_data[0]=="A" && window_data[1]=="U" && window_data[2]=="D" &&
     window_data[3]=="I" && window_data[4]=="O" && window_data[5]==" " && window_data[6]==" " && window_data[7]==" " &&
     window_data[8]=="I" && window_data[9]=="D" && window_data[10]=="X" && (window_data[11]&8'h18)==0 &&
     entry_size==512 && good_cluster(entry_cluster))begin
   audio_index_valid<=1;audio_index_lba<=data_start+((entry_cluster-2)<<cluster_shift);
  end
  // 目录缓存选择与簇号/长度校验隔一拍，缩短50MHz关键路径。
  entry_cluster_q<=entry_cluster; entry_size_q<=entry_size;
  entry_empty_q<=window_data[0]==0;
  entry_bmp_q<=(!HD_FILES_ONLY || (window_data[0]|8'h20)==8'h68) && window_data[0]!=8'he5 && (window_data[11]&8'h18)==0 &&
      (window_data[8]|8'h20)==8'h62 && (window_data[9]|8'h20)==8'h6d && (window_data[10]|8'h20)==8'h70;
  state<=DIR_CHECK;
 end
 DIR_CHECK: begin
  state<=DIR_LOAD;
  if(entry_empty_q) begin mount_done<=1; state<=IDLE; end
  else begin
   if(entry_bmp_q && found_count<4 && good_cluster(entry_cluster_q) && entry_size_q>=54 && entry_size_q<=32'd16777216) begin
    files_cluster[found_count[1:0]]<=entry_cluster_q; files_size[found_count[1:0]]<=entry_size_q;
    found_valid<=1; found_handle<={29'd0,found_count}; found_count<=found_count+1;
    if(found_count==3 && !SCAN_AUDIO_INDEX) begin mount_done<=1; state<=IDLE; end
    else if(entry_offset==480) begin
     if(sector_in_cluster+1<sectors_per_cluster) begin sector_in_cluster<=sector_in_cluster+1; state<=DIR_NEXT; end
     else follow_fat(DIR_NEXT);
    end else entry_offset<=entry_offset+32;
   end else if(entry_offset==480) begin
    if(sector_in_cluster+1<sectors_per_cluster) begin sector_in_cluster<=sector_in_cluster+1; state<=DIR_NEXT; end
    else follow_fat(DIR_NEXT);
   end else entry_offset<=entry_offset+32;
  end
 end
 FAT_ISSUE: begin
  fat_offset<={cluster[6:0],2'b00};
  if(fat_cache_valid && fat_cache_sector==cluster[31:7]) state<=FAT_LOAD;
  else read_sector(fat_start+(cluster>>7),FAT);
 end
 FAT: begin
  if(after_fat==PREFLIGHT) begin
   if(chain_left==1) begin
    if(fat_value>=32'h0ffffff8) begin cluster<=first_cluster; sector_in_cluster<=0; have_last<=0; selected<=1; state<=IDLE; end
    else fail(6); // 长度不符或循环链
   end else if(!good_cluster(fat_value)) fail(6);
   else begin
    if(fat_value!=cluster+1)selected_contiguous<=0;
    cluster<=fat_value; chain_left<=chain_left-1; follow_fat(PREFLIGHT);
   end
  end else if(after_fat==DIR_NEXT && fat_value>=32'h0ffffff8) begin mount_done<=1; state<=IDLE; end
  else if(!good_cluster(fat_value)) fail(6);
  else begin cluster<=fat_value; sector_in_cluster<=0; state<=after_fat; end
 end
 OPEN: begin chain_left<=file_clusters; follow_fat(PREFLIGHT); end
 MAP: state<=DATA_ISSUE;
 SEEK: begin
  if(seek_left==0)begin sector_in_cluster<=file_sector&({24'd0,sectors_per_cluster}-1'b1);state<=DATA_ISSUE;end
  else begin seek_left<=seek_left-1'b1;follow_fat(SEEK);end
 end
 DATA_ISSUE: begin
  // Break cluster shift + LBA addition + volume comparison into two cycles.
  data_lba_q<=data_lba;data_cluster_valid<=good_cluster(cluster);state<=DATA_CHECK;
 end
 DATA_CHECK: begin
  if(!data_cluster_valid || data_lba_q[32] || data_lba_q>=({1'b0,volume_start}+volume_size)) fail(6);
  else begin send_idx<=0; read_sector(data_lba_q[31:0],SEND); end
 end
 DIR_LOAD: load_window(entry_offset,32,DIR);
 FAT_LOAD: load_window(fat_offset,4,FAT);
 WIN_WAIT: state<=WIN_GET;
 WIN_GET: begin
  window_data[window_index[4:0]]<=sector_q;
  if(window_index+1==window_length)state<=window_return;
  else begin window_index<=window_index+1;ram_read_addr<=window_base+window_index+1;state<=WIN_WAIT;end
 end
 SEND_ADDR: begin ram_read_addr<=send_idx;state<=SEND_WAIT;end
 SEND_WAIT: state<=SEND;
 SEND: begin
  // sector_q and its RAM address stay stable while the scaler emits
  // repeated pixels. Default mode preserves the legacy pulsed stream.
  if(!FILE_BACKPRESSURE || file_ready)begin
   file_data<=sector_q; file_valid<=1;
   if(send_idx==511) begin last_logical<=file_sector; have_last<=1; state<=RELEASE; end
   else begin send_idx<=send_idx+1;state<=SEND_ADDR;end
  end
 end
 RELEASE: begin
  if(file_valid) file_end<=1;
  else if(!file_req) state<=IDLE;
 end
 FAIL: begin sd_req<=0; selected<=0; end
 default: fail(15);
 endcase
 end
end
endmodule

