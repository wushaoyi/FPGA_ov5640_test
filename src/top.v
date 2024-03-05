
module top(
	input                       clk,
	input                       rst_n,
	inout                       cmos_scl,          // 控制i2c的时钟
	inout                       cmos_sda,          // i2c数据
	input                       cmos_vsync,        // cmos场同步
	input                       cmos_href,         // cmos行同步参考，数据有效
	input                       cmos_pclk,         // cmos像素时钟
	output                      cmos_xclk,         // cmos外部时钟
	input   [7:0]               cmos_db,           // cmos数据
	output                      cmos_rst_n,        // cmos复位
	output                      cmos_pwdn,         // cmos断电
	input                       key_in,
	output                      vga_out_hs,        // vga水平同步
	output                      vga_out_vs,        // vga垂直同步
	output[4:0]                 vga_out_r,         // vga红色
	output[5:0]                 vga_out_g,         // vga绿色
	output[4:0]                 vga_out_b,         // vga蓝色
	output                      sdram_clk,         // sdram时钟
	output                      sdram_cke,         // sdram时钟使能
	output                      sdram_cs_n,        // sdram芯片选择
	output                      sdram_we_n,        // sdram写使能
	output                      sdram_cas_n,       // sdram列地址选通
	output                      sdram_ras_n,       // sdram行地址选通
	output[1:0]                 sdram_dqm,         // sdram数据使能
	output[1:0]                 sdram_ba,          // sdram行地址
	output[12:0]                sdram_addr,        // sdram bank地址
	inout[15:0]                 sdram_dq           // sdram数据
);

parameter MEM_DATA_BITS          = 16;             //external memory user interface data width
parameter ADDR_BITS              = 24;             //external memory user interface address width
parameter BUSRT_BITS             = 10;             //external memory user interface burst width
wire                            wr_burst_data_req;
wire                            wr_burst_finish;
wire                            rd_burst_finish;
wire                            rd_burst_req;
wire                            wr_burst_req;
wire[BUSRT_BITS - 1:0]          rd_burst_len;
wire[BUSRT_BITS - 1:0]          wr_burst_len;
wire[ADDR_BITS - 1:0]           rd_burst_addr;
wire[ADDR_BITS - 1:0]           wr_burst_addr;
wire                            rd_burst_data_valid;
wire[MEM_DATA_BITS - 1 : 0]     rd_burst_data;
wire[MEM_DATA_BITS - 1 : 0]     wr_burst_data;
wire                            read_req;
wire                            read_req_ack;
wire                            read_en;
wire[15:0]                      read_data;
wire                            write_en;
wire[15:0]                      write_data;
wire                            write_req;
wire                            write_req_ack;
wire                            ext_mem_clk;       //external memory clock
wire                            video_clk;         //video pixel clock
wire                            hs;
wire                            vs;
wire                            de;
wire[15:0]                      vout_data;
wire[15:0]                      cmos_16bit_data;
wire                            cmos_16bit_wr;
wire[1:0]                       write_addr_index;
wire[1:0]                       read_addr_index;
wire                            initial_en;
wire                            Config_Done;
wire[7:0]                       ycbcr_y;
wire                            ycbcr_hs;
wire                            ycbcr_vs;
wire                            ycbcr_de;

assign sdram_clk = ext_mem_clk;
assign write_en = cmos_16bit_wr;
assign write_data = {cmos_16bit_data[4:0],cmos_16bit_data[10:5],cmos_16bit_data[15:11]};
//generate the CMOS sensor clock and the SDRAM controller clock
sys_pll sys_pll_m0(
	.inclk0                     (clk                      ),
	.c0                         (cmos_xclk                ),
	.c1                         (ext_mem_clk              )
	);
//generate video pixel clock
video_pll video_pll_m0(
	.inclk0                     (clk                      ),
	.c0                         (video_clk                )
	);
//cmos power on delay
power_on_delay	power_on_delay_inst(
	.clk_50M                    (clk                      ),
	.reset_n                    (rst_n                    ),	
	.camera_rstn                (cmos_rst_n               ),
	.camera_pwnd                (cmos_pwdn                ),
	.initial_en                 (initial_en               )		
);

//cmos register intial
reg_config	reg_config_inst(
	.clk_24M                    (cmos_xclk                ),
	.camera_rstn                (cmos_rst_n               ),
	.initial_en                 (initial_en               ),		
	.i2c_sclk                   (cmos_scl                 ),
	.i2c_sdat                   (cmos_sda                 ),
	.reg_conf_done              (Config_Done              )

);


//CMOS sensor 8bit data is converted to 16bit data
cmos_8_16bit cmos_8_16bit_m0(
	.rst                        (~rst_n                   ),
	.pclk                       (cmos_pclk                ),
	.pdata_i                    (cmos_db                  ),
	.de_i                       (cmos_href                ),
	.pdata_o                    (cmos_16bit_data          ),
	.hblank                     (                         ),
	.de_o                       (cmos_16bit_wr            )
);
//CMOS sensor writes the request and generates the read and write address index
cmos_write_req_gen cmos_write_req_gen_m0(
	.rst                        (~rst_n                   ),
	.pclk                       (cmos_pclk                ),
	.cmos_vsync                 (cmos_vsync               ),
	.write_req                  (write_req                ),
	.write_addr_index           (write_addr_index         ),
	.read_addr_index            (read_addr_index          ),
	.write_req_ack              (write_req_ack            )
);
//视频输出定时发生器，并生成帧读取数据请求
video_timing_data video_timing_data_m0
(
	.video_clk                  (video_clk                ),
	.rst                        (~rst_n                   ),
	.read_req                   (read_req                 ),
	.read_req_ack               (read_req_ack             ),
	.read_en                    (read_en                  ),
	.read_data                  (read_data                ),
	.hs                         (hs                       ),
	.vs                         (vs                       ),
	.de                         (de                       ),
	.vout_data                  (vout_data                )
);
//灰度化
rgb_to_ycbcr rgb_to_ycbcr_m0(
	.clk                        (video_clk                ),
	.rst                        (~rst_n                   ),
	.rgb_r                      ({vout_data[15:11],3'd0}  ),
	.rgb_g                      ({vout_data[10:5],2'd0}   ),
	.rgb_b                      ({vout_data[4:0],3'd0}    ),
	.rgb_hs                     (hs                       ),
	.rgb_vs                     (vs                       ),
	.rgb_de                     (de                       ),
	.ycbcr_y                    (ycbcr_y                  ),
	.ycbcr_cb                   (                         ),
	.ycbcr_cr                   (                         ),
	.ycbcr_hs                   (ycbcr_hs                 ),
	.ycbcr_vs                   (ycbcr_vs                 ),
	.ycbcr_de                   (ycbcr_de                 )
);
//视频的数据帧读写控制
frame_read_write frame_read_write_m0
(
	.rst                        (~rst_n                   ),
	.mem_clk                    (ext_mem_clk              ),
	.rd_burst_req               (rd_burst_req             ),
	.rd_burst_len               (rd_burst_len             ),
	.rd_burst_addr              (rd_burst_addr            ),
	.rd_burst_data_valid        (rd_burst_data_valid      ),
	.rd_burst_data              (rd_burst_data            ),
	.rd_burst_finish            (rd_burst_finish          ),
	.read_clk                   (video_clk                ),
	.read_req                   (read_req                 ),
	.read_req_ack               (read_req_ack             ),
	.read_finish                (                         ),
	.read_addr_0                (24'd0                    ), //The first frame address is 0
	.read_addr_1                (24'd2073600              ), //The second frame address is 24'd2073600 ,large enough address space for one frame of video
	.read_addr_2                (24'd4147200              ),
	.read_addr_3                (24'd6220800              ),
	.read_addr_index            (read_addr_index          ),
	.read_len                   (24'd786432               ), //frame size
	.read_en                    (read_en                  ),
	.read_data                  (read_data                ),

	.wr_burst_req               (wr_burst_req             ),
	.wr_burst_len               (wr_burst_len             ),
	.wr_burst_addr              (wr_burst_addr            ),
	.wr_burst_data_req          (wr_burst_data_req        ),
	.wr_burst_data              (wr_burst_data            ),
	.wr_burst_finish            (wr_burst_finish          ),
	.write_clk                  (cmos_pclk                ),
	.write_req                  (write_req                ),
	.write_req_ack              (write_req_ack            ),
	.write_finish               (                         ),
	.write_addr_0               (24'd0                    ),
	.write_addr_1               (24'd2073600              ),
	.write_addr_2               (24'd4147200              ),
	.write_addr_3               (24'd6220800              ),
	.write_addr_index           (write_addr_index         ),
	.write_len                  (24'd786432               ), //frame size
	.write_en                   (write_en                 ),
	.write_data                 (write_data               )
);
//sdram controller
sdram_core sdram_core_m0
(
	.rst                        (~rst_n                   ),
	.clk                        (ext_mem_clk              ),
	.rd_burst_req               (rd_burst_req             ),
	.rd_burst_len               (rd_burst_len             ),
	.rd_burst_addr              (rd_burst_addr            ),
	.rd_burst_data_valid        (rd_burst_data_valid      ),
	.rd_burst_data              (rd_burst_data            ),
	.rd_burst_finish            (rd_burst_finish          ),
	.wr_burst_req               (wr_burst_req             ),
	.wr_burst_len               (wr_burst_len             ),
	.wr_burst_addr              (wr_burst_addr            ),
	.wr_burst_data_req          (wr_burst_data_req        ),
	.wr_burst_data              (wr_burst_data            ),
	.wr_burst_finish            (wr_burst_finish          ),
	.sdram_cke                  (sdram_cke                ),
	.sdram_cs_n                 (sdram_cs_n               ),
	.sdram_ras_n                (sdram_ras_n              ),
	.sdram_cas_n                (sdram_cas_n              ),
	.sdram_we_n                 (sdram_we_n               ),
	.sdram_dqm                  (sdram_dqm                ),
	.sdram_ba                   (sdram_ba                 ),
	.sdram_addr                 (sdram_addr               ),
	.sdram_dq                   (sdram_dq                 )
);

image_pro image_pro_m0
(

	.i_clk(clk)		,
	.i_rst_n(rst_n)			,
	.key_choose(key_in)		,
	
	.in0_hs(hs)			,
	.in0_vs(vs)			,
	.in0_R(vout_data[15:11])		,
	.in0_G(vout_data[10:5])			,
	.in0_B(vout_data[4:0])	,
	
	.in1_hs(ycbcr_hs)			,
	.in1_vs(ycbcr_vs)			,
	.in1_R(ycbcr_y[7:3])		,
	.in1_G(ycbcr_y[7:2])		,
	.in1_B(ycbcr_y[7:3])		,
	
	.out_hs(vga_out_hs)			,
	.out_vs(vga_out_vs)			,
	.out_R(vga_out_r)	,
	.out_G	(vga_out_g)		,
	.out_B	(vga_out_b) 
);

endmodule