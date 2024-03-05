`timescale 1ns / 1ps
module sdram_core
#
(
	parameter T_RP                    =  4,
	parameter T_RC                    =  6,
	parameter T_MRD                   =  6,
	parameter T_RCD                   =  2,
	parameter T_WR                    =  3,
	parameter CASn                    =  3,
	parameter SDR_BA_WIDTH            =  2,
	parameter SDR_ROW_WIDTH           =  13,
	parameter SDR_COL_WIDTH           =  9,
	parameter SDR_DQ_WIDTH            =  16,
	parameter SDR_DQM_WIDTH           =  SDR_DQ_WIDTH/8,
	parameter APP_ADDR_WIDTH          =  SDR_BA_WIDTH + SDR_ROW_WIDTH + SDR_COL_WIDTH,
	parameter APP_BURST_WIDTH         =  10
)
(
	input                             clk,
	input                             rst,                 //复位信号，高电平表示复位
	//write
	input                             wr_burst_req,        //  写入请求
	input[SDR_DQ_WIDTH-1:0]           wr_burst_data,       //  写入数据
	input[APP_BURST_WIDTH-1:0]        wr_burst_len,        //  提前写入数据长度wr_burst_req
	input[APP_ADDR_WIDTH-1:0]         wr_burst_addr,       //  SDRAM 写缓冲区的写基址
	output                            wr_burst_data_req,   //  提前1个时钟写入数据请求
	output                            wr_burst_finish,     //  写入数据结束
	//read
	input                             rd_burst_req,        //  读取请求
	input[APP_BURST_WIDTH-1:0]        rd_burst_len,        //  读取数据长度，提前 rd_burst_req
	input[APP_ADDR_WIDTH-1:0]         rd_burst_addr,       //  SDRAM 读取缓冲区的读取基址
	output[SDR_DQ_WIDTH-1:0]          rd_burst_data,       //  将数据读取到内部
	output                            rd_burst_data_valid, //  读取数据启用（有效）
	output                            rd_burst_finish,     //  读取数据结束
	//sdram
	output                            sdram_cke,           //时钟使能
	output                            sdram_cs_n,          //片选
	output                            sdram_ras_n,         //行选择
	output                            sdram_cas_n,         //列选择
	output                            sdram_we_n,          //写入启用
	output[SDR_BA_WIDTH-1:0]          sdram_ba,            //岸地址
	output[SDR_ROW_WIDTH-1:0]         sdram_addr,          //地址
	output[SDR_DQM_WIDTH-1:0]         sdram_dqm,           //数据掩码
	inout[SDR_DQ_WIDTH-1: 0]          sdram_dq             //数据
);

// State machine code
localparam     S_INIT_NOP  = 5'd0;       //等待上电稳定200us结束
localparam     S_INIT_PRE  = 5'd1;       //预充电状态
localparam     S_INIT_TRP  = 5'd2;       //等待预充电完成
localparam     S_INIT_AR1  = 5'd3;       //首次自我刷新
localparam     S_INIT_TRF1 = 5'd4;       //等待结束刷新后的第一次
localparam     S_INIT_AR2  = 5'd5;       //第二次自我刷新
localparam     S_INIT_TRF2 = 5'd6;       //等待结束刷新后的第二次
localparam     S_INIT_MRS  = 5'd7;       //模式寄存器集
localparam     S_INIT_TMRD = 5'd8;       //等待模式寄存器设置完成
localparam     S_INIT_DONE = 5'd9;       //初始化完成
localparam     S_IDLE      = 5'd10;      //空闲状态
localparam     S_ACTIVE    = 5'd11;      //行激活、读取和写入
localparam     S_TRCD      = 5'd12;      //行激活等待
localparam     S_READ      = 5'd13;      //读取数据状态
localparam     S_CL        = 5'd14;      //等待延迟
localparam     S_RD        = 5'd15;      //读取数据
localparam     S_WRITE     = 5'd16;      //写入数据状态
localparam     S_WD        = 5'd17;      //写入数据
localparam     S_TWR       = 5'd18;      //等待写入数据和自刷新结束
localparam     S_PRE       = 5'd19 ;     //预充电
localparam     S_TRP       = 5'd20 ;     //等待预充电完成
localparam     S_AR        = 5'd21;      //自我刷新
localparam     S_TRFC      = 5'd22;      //等待自刷新

reg                         read_flag;
wire                        done_200us;        //上电后，200us输入稳定在标志位末端
reg                         sdram_ref_req;     // SDRAM 自刷新请求信号
wire                        sdram_ref_ack;     // SDRAM 自刷新请求响应信号
reg[SDR_BA_WIDTH-1:0]       sdram_ba_r;
reg[SDR_ROW_WIDTH-1:0]      sdram_addr_r;
reg                         ras_n_r;
reg                         cas_n_r;
reg                         we_n_r;
wire[APP_ADDR_WIDTH-1:0]    sys_addr;
reg[14:0]                   cnt_200us;
reg[10:0]                   cnt_7p5us;
reg[SDR_DQ_WIDTH-1:0]       sdr_dq_out;
reg[SDR_DQ_WIDTH-1:0]       sdr_dq_in;
reg                         sdr_dq_oe;
reg[9:0]                    cnt_clk_r; //时钟计数
reg                         cnt_rst_n; //时钟计数复位信号
reg[4:0]                    state;
reg                         wr_burst_data_req_d0;
reg                         wr_burst_data_req_d1;
reg                         rd_burst_data_valid_d0;
reg                         rd_burst_data_valid_d1;

wire end_trp       =  (cnt_clk_r   == T_RP) ? 1'b1 : 1'b0;
wire end_trfc      =  (cnt_clk_r   == T_RC) ? 1'b1 : 1'b0;
wire end_tmrd      =  (cnt_clk_r   == T_MRD) ? 1'b1 : 1'b0;
wire end_trcd      =  (cnt_clk_r   == T_RCD-1) ? 1'b1 : 1'b0;
wire end_tcl       =  (cnt_clk_r   == CASn-1) ? 1'b1 : 1'b0;
wire end_rdburst   =  (cnt_clk_r   == rd_burst_len-4) ? 1'b1 : 1'b0;
wire end_tread     =  (cnt_clk_r   == rd_burst_len+2) ? 1'b1 : 1'b0;
wire end_wrburst   =  (cnt_clk_r   == wr_burst_len-1) ? 1'b1 : 1'b0;
wire end_twrite    =  (cnt_clk_r   == wr_burst_len-1) ? 1'b1 : 1'b0;
wire end_twr       =  (cnt_clk_r   == T_WR) ? 1'b1 : 1'b0;


always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		wr_burst_data_req_d0 <= 1'b0;
		wr_burst_data_req_d1 <= 1'b0;
		rd_burst_data_valid_d0 <= 1'b0;
		rd_burst_data_valid_d1 <= 1'b0;
	end
	else
	begin
		wr_burst_data_req_d0 <= wr_burst_data_req;
		wr_burst_data_req_d1 <= wr_burst_data_req_d0;
		rd_burst_data_valid_d0 <= rd_burst_data_valid;
		rd_burst_data_valid_d1 <= rd_burst_data_valid_d0;
	end
end

assign wr_burst_finish = ~wr_burst_data_req_d0 & wr_burst_data_req_d1;
assign rd_burst_finish = ~rd_burst_data_valid_d0 & rd_burst_data_valid_d1;
assign rd_burst_data = sdr_dq_in;

assign sdram_dqm = {SDR_DQM_WIDTH{1'b0}};
assign sdram_dq = sdr_dq_oe ? sdr_dq_out : {SDR_DQ_WIDTH{1'bz}};
assign sdram_cke = 1'b1;
assign sdram_cs_n = 1'b0;
assign sdram_ba = sdram_ba_r;
assign sdram_addr = sdram_addr_r;
assign {sdram_ras_n,sdram_cas_n,sdram_we_n} = {ras_n_r,cas_n_r,we_n_r};
assign sys_addr = read_flag ? rd_burst_addr:wr_burst_addr;        //读/写地址总线切换控制
// 上电 200us 时间，done_200us=1
always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		cnt_200us <= 15'd0;
	else if(cnt_200us < 15'd20_000)
		cnt_200us <= cnt_200us + 1'b1; 
end

assign done_200us = (cnt_200us == 15'd20_000);

//------------------------------------------------------------------------------
//7.5uS 定时器，每 8192 行 64ms 存储一次，用于自动刷新
//------------------------------------------------------------------------------
always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		cnt_7p5us <= 11'd0;
	else if(cnt_7p5us < 11'd750)
		cnt_7p5us <= cnt_7p5us+1'b1;
	else
		cnt_7p5us <= 11'd0;
end

always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		sdram_ref_req <= 1'b0;
	else if(cnt_7p5us == 11'd749)
		sdram_ref_req <= 1'b1;   
	else if(sdram_ref_ack)
		sdram_ref_req <= 1'b0; 
end
//SDRAM 状态机
always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		state <= S_INIT_NOP;
	else
		begin
			case (state)
				S_INIT_NOP:
					state <= done_200us ? S_INIT_PRE : S_INIT_NOP;     //200us结束后/复位进入下一个状态
				S_INIT_PRE:
					state <= S_INIT_TRP;     //预充电状态
				S_INIT_TRP:
					state <= (end_trp) ? S_INIT_AR1 : S_INIT_TRP;         //预充电，等待T_RP时钟周期
				S_INIT_AR1:
					state <= S_INIT_TRF1;    //首次自我刷新
				S_INIT_TRF1:
					state <= (end_trfc) ? S_INIT_AR2 : S_INIT_TRF1;           //等待第一次自刷新结束，T_RC时钟周期
				S_INIT_AR2:
					state <= S_INIT_TRF2;    //第二次自刷新
				S_INIT_TRF2:
					state <= (end_trfc) ?  S_INIT_MRS : S_INIT_TRF2;       //等待第二个自刷新结束T_RC时钟周期
				S_INIT_MRS:
					state <= S_INIT_TMRD;//模式寄存器集（MRS）
				S_INIT_TMRD:
					state <= (end_tmrd) ? S_INIT_DONE : S_INIT_TMRD;      //等待模式寄存器设置完成，具有T_MRD时钟周期
				S_INIT_DONE:
					state <= S_IDLE;        // SDRAM 初始化设置完成标志
				S_IDLE:
					if(sdram_ref_req)
						begin
						state <= S_AR;      //自刷新请求的时机
						read_flag <= 1'b1;
						end
					else if(wr_burst_req)
						begin
						state <= S_ACTIVE;  //写入 SDRAM
						read_flag <= 1'b0;
						end
					else if(rd_burst_req)
						begin
						state <= S_ACTIVE;  //读取 SDRAM
						read_flag <= 1'b1;
						end
					else
						begin
						state <= S_IDLE;
						read_flag <= 1'b1;
						end
				//行活动
				S_ACTIVE:
					if(T_RCD == 0)
						 if(read_flag) state <= S_READ;
						 else state <= S_WRITE;
					else state <= S_TRCD;
				//行活动等待
				S_TRCD:
					if(end_trcd)
						 if(read_flag) state <= S_READ;
						 else state <= S_WRITE;
					else state <= S_TRCD;
				//读取数据 
				S_READ:
					state <= S_CL;
				//读取数据等待
				S_CL:
					state <= (end_tcl) ? S_RD : S_CL;
				//读取数据
				S_RD:
					state <= (end_tread) ? S_PRE : S_RD;
				//写入数据状态
				S_WRITE:
					state <= S_WD;
				//写入数据
				S_WD:
					state <= (end_twrite) ? S_TWR : S_WD;
				//等待写入数据并以自我刷新结束
				S_TWR:
					state <= (end_twr) ? S_PRE : S_TWR;
				//手动预充电
				S_PRE:
				    state <= S_TRP ;
				//预充电后等待
				S_TRP:
				    state <= (end_trp) ? S_IDLE : S_TRP ;
				//自刷新
				S_AR:
					state <= S_TRFC;
				//自刷新等待
				S_TRFC:
					state <= (end_trfc) ? S_IDLE : S_TRFC;
				default:
					state <= S_INIT_NOP;
			endcase
		end
end

assign sdram_ref_ack = (state == S_AR);// SDRAM 自刷新响应信号

//提前写 1 个时钟
assign wr_burst_data_req = ((state == S_TRCD) & ~read_flag) | (state == S_WRITE)|((state == S_WD) & (cnt_clk_r < wr_burst_len - 2'd2));
//读取 SDRAM 响应信号
assign rd_burst_data_valid = (state == S_RD) & (cnt_clk_r >= 10'd1) & (cnt_clk_r < rd_burst_len + 2'd1);

//生成 SDRAM 顺序操作的时间延迟
always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		cnt_clk_r <= 10'd0;         
	else if(!cnt_rst_n)
		cnt_clk_r <= 10'd0;  
	else
		cnt_clk_r <= cnt_clk_r+1'b1;
end

//计数器控制逻辑
always@(*) 
begin
	case (state)
		S_INIT_NOP: cnt_rst_n <= 1'b0;
		S_INIT_PRE: cnt_rst_n <= 1'b1;                   //预充电延迟计数开始
		S_INIT_TRP: cnt_rst_n <= (end_trp) ? 1'b0:1'b1;  //等到预充电延迟计数结束并且计数器被清除
		S_INIT_AR1,S_INIT_AR2:cnt_rst_n <= 1'b1;          //自刷新计数开始
		S_INIT_TRF1,S_INIT_TRF2:cnt_rst_n <= (end_trfc) ? 1'b0:1'b1;   //等到刷新计数完成，并且计数器被清除
		S_INIT_MRS: cnt_rst_n <= 1'b1;          //模式寄存器设置，时间计数开始
		S_INIT_TMRD: cnt_rst_n <= (end_tmrd) ? 1'b0:1'b1;   //等到刷新计数完成，并且计数器被清除
		S_IDLE:    cnt_rst_n <= 1'b0;
		S_ACTIVE:  cnt_rst_n <= 1'b1;
		S_TRCD:    cnt_rst_n <= (end_trcd) ? 1'b0:1'b1;
		S_CL:      cnt_rst_n <= (end_tcl) ? 1'b0:1'b1;
		S_RD:      cnt_rst_n <= (end_tread) ? 1'b0:1'b1;
		S_WD:      cnt_rst_n <= (end_twrite) ? 1'b0:1'b1;
		S_TWR:     cnt_rst_n <= (end_twr) ? 1'b0:1'b1;
		S_TRP:     cnt_rst_n <= (end_trp) ? 1'b0:1'b1;
		S_TRFC:    cnt_rst_n <= (end_trfc) ? 1'b0:1'b1;
		default:   cnt_rst_n <= 1'b0;
	endcase
end

always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		sdr_dq_out <= 16'd0; 
	else if((state == S_WRITE) | (state == S_WD))
		sdr_dq_out <= wr_burst_data; 
end
//双向数据方向控制逻辑
always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		sdr_dq_oe <= 1'b0;
	else if((state == S_WRITE) | (state == S_WD))
		sdr_dq_oe <= 1'b1;
	else
		sdr_dq_oe <= 1'b0;
end

//从 SDRAM 读取数据
always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		sdr_dq_in <= 16'd0;
	else if(state == S_RD)
		sdr_dq_in <= sdram_dq;
end

always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1) 
	begin
		{ras_n_r,cas_n_r,we_n_r} <= 3'b111;
		sdram_ba_r <= {SDR_BA_WIDTH{1'b1}};
		sdram_addr_r <= {SDR_ROW_WIDTH{1'b1}};
	end
	else
		case(state)
			S_INIT_NOP,S_INIT_TRP,S_INIT_TRF1,S_INIT_TRF2,S_INIT_TMRD: 
			begin
				{ras_n_r,cas_n_r,we_n_r} <= 3'b111;
				sdram_ba_r <= {SDR_BA_WIDTH{1'b1}};
				sdram_addr_r <= {SDR_ROW_WIDTH{1'b1}};
			end
			S_INIT_PRE: 
			begin
				{ras_n_r,cas_n_r,we_n_r} <= 3'b010;
				sdram_ba_r <= {SDR_BA_WIDTH{1'b1}};
				sdram_addr_r <= {SDR_ROW_WIDTH{1'b1}};
			end
			S_INIT_AR1,S_INIT_AR2: 
			begin
				{ras_n_r,cas_n_r,we_n_r} <= 3'b001;
				sdram_ba_r <= {SDR_BA_WIDTH{1'b1}};
				sdram_addr_r <= {SDR_ROW_WIDTH{1'b1}};
			end
			S_INIT_MRS:
			begin   //模式寄存器设置，可根据实际需要进行设置
				{ras_n_r,cas_n_r,we_n_r} <= 3'b000;
				sdram_ba_r <= {SDR_BA_WIDTH{1'b0}};  
				sdram_addr_r <= {
					3'b000,
					1'b0,           //操作模式设置（此处设置为 A9=0，即突发读取/突发写入）
					2'b00,          //操作模式设置（{A8，A7}=00），当前操作设置为模式寄存器
					3'b011,         //CAS 延迟设置
					1'b0,           //突发模式
					3'b111          //连拍长度，整页
					};
			end
			S_IDLE,S_TRCD,S_CL,S_TRFC,S_TWR,S_TRP: 
			begin
				{ras_n_r,cas_n_r,we_n_r} <= 3'b111;
				sdram_ba_r <= {SDR_BA_WIDTH{1'b1}};
				sdram_addr_r <= {SDR_ROW_WIDTH{1'b1}};
			end
			S_ACTIVE: 
			begin
				{ras_n_r,cas_n_r,we_n_r} <= 3'b011;
				sdram_ba_r <= sys_addr[APP_ADDR_WIDTH - 1:APP_ADDR_WIDTH - SDR_BA_WIDTH];  
				sdram_addr_r <= sys_addr[SDR_COL_WIDTH + SDR_ROW_WIDTH - 1:SDR_COL_WIDTH]; 
			end
			S_READ: 
			begin
				{ras_n_r,cas_n_r,we_n_r} <= 3'b101;
				sdram_ba_r <= sys_addr[APP_ADDR_WIDTH - 1:APP_ADDR_WIDTH - SDR_BA_WIDTH];  
				sdram_addr_r <= {4'b0000,sys_addr[8:0]};//列地址 A10=0，设置读取启用，无自动预充电
			end
			S_RD: 
			begin
				if(end_rdburst)
					{ras_n_r,cas_n_r,we_n_r} <= 3'b110;
				else begin
					{ras_n_r,cas_n_r,we_n_r} <= 3'b111;
					sdram_ba_r <= {SDR_BA_WIDTH{1'b1}};
					sdram_addr_r <= {SDR_ROW_WIDTH{1'b1}};
				end
			end
			S_WRITE: 
			begin
				{ras_n_r,cas_n_r,we_n_r} <= 3'b100;
				sdram_ba_r <= sys_addr[APP_ADDR_WIDTH - 1:APP_ADDR_WIDTH - SDR_BA_WIDTH];  
				sdram_addr_r <= {4'b0000,sys_addr[8:0]};//列地址 A10=0，设置写启用，无自动预充
			end
			S_WD: 
			begin
				if(end_wrburst) {ras_n_r,cas_n_r,we_n_r} <= 3'b110;
				else begin
					{ras_n_r,cas_n_r,we_n_r} <= 3'b111;
					sdram_ba_r <= {SDR_BA_WIDTH{1'b1}};
					sdram_addr_r <= {SDR_ROW_WIDTH{1'b1}};
				end
			end
			S_PRE: 
			begin
				{ras_n_r,cas_n_r,we_n_r} <= 3'b010;
				sdram_ba_r <= {SDR_BA_WIDTH{1'b1}};
				sdram_addr_r <= {SDR_ROW_WIDTH{1'b1}};
			end
			S_AR: 
			begin
				{ras_n_r,cas_n_r,we_n_r} <= 3'b001;
				sdram_ba_r <= {SDR_BA_WIDTH{1'b1}};
				sdram_addr_r <= {SDR_ROW_WIDTH{1'b1}};
			end
			default: 
			begin
				{ras_n_r,cas_n_r,we_n_r} <= 3'b111;
				sdram_ba_r <= {SDR_BA_WIDTH{1'b1}};
				sdram_addr_r <= {SDR_ROW_WIDTH{1'b1}};
			end
		endcase
end

endmodule

