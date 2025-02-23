module rowRf(clk, rst, mode, writeEn, writeAddr, writeData, fullRow, threeRowready, rowOut);

input clk, rst, writeEn, fullRow;
input [2:0] mode;
input [63:0] writeData;     // Data write to rowRf from FIFO
input [1:0]  writeAddr;     // Write to rowRf address
input threeRowready;
output reg [63:0] rowOut;

reg [63:0] buffer [3:0];    // Keep four 64 bit data which means one row data
reg [2:0] readAddr;         // write to PE array address
reg state;
integer i;

always@(posedge clk or posedge rst)begin
	if(rst)begin
		for(i=0; i<4; i=i+1)begin
			buffer[i] <= 64'd0;
		end
		readAddr <= 0;
		rowOut <= 64'd0;
		state <= 1;
	end
	else begin

		/*  Read data from FIFO  */
		if(writeEn)begin 
			buffer[writeAddr] <= writeData;
		end

		/* Write data to PE array */ 
		case(state)
			0:begin
				rowOut <= buffer[readAddr];
				if(mode==0 && readAddr==3) begin
					state <= 1;
					readAddr <= 3'd0;
				end
				else if(mode==1 && readAddr==1)begin
					state <= 1;
					readAddr <= 3'd0;
				end
				else readAddr <= readAddr + 1;
			end
			1:begin
				if(fullRow) begin
					rowOut <= buffer[readAddr];
					readAddr <= readAddr + 1;
					state <= 0;
				end
			end
		endcase 

	end
end

endmodule