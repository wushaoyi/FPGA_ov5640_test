

`timescale 1ns/1ps
module frame_read_write
#
(
	parameter MEM_DATA_BITS          = 16,
	parameter READ_DATA_BITS         = 16,
	parameter WRITE_DATA_BITS        = 16,
	parameter ADDR_BITS              = 24,
	parameter BUSRT_BITS             = 10,
	parameter BURST_SIZE             = 256
)               
(
	input                            rst,                  
	input                            mem_clk,                    // 外部存储器控制器用户界面时钟
	output                           rd_burst_req,               // 到外部存储器控制器，发出突发读取请求
	output[BUSRT_BITS - 1:0]         rd_burst_len,               // 到外部存储器控制器，数据长度为突发读取请求，而不是字节
	output[ADDR_BITS - 1:0]          rd_burst_addr,              // 到外部存储器控制器，突发读取请求的基址
	input                            rd_burst_data_valid,        // 从外部存储器控制器，读取数据有效 
	input[MEM_DATA_BITS - 1:0]       rd_burst_data,              // 从外部存储器控制器，读取请求数据
	input                            rd_burst_finish,            // 从外部存储器控制器，突发读取完成
	input                            read_clk,                   // 数据读取模块时钟
	input                            read_req,                   // 数据读取模块读取请求，保持 '1' 直到 read_req_ack = '1'
	output                           read_req_ack,               // 数据读取模块读取请求响应
	output                           read_finish,                // 数据读取模块读取请求完成
	input[ADDR_BITS - 1:0]           read_addr_0,                // 数据读取模块读取请求基址 0，当 read_addr_index = 0 时使用
	input[ADDR_BITS - 1:0]           read_addr_1,                // 数据读取模块读取请求基址 1，当 read_addr_index = 1 时使用
	input[ADDR_BITS - 1:0]           read_addr_2,                // 数据读取模块读取请求基址 1，当 read_addr_index = 2 时使用
	input[ADDR_BITS - 1:0]           read_addr_3,                // 数据读取模块读取请求基址 1，当 read_addr_index = 3 时使用
	input[1:0]                       read_addr_index,            // 从read_addr_0 read_addr_1 read_addr_2 read_addr_3中选择有效的基址
	input[ADDR_BITS - 1:0]           read_len,                   // 数据读取模块读取请求数据长度
	input                            read_en,                    // 数据读取模块读取请求一个数据，read_data下一个时钟有效
	output[READ_DATA_BITS  - 1:0]    read_data,                  // 读取数据
	output                           wr_burst_req,               // 到外部存储器控制器，发送突发写入请求
	output[BUSRT_BITS - 1:0]         wr_burst_len,               // 到外部存储器控制器，突发写入请求的数据长度，而不是字节
	output[ADDR_BITS - 1:0]          wr_burst_addr,              // 到外部存储器控制器，突发写入请求的基址 
	input                            wr_burst_data_req,          // 从外部存储器控制器，写入数据请求，数据之前 1 时钟
	output[MEM_DATA_BITS - 1:0]      wr_burst_data,              // 到外部存储器控制器，写入数据
	input                            wr_burst_finish,            // 从外部存储器控制器，突发写入完成
	input                            write_clk,                  // 数据写入模块时钟
	input                            write_req,                  // 数据写入模块写入请求，保持 '1' 直到 read_req_ack = '1'
	output                           write_req_ack,              // 数据写入模块写入请求响应
	output                           write_finish,               // 数据写入模块写入请求完成
	input[ADDR_BITS - 1:0]           write_addr_0,               // 数据写入模块写入请求基址 0，当 write_addr_index = 0 时使用
	input[ADDR_BITS - 1:0]           write_addr_1,               // 数据写入模块写入请求基址 1，当 write_addr_index = 1 时使用
	input[ADDR_BITS - 1:0]           write_addr_2,               // 数据写入模块写入请求基址 1，当 write_addr_index = 2 时使用
	input[ADDR_BITS - 1:0]           write_addr_3,               // 数据写入模块写入请求基址 1，当 write_addr_index = 3 时使用
	input[1:0]                       write_addr_index,           // 从write_addr_0 write_addr_1 write_addr_2 write_addr_3中选择有效的基址
	input[ADDR_BITS - 1:0]           write_len,                  // 数据写入模块写入请求数据长度
	input                            write_en,                   // 一个数据的数据写入模块写入请求
	input[WRITE_DATA_BITS - 1:0]     write_data                  // 写入数据
);
wire[15:0]                           wrusedw;                    // 写入已用词
wire[15:0]                           rdusedw;                    // 读取已用词
wire                                 read_fifo_aclr;             // fifo 异步清除
wire                                 write_fifo_aclr;            // fifo 异步清除
//instantiate an asynchronous FIFO 
afifo_16_512 write_buf
	(
	.rdclk                      (mem_clk                  ),          // 读取侧时钟
	.wrclk                      (write_clk                ),          // 写入侧时钟
	.aclr                       (write_fifo_aclr          ),          // 异步清除
	.wrreq                      (write_en                 ),          // 写入请求
	.rdreq                      (wr_burst_data_req        ),          // 读取请求
	.data                       (write_data               ),          // 输入数据
	.rdempty                    (                         ),          // 读取侧空标志
	.wrfull                     (                         ),          // 写入侧满标志
	.rdusedw                    (rdusedw                  ),          // 读取已用词
	.wrusedw                    (                         ),          // 写入已用词
	.q                          (wr_burst_data            )
);

frame_fifo_write
#
(
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BUSRT_BITS                 (BUSRT_BITS               ),
	.BURST_SIZE                 (BURST_SIZE               )
) 
frame_fifo_write_m0              
(  
	.rst                        (rst                      ),
	.mem_clk                    (mem_clk                  ),
	.wr_burst_req               (wr_burst_req             ),
	.wr_burst_len               (wr_burst_len             ),
	.wr_burst_addr              (wr_burst_addr            ),
	.wr_burst_data_req          (wr_burst_data_req        ),
	.wr_burst_finish            (wr_burst_finish          ),
	.write_req                  (write_req                ),
	.write_req_ack              (write_req_ack            ),
	.write_finish               (write_finish             ),
	.write_addr_0               (write_addr_0             ),
	.write_addr_1               (write_addr_1             ),
	.write_addr_2               (write_addr_2             ),
	.write_addr_3               (write_addr_3             ),
	.write_addr_index           (write_addr_index         ),    
	.write_len                  (write_len                ),
	.fifo_aclr                  (write_fifo_aclr          ),
	.rdusedw                    (rdusedw                  ) 
	
);

//instantiate an asynchronous FIFO 
afifo_16_512 read_buf
	(
	.rdclk                     (read_clk                   ),          // 读取侧时钟
	.wrclk                     (mem_clk                    ),          // 写入侧时钟
	.aclr                      (read_fifo_aclr             ),          // 异步清除
	.wrreq                     (rd_burst_data_valid        ),          // 写入请求
	.rdreq                     (read_en                    ),          // 读取请求
	.data                      (rd_burst_data              ),          // 输入数据
	.rdempty                   (                           ),          // 读取侧空标志
	.wrfull                    (                           ),          // 写入侧满标志
	.rdusedw                   (                           ),          // 读取已用词
	.wrusedw                   (wrusedw                    ),          // 写入已用词
	.q                         (read_data                  )
);

frame_fifo_read
#
(
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BUSRT_BITS                 (BUSRT_BITS               ),
	.FIFO_DEPTH                 (512                      ),
	.BURST_SIZE                 (BURST_SIZE               )
)
frame_fifo_read_m0
(
	.rst                        (rst                      ),
	.mem_clk                    (mem_clk                  ),
	.rd_burst_req               (rd_burst_req             ),   
	.rd_burst_len               (rd_burst_len             ),  
	.rd_burst_addr              (rd_burst_addr            ),
	.rd_burst_data_valid        (rd_burst_data_valid      ),    
	.rd_burst_finish            (rd_burst_finish          ),
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
	.wrusedw                    (wrusedw                  )
);

endmodule
