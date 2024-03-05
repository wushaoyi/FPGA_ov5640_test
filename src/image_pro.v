`timescale 1ns / 1ps
//切换原图和灰度化模块

module image_pro
(
	input	wire			i_clk			,
	input	wire			i_rst_n			,
	input	wire	   	key_choose		,
	
	input	wire			in0_hs			,
	input	wire			in0_vs			,
	input	wire			in0_R		,
	input	wire			in0_G			,
	input	wire	   	in0_B		,
	
	input	wire			in1_hs			,
	input	wire			in1_vs			,
	input	wire			in1_R		,
	input	wire			in1_G		,
	input	wire	   	in1_B		,
	
	output	reg 			out_hs			,
	output	reg 			out_vs			,
	output	reg 			out_R		,
	output	reg 			out_G			,
	output	reg 	      out_B	 
);



always @ (posedge i_clk or posedge i_rst_n) begin
	case(key_choose ) 
		1'b1: 	begin out_hs = in0_hs; out_vs = in0_vs; out_R = in0_R; out_G = in0_G; out_B = in0_B; end
		1'd0: 	begin out_hs = in1_hs; out_vs = in1_vs; out_R = in1_R; out_G = in1_G; out_B = in1_B; end 
		default:begin out_hs = in0_hs; out_vs = in0_vs; out_R = in0_R; out_G = in0_G; out_B = in0_B; end
		endcase 
end 

endmodule