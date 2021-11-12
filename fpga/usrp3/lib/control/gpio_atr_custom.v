//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    16:14:16 11/12/2021 
// Design Name: 
// Module Name:    gpio_atr_custom 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
// Modify the original gpio_atr.v such that:
// In <idle state> gpio output divided clock signal used for RF switches
//////////////////////////////////////////////////////////////////////////////////

module gpio_atr_custom #(
  parameter BASE          = 0,
  parameter FAB_CTRL_EN   = 0,
  parameter DEFAULT_DDR   = 0
) (
  input clk, input reset,                                       //Clock and reset
  input set_stb, input [7:0] set_addr, input [31:0] set_data,   //Settings control interface
  input rx, input tx,                                           //Run signals that indicate tx and rx operation
  input      [9:0]  gpio_in,                              //GPIO input state
  output reg [9:0]  gpio_out,                             //GPIO output state
  output reg [9:0]  gpio_ddr,                             //GPIO direction (0=input, 1=output)
  input      [9:0]  gpio_out_fab,                         //GPIO driver bus from fabric
  output reg [9:0]  gpio_sw_rb                            //Readback value for software
);
  genvar i;

  wire [9:0]   in_tx, in_rx, in_fdx, ddr_reg, atr_disable, fabric_ctrl;
  reg [9:0]    ogpio, igpio;

  setting_reg #(.my_addr(BASE+1), .width(10)) reg_rx (
    .clk(clk),.rst(reset),.strobe(set_stb),.addr(set_addr), .in(set_data),
    .out(in_rx),.changed());

  setting_reg #(.my_addr(BASE+2), .width(10)) reg_tx (
    .clk(clk),.rst(reset),.strobe(set_stb),.addr(set_addr), .in(set_data),
    .out(in_tx),.changed());

  setting_reg #(.my_addr(BASE+3), .width(10)) reg_fdx (
    .clk(clk),.rst(reset),.strobe(set_stb),.addr(set_addr), .in(set_data),
    .out(in_fdx),.changed());
	
  setting_reg #(.my_addr(BASE+4), .width(10), .at_reset(DEFAULT_DDR)) reg_ddr (
    .clk(clk),.rst(reset),.strobe(set_stb),.addr(set_addr), .in(set_data),
    .out(ddr_reg),.changed());

  setting_reg #(.my_addr(BASE+5), .width(10)) reg_atr_disable (
    .clk(clk),.rst(reset),.strobe(set_stb),.addr(set_addr), .in(set_data),
    .out(atr_disable),.changed());

  generate if (FAB_CTRL_EN == 1) begin
    setting_reg #(.my_addr(BASE+6), .width(10)) reg_fabric_ctrl (
      .clk(clk),.rst(reset),.strobe(set_stb),.addr(set_addr), .in(set_data),
      .out(fabric_ctrl),.changed());
  end else begin
    assign fabric_ctrl = {10'b0};
  end endgenerate

  //12 bit counter
  reg [9:0] counter;
  reg [9:0] counter_buf;
  always @(posedge clk) begin
		if (reset) begin
			counter <= 0;
			counter_buf <= 0;
		end
		else begin
			counter <= counter + 1;
			counter_buf[3:0] <= counter[9:6];
		end
  end
 
 
  //Pipeline rx and tx signals for easier timing closure
  reg rx_d, tx_d;
  always @(posedge clk)
    {rx_d, tx_d} <= {rx, tx};

  generate for (i=0; i<10; i=i+1) begin: gpio_mux_gen
    //ATR selection MUX
    always @(posedge clk) begin
      case({atr_disable[i], tx_d, rx_d})
        3'b000:   ogpio[i] <= counter_buf[i];
        3'b001:   ogpio[i] <= in_rx[i];
        3'b010:   ogpio[i] <= in_tx[i];
        3'b011:   ogpio[i] <= in_fdx[i];
        default:  ogpio[i] <= counter_buf[i];   //If ATR mode is disabled, always use clock out
      endcase
    end
	
   //Pipeline input, output and direction
   //For fabric access, insert MUX as close to the IO as possible
   always @(posedge clk) begin
     gpio_out[i] <= fabric_ctrl[i] ? gpio_out_fab[i] : ogpio[i];
   end
  end endgenerate
 

  always @(posedge clk)
    igpio <= gpio_in;

 //set gpio to output
  always @(posedge clk) begin
    gpio_ddr <= ddr_reg;
  end
  
  //Generate software readback state
  generate for (i=0; i<10; i=i+1) begin: gpio_rb_gen
    always @(posedge clk)
      gpio_sw_rb[i] <= gpio_ddr[i] ? gpio_out[i] : igpio[i];
  end endgenerate

endmodule // gpio_atr
