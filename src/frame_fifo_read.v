
`timescale 1ns/1ps
module frame_fifo_read
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter ADDR_BITS              = 23,
	parameter BUSRT_BITS             = 10,
	parameter FIFO_DEPTH             = 256,
	parameter BURST_SIZE             = 128
)               
(
	input                            rst,                  
	input                            mem_clk,                    // 外部存储器控制器用户界面时钟
	output reg                       rd_burst_req,               // 向外部存储器控制器发送突发读取请求  
	output reg[BUSRT_BITS - 1:0]     rd_burst_len,               // 对于外部存储器控制器，突发读取请求的数据长度，不是字节 
	output reg[ADDR_BITS - 1:0]      rd_burst_addr,              // 到外部存储器控制器，突发读请求的基址
	input                            rd_burst_data_valid,        // 从外部存储器控制器，读取请求数据有效    
	input                            rd_burst_finish,            // 从外部存储器控制器，突发读取完成
	input                            read_req,                   // 数据读取模块读取请求，保持'1'直到read_req_ack = '1
	output reg                       read_req_ack,               // 数据读取模块读取请求响应
	output                           read_finish,                // 数据读取模块读取请求完成
	input[ADDR_BITS - 1:0]           read_addr_0,                // 数据读取模块读请求的基址为0，当read_addr_index = 0时使用
	input[ADDR_BITS - 1:0]           read_addr_1,                // 数据读取模块读请求的基址为1，当read_addr_index = 1时使用
	input[ADDR_BITS - 1:0]           read_addr_2,                // 数据读取模块读请求的基址为1，当read_addr_index = 2时使用
	input[ADDR_BITS - 1:0]           read_addr_3,                // 数据读取模块读请求的基址为1，当read_addr_index = 3时使用
	input[1:0]                       read_addr_index,            // 从read_addr_0 read_addr_1 read_addr_2 read_addr_3中选择有效的基址
	input[ADDR_BITS - 1:0]           read_len,                   // 数据读取模块读取请求的数据长度
	output reg                       fifo_aclr,                  // 要fifo异步清除
	input[15:0]                      wrusedw                     // 从fifo写用过的词
);
localparam ONE                       = 256'd1;                   //256位'1'可以用ONE[n-1:0]表示n位'1'
localparam ZERO                      = 256'd0;                   //256位'0'
//读取状态机代码
localparam S_IDLE                    = 0;                        //空闲状态，等待读取帧
localparam S_ACK                     = 1;                        //读请求响应
localparam S_CHECK_FIFO              = 2;                        //检查FIFO状态，确保有足够的空间进行突发读取
localparam S_READ_BURST              = 3;                        //开始快速阅读
localparam S_READ_BURST_END          = 4;                        //一次突发读取完成
localparam S_END                     = 5;                        //读取一帧数据以完成


reg                                  read_req_d0;                //异步读请求，同步到'mem_clk'时钟域，第一个节拍
reg                                  read_req_d1;                //第二个
reg                                  read_req_d2;                //第三个，你为什么需要3个?这是设计习惯
reg[ADDR_BITS - 1:0]                 read_len_d0;                //异步read_len(读取数据长度)，首先同步到'mem_clk'时钟域
reg[ADDR_BITS - 1:0]                 read_len_d1;                //第二个
reg[ADDR_BITS - 1:0]                 read_len_latch;             //锁定读数据长度
reg[ADDR_BITS - 1:0]                 read_cnt;                   //读数据计数器
reg[3:0]                             state;                      //状态机
reg[1:0]                             read_addr_index_d0;         //首先同步到'mem clock '时钟域
reg[1:0]                             read_addr_index_d1;         //其次同步到'mem clk'时钟域

assign read_finish = (state == S_END) ? 1'b1 : 1'b0;             //读取结束状态'S END'
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		read_req_d0    <=  1'b0;
		read_req_d1    <=  1'b0;
		read_req_d2    <=  1'b0;
		read_len_d0    <=  ZERO[ADDR_BITS - 1:0];               //相当于read_len_d0 <= 0;
		read_len_d1    <=  ZERO[ADDR_BITS - 1:0];               //相当于read_len_d1 <= 0;
		read_addr_index_d0 <= 2'b00;
		read_addr_index_d1 <= 2'b00;
	end
	else
	begin
		read_req_d0    <=  read_req;
		read_req_d1    <=  read_req_d0;
		read_req_d2    <=  read_req_d1;     
		read_len_d0    <=  read_len;
		read_len_d1    <=  read_len_d0; 
		read_addr_index_d0 <= read_addr_index;
		read_addr_index_d1 <= read_addr_index_d0;
	end 
end


always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		state <= S_IDLE;
		read_len_latch <= ZERO[ADDR_BITS - 1:0];
		rd_burst_addr <= ZERO[ADDR_BITS - 1:0];
		rd_burst_req <= 1'b0;
		read_cnt <= ZERO[ADDR_BITS - 1:0];
		fifo_aclr <= 1'b0;
		rd_burst_len <= ZERO[BUSRT_BITS - 1:0];
		read_req_ack <= 1'b0;
	end
	else
		case(state)
			//空闲状态，等待读取，read_req_d2 == '1'转到'S_ACK'
			S_IDLE:
			begin
				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				read_req_ack <= 1'b0;
			end
			//'S_ACK'状态完成读请求响应、FIFO复位、地址锁存和数据长度锁存
			S_ACK:
			begin
				if(read_req_d2 == 1'b0)
				begin
					state <= S_CHECK_FIFO;
					fifo_aclr <= 1'b0;
					read_req_ack <= 1'b0;
				end
				else
				begin
					//读请求响应
					read_req_ack <= 1'b1;
					//FIFO 复位
					fifo_aclr <= 1'b1;
					//从read_addr_0 read_addr_1 read_addr_2 read_addr_3中选择有效的基址
					if(read_addr_index_d1 == 2'd0)
						rd_burst_addr <= read_addr_0;
					else if(read_addr_index_d1 == 2'd1)
						rd_burst_addr <= read_addr_1;
					else if(read_addr_index_d1 == 2'd2)
						rd_burst_addr <= read_addr_2;
					else if(read_addr_index_d1 == 2'd3)
						rd_burst_addr <= read_addr_3;
					//锁存数据长度

					read_len_latch <= read_len_d1;
				end
				//读数据计数器复位， read_cnt <= 0;
				read_cnt <= ZERO[ADDR_BITS - 1:0];
			end
			S_CHECK_FIFO:
			begin
				//如果此时有读请求，则进入“S_ACK”状态
				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				//如果FIFO空间是突发读请求，则进入突发读状态
				else if(wrusedw < (FIFO_DEPTH - BURST_SIZE))
				begin
					state <= S_READ_BURST;
					rd_burst_len <= BURST_SIZE[BUSRT_BITS - 1:0];
					rd_burst_req <= 1'b1;
				end
			end
			
			S_READ_BURST:
			begin
				if(rd_burst_data_valid)
					rd_burst_req <= 1'b0;
				//突然结束
 
				if(rd_burst_finish == 1'b1)
				begin
					state <= S_READ_BURST_END;
					//读取计数器+突发长度
					read_cnt <= read_cnt + BURST_SIZE[ADDR_BITS - 1:0];
					//生成下一个突发读地址
					rd_burst_addr <= rd_burst_addr + BURST_SIZE[ADDR_BITS - 1:0];
				end     
			end
			S_READ_BURST_END:
			begin
				//如果此时有读请求，则进入“S_ACK”状态
				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				//如果读取计数器的值小于帧长，则继续读取;
				//否则，读取完成
				else if(read_cnt < read_len_latch)
				begin
					state <= S_CHECK_FIFO;
				end
				else
				begin
					state <= S_END;
				end
			end
			S_END:
			begin
				state <= S_IDLE;
			end
			default:
				state <= S_IDLE;
		endcase
end
endmodule