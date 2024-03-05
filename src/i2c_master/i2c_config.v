

 module reg_config(     
		  input          clk_24M,
		  input          camera_rstn,
		  input          initial_en,
		  output         reg_conf_done,
		  output         i2c_sclk,
		  inout          i2c_sdat

);

    
reg                             clock_20k;
reg [15:0]                      clock_20k_cnt;
reg [1:0]                       config_step;	  
reg [8:0]                       reg_index;	  
reg [31:0]                      i2c_data;
reg                             start;
reg                             reg_conf_done_reg;
reg [9:0]                       lut_index;
wire[31:0]                      lut_data;
	  
i2c_com u1(

	.clock_i2c        (clock_20k         ),
   .camera_rstn      (camera_rstn       ),
   .ack              (ack               ),
   .i2c_data         (i2c_data          ),
   .start            (start             ),
   .tr_end           (tr_end            ),
   .i2c_sclk         (i2c_sclk          ),
   .i2c_sdat         (i2c_sdat          )
);

assign reg_conf_done=reg_conf_done_reg;


//I2C Clock 24->20khz    
always@(posedge clk_24M)   
begin
   if(camera_rstn == 1'b0) begin
        clock_20k<=0;
        clock_20k_cnt<=0;
   end
   else if(clock_20k_cnt<1200)
      clock_20k_cnt<=clock_20k_cnt+1'b1;
   else begin
         clock_20k<=~clock_20k;
         clock_20k_cnt<=0;
   end
end


//iic寄存器配置过程控制    
always@(posedge clock_20k)    
begin
   if(!camera_rstn) begin
       config_step<=0;
       start<=0;
       lut_index<=0;
		 reg_conf_done_reg<=0;
   end
   else begin
      if(reg_conf_done_reg==1'b0) begin          
			  if(lut_index<302) begin
					 case(config_step)
					 0:begin
						i2c_data<=lut_data;   //IIC 设备地址0x78   
						start<=1;
						config_step<=1;
					 end
					 1:begin
						if(tr_end) begin             //iic写完成               					
							 start<=0;
							 config_step<=2;
						end
					 end
					 2:begin
						  lut_index<=lut_index+1'b1;
						  config_step<=0;
					 end
					 endcase
				end
			 else 
				reg_conf_done_reg<=1'b1;
      end
   end
 end
 
 //configure look-up table
lut_ov5640_rgb565_1024_768  lut_ov5640_rgb565_1024_768_m0(
	.lut_index                  (lut_index                ),
	.lut_data                   (lut_data                 )
);
		


endmodule

