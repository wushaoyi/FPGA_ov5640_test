

`timescale 1ns/1ps
module frame_fifo_write
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter ADDR_BITS              = 23,
	parameter BUSRT_BITS             = 10,
	parameter BURST_SIZE             = 128
)               
(
	input                            rst,                  
	input                            mem_clk,                    // 外部存储器控制器用户界面时钟
	output reg                       wr_burst_req,               // 向外部存储器控制器发出突发写请求
	output reg[BUSRT_BITS - 1:0]     wr_burst_len,               // 对外部存储器控制器来说，突发写请求的数据长度，不是字节 
	output reg[ADDR_BITS - 1:0]      wr_burst_addr,              // 到外部存储器控制器，突发写请求的基址
	input                            wr_burst_data_req,          // 从外部存储器控制器，写入数据请求，之前的数据1时钟 
	input                            wr_burst_finish,            // 从外部存储器控制器，突发写入完成
	input                            write_req,                  // 数据写模块写请求，保持'1'直到read_req_ack = '1''
	output reg                       write_req_ack,              // 数据写模块写请求响应
	output                           write_finish,               // 数据写模块写请求完成
	input[ADDR_BITS - 1:0]           write_addr_0,               // 数据写模块写请求基址0，当write_addr_index = 0时使用
	input[ADDR_BITS - 1:0]           write_addr_1,               // 数据写模块写请求基址1，当write_addr_index = 1时使用
	input[ADDR_BITS - 1:0]           write_addr_2,               // 数据写模块写请求基址1，当write_addr_index = 2时使用
	input[ADDR_BITS - 1:0]           write_addr_3,               // 数据写模块写请求基址1，当write_addr_index = 3时使用
	input[1:0]                       write_addr_index,           // 从write_addr_0 write_addr_1 write_addr_2 write_addr_3中选择有效的base地址
	input[ADDR_BITS - 1:0]           write_len,                  // 数据写模块写请求数据长度
	output reg                       fifo_aclr,                  // fifo异步清除
	input[15:0]                      rdusedw                     // 从fifo读出使用过的单词
);
localparam ONE                       = 256'd1;                   //256位'1'可以用ONE[n-1:0]表示n位'1'
localparam ZERO                      = 256'd0;                   //256位'0'
//编写状态机代码
localparam S_IDLE                    = 0;                        //空闲状态，等待写
localparam S_ACK                     = 1;                        //书面请求回应
localparam S_CHECK_FIFO              = 2;                        //检查FIFO状态，确保有足够的空间来突发写入
localparam S_WRITE_BURST             = 3;                        //开始突发写
localparam S_WRITE_BURST_END         = 4;                        //一次突发写完成
localparam S_END                     = 5;                        //一帧数据写入完成

reg                                 write_req_d0;                //异步写请求，同步到'mem_clk'时钟域，第一个节拍
reg                                 write_req_d1;                //第二个
reg                                 write_req_d2;                //第三个，你为什么需要3个?这是设计习惯
reg[ADDR_BITS - 1:0]                write_len_d0;                //异步write_len(写数据长度)，首先同步到'mem_clk'时钟域
reg[ADDR_BITS - 1:0]                write_len_d1;                //第二
reg[ADDR_BITS - 1:0]                write_len_latch;             //锁写数据长度
reg[ADDR_BITS - 1:0]                write_cnt;                   //写数据计数器
reg[1:0]                            write_addr_index_d0;
reg[1:0]                            write_addr_index_d1;
reg[3:0]                            state;                       //状态机

assign write_finish = (state == S_END) ? 1'b1 : 1'b0;            //写入结束状态'S END'
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		write_req_d0    <=  1'b0;
		write_req_d1    <=  1'b0;
		write_req_d2    <=  1'b0;
		write_len_d0    <=  ZERO[ADDR_BITS - 1:0];              //相当于 write_len_d0 <= 0;
		write_len_d1    <=  ZERO[ADDR_BITS - 1:0];              //相当于 write_len_d1 <= 0;
		write_addr_index_d0    <=  2'b00;
		write_addr_index_d1    <=  2'b00;
	end
	else
	begin
		write_req_d0    <=  write_req;
		write_req_d1    <=  write_req_d0;
		write_req_d2    <=  write_req_d1;
		write_len_d0    <=  write_len;
		write_len_d1    <=  write_len_d0;
		write_addr_index_d0 <= write_addr_index;
		write_addr_index_d1 <= write_addr_index_d0;
	end 
end


always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		state <= S_IDLE;
		write_len_latch <= ZERO[ADDR_BITS - 1:0];
		wr_burst_addr <= ZERO[ADDR_BITS - 1:0];
		wr_burst_req <= 1'b0;
		write_cnt <= ZERO[ADDR_BITS - 1:0];
		fifo_aclr <= 1'b0;
		write_req_ack <= 1'b0;
		wr_burst_len <= ZERO[BUSRT_BITS - 1:0];
	end
	else
		case(state)
			//空闲状态，等待写write_req_d2 == '1'返回'S_ACK'
			S_IDLE:
			begin
				if(write_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				write_req_ack <= 1'b0;
			end
			//'S_ACK'状态完成写请求响应、FIFO复位、地址锁存和数据长度锁存
			S_ACK:
			begin
				//写请求撤销后(write_req_d2 == '0')，转到'S_CHECK_FIFO'，write_req_ack转到'0'
				if(write_req_d2 == 1'b0)
				begin
					state <= S_CHECK_FIFO;
					fifo_aclr <= 1'b0;
					write_req_ack <= 1'b0;
				end
				else
				begin
					//写请求响应
					write_req_ack <= 1'b1;
					//FIFO复位
					fifo_aclr <= 1'b1;
					//从write_addr_0 write_addr_1 write_addr_2 write_addr_3中选择有效的base地址
					if(write_addr_index_d1 == 2'd0)
						wr_burst_addr <= write_addr_0;
					else if(write_addr_index_d1 == 2'd1)
						wr_burst_addr <= write_addr_1;
					else if(write_addr_index_d1 == 2'd2)
						wr_burst_addr <= write_addr_2;
					else if(write_addr_index_d1 == 2'd3)
						wr_burst_addr <= write_addr_3;
					//锁存器数据长度
					write_len_latch <= write_len_d1;                    
				end
				//写数据计数器复位，write_cnt <= 0;
				write_cnt <= ZERO[ADDR_BITS - 1:0];
			end
			S_CHECK_FIFO:
			begin
				//如果此时有写请求，则进入` S_ACK `状态
				if(write_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				//如果FIFO空间是突发写请求，则进入突发写状态
				else if(rdusedw >= BURST_SIZE)
				begin
					state <= S_WRITE_BURST;
					wr_burst_len <= BURST_SIZE[BUSRT_BITS - 1:0];
					wr_burst_req <= 1'b1;
				end
			end
			
			S_WRITE_BURST:
			begin
				//突然结束
				if(wr_burst_finish == 1'b1)
				begin
					wr_burst_req <= 1'b0;
					state <= S_WRITE_BURST_END;
					//写入计数器+突发长度
					write_cnt <= write_cnt + BURST_SIZE[ADDR_BITS - 1:0];
					//产生下一个突发写地址
					wr_burst_addr <= wr_burst_addr + BURST_SIZE[ADDR_BITS - 1:0];
				end     
			end
			S_WRITE_BURST_END:
			begin
				//如果此时有写请求，则进入` S_ACK `状态
				if(write_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				//如果写计数器的值小于帧长度，则继续写
				//否则写就完成了
				else if(write_cnt < write_len_latch)
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