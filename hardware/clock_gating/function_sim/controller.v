module controller(clk, rst, inSel, biasBuf_in_addr, bias_weight_outAddr, biasBufEn, FIFO_w_canWrite, FIFO_w_canRead, FIFO_w_En, canRead, 
	              canWrite, fullRow, threeRowready, psumEn, first, last, headAddress, pusmclear, mode,
	              DRAMreadAddr, needRead, clear, FIFO_En, DRAMreadEn, ReadCount, FIFOtotalRead, selectRow, toMem0, toMem1, toMem2, toMem3);

input clk, rst;
output DRAMreadEn;

// For all
output reg [2:0] mode;

assign DRAMreadEn = 1;

// For tb
output reg [1:0] inSel;

// For biasBuf
output reg [6:0] biasBuf_in_addr;
output reg [6:0] bias_weight_outAddr;
output reg biasBufEn;

// For weightBuf
reg [6:0] weightAddr;

// For FIFO_w
input FIFO_w_canWrite, FIFO_w_canRead;
output reg FIFO_w_En;

// FIFO input
input canRead, canWrite;  
input [4:0] ReadCount;
input [10:0] FIFOtotalRead;

// For psumBuf
output reg psumEn, first, last;  
output reg [5:0] headAddress;
output reg pusmclear;

// For FIFO
output reg [9:0] DRAMreadAddr;
output reg needRead;
output reg clear;
output reg FIFO_En;


// For row select
output reg [1:0] selectRow;
output reg toMem0, toMem1, toMem2, toMem3;  // rowRf enable signal
output reg fullRow;                         // Use to check new row is full or not 
output reg threeRowready;                   // First three row ready signal

// For psum 
reg [3:0] psumState;
reg [2:0] sendCount, processCount;



// ------------------ Psum control ----------------------
always@(posedge clk or posedge rst)begin
	if(rst)begin
		psumEn <= 0;
		first <= 0;
		last <= 0;
		headAddress <= 6'd0;

		psumState <= 4'd0;
		sendCount <= 3'd0;
		processCount <= 3'd0;

		pusmclear <= 0;
	end
	else begin
		if(mode==0)begin
			case(psumState)
				0:begin  // Wait first three row ready
					if(threeRowready) psumState <= 1;
				end
				1:begin   
					if(sendCount==2) psumState <= 2;
					sendCount <= (sendCount==2)? 0 : sendCount + 1;
				end
				2:begin
					case(processCount)
						0:begin
							psumEn <= 1;
							first <= 1;
						end
						1:begin
							first <= 0;
							headAddress <= headAddress + 6;
						end
						2:begin
							headAddress <= headAddress + 8;
						end
						3:begin
							last <= 1;
							headAddress <= headAddress + 8;
							if(fullRow) sendCount <= 1;
						end
						4:begin
							last <= 0;
							psumEn <= 0;
							headAddress <= 0;
							psumState <= (threeRowready)? 1 : 0;
						end
					endcase
					processCount <= (processCount==4)? 0 : processCount + 1;
				end
			endcase
		end
		else if(mode==1)begin
			case(psumState)
			    0:begin
			    	
			    end
				1:begin  // Wait first three row ready
					if(threeRowready) psumState <= 2;
					headAddress <= 0;
					pusmclear <= 1;
				end
				2:begin   
					if(sendCount==3) psumState <= 3;
					sendCount <= (sendCount==3)? 0 : sendCount + 1;
					pusmclear <= 0;
				end
				3:begin
					case(processCount)
						0:begin
							psumEn <= 1;
							first <= 1;
							if(fullRow) sendCount <= 3;
						end
						1:begin
							first <= 0;
							last <= 1;
							headAddress <= headAddress + 6;
							if(fullRow) sendCount <= 2;
						end
						2:begin
							last <= 0;
							psumEn <= 0;
							headAddress <= headAddress + 6;
							psumState <= (threeRowready)? 2 : 1;
							if(fullRow) sendCount <= 1;
						end
					endcase
					processCount <= (processCount==2)? 0 : processCount + 1;
				end
			endcase
		end
	end
end


// ---------------- Top state control ------------------
reg [1:0] crState, ntState;
reg [2:0] channel_cnt;


parameter READ_BIAS   = 2'd0,
          READ_WEIGHT = 2'd1,
          READ_IFMAP  = 2'd2,
          WAIT        = 2'd3;

always@(posedge clk or posedge rst)begin
	if(rst)begin
		crState <= READ_BIAS;
	end
	else begin
		crState <= ntState;
	end
end

always@(*)begin
	case(crState)
		READ_BIAS:begin
			ntState = (biasBuf_in_addr==5)? READ_WEIGHT : READ_BIAS;
			inSel = 0;
			biasBufEn = 1;
			FIFO_w_En = 0;
			FIFO_En   = 0; 
			clear     = 0;
		end
		READ_WEIGHT:begin
			ntState = (weightAddr==5)? READ_IFMAP : READ_WEIGHT;
			inSel = 1;
			biasBufEn = 0;
			FIFO_w_En = 1;
			FIFO_En   = 0; 
			clear     = 0;
		end
		READ_IFMAP:begin
			ntState = (FIFOtotalRead==121 && canRead)? WAIT : READ_IFMAP;
			inSel = 2;
			biasBufEn = 0;
			FIFO_w_En = 0;
			FIFO_En   = 1;
			clear     = 0; 
		end
		WAIT:begin
			FIFO_En   = 1;
			if(channel_cnt==5)begin
				ntState = READ_WEIGHT;
				FIFO_En   = 0;
			end
			else if(threeRowready)begin
				ntState = READ_IFMAP;
			end
			else ntState = WAIT;
			inSel = 2;
			biasBufEn = 0;
			FIFO_w_En = 0;
			
			if(threeRowready) clear = 1;
			else clear = 0;
		end
	endcase
end


// ------------------ FIFO control ----------------------
always@(posedge clk or posedge rst)begin
	if(rst)begin
		DRAMreadAddr <= 10'd0;
		channel_cnt <= 3'd0;
		mode <= 3'd0;
		needRead <= 1;
	end
	else begin
		case(crState)
			READ_BIAS:begin
				needRead <= 1;
				if(biasBufEn) DRAMreadAddr <= DRAMreadAddr + 1;
			end
			READ_WEIGHT:begin
				if(FIFO_w_En && FIFO_w_canWrite) DRAMreadAddr <= DRAMreadAddr + 1;
				if(mode==0 && weightAddr==5)  DRAMreadAddr <= 125;
				if(mode==1 && weightAddr==11) DRAMreadAddr <= 238;  // Start from conv1 result
			end
			READ_IFMAP:begin
				if(FIFO_En && canWrite) begin
					if(FIFOtotalRead!=121) DRAMreadAddr <= DRAMreadAddr + 1;
					else DRAMreadAddr <= 125;
				end
			end
			WAIT:begin
				
				if(threeRowready) begin
					channel_cnt <= channel_cnt + 1;
				end
				if(channel_cnt==5) begin   // Start to enter conv2
					mode <= mode + 1;
					DRAMreadAddr <= 13;
				end
				else if(FIFO_En && canWrite) begin
					DRAMreadAddr <= DRAMreadAddr + 1;
				end
			end
		endcase
	end
end


// ------------------ biasBuf 、FIFO_w 、FIFO control ------------------

always@(posedge clk or posedge rst)begin
	if(rst)begin
		biasBuf_in_addr <= 0;
		bias_weight_outAddr <= 0;
		weightAddr <= 7'd0;
	end
	else begin
		case(crState)
			READ_BIAS:begin
				weightAddr <= 7'd0;
				biasBuf_in_addr <= (biasBuf_in_addr==6)? 0 : biasBuf_in_addr + 1;
			end
			READ_WEIGHT:begin
				if(FIFO_w_canRead) begin
					weightAddr <= weightAddr + 1;
					bias_weight_outAddr <= 0;
				end
			end
			READ_IFMAP:begin
				
			end
			WAIT:begin
				if(threeRowready) bias_weight_outAddr <= bias_weight_outAddr + 1;
				if(mode==0) weightAddr <= 0;
			end
		endcase
	end
end


// ------------------ Row select control ------------------
reg [1:0] rowState;
always@(posedge clk or posedge rst)begin
	if(rst)begin
		rowState <= 2'd0;
		threeRowready <= 0; 
	end
	else begin
		if(FIFOtotalRead==121 && canRead) begin
			threeRowready <= 0; 
			rowState <= 2'd0;
		end
		else begin
			case(rowState)
				0:begin
					if(mode==0 && ReadCount==4) rowState <= 1;
					if(mode==1 && ReadCount==2) rowState <= 1;
				end
				1:begin
					if(mode==0 && ReadCount==8) rowState <= 2;
					if(mode==1 && ReadCount==4) rowState <= 2;
				end
				2:begin
					if(mode==0 && ReadCount==12) rowState <= 3;
					if(mode==1 && ReadCount==6) rowState <= 3;
					if(mode==0 && ReadCount==11)
						threeRowready <= 1;
					if(mode==1 && ReadCount==5)
						threeRowready <= 1;
				end
				3:begin
					if(mode==0 && ReadCount==16) rowState <= 0;
					if(mode==1 && ReadCount==8) rowState <= 0;
				end
			endcase
		end
	end
end

// ------------- rowRf select -------------

always@(posedge clk or posedge rst)begin
	if(rst)begin
		selectRow <= 2'd3;
	end
	else begin
		if(fullRow) selectRow <= selectRow + 1;
	end
end

always@(*)begin
	case(rowState)
		0:begin
			toMem0 = 1;
			toMem1 = 0;
			toMem2 = 0;
			toMem3 = 0;
			fullRow = (threeRowready && ReadCount==4)? 1 : 0;
		end
		1:begin
			toMem0 = 0;
			toMem1 = 1;
			toMem2 = 0;
			toMem3 = 0;
			fullRow = (threeRowready && ReadCount==8)? 1 : 0;
		end
		2:begin
			toMem0 = 0;
			toMem1 = 0;
			toMem2 = 1;
			toMem3 = 0;
			fullRow = (threeRowready && ReadCount==12)? 1 : 0;
		end
		3:begin
			toMem0 = 0;
			toMem1 = 0;
			toMem2 = 0;
			toMem3 = 1;
			fullRow = (threeRowready && ReadCount==16)? 1 : 0;
		end
	endcase
end

endmodule