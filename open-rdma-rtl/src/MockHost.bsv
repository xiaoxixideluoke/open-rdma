package MockHost ;

import Clocks :: * ;
import BRAM :: *;
import BRAMCore ::*;
import DefaultValue ::*;
import ClientServer ::*;
import FIFOF :: *;
import DReg :: *;
import GetPut :: *;
import SpecialFIFOs :: *;
import BasicDataTypes :: *;
import PrimUtils :: *;

//  Export  section
export NetIfcAccessAction(..);

// Modules for export
export mkMockHostMem;
export mkMockHostBarAccess;
export mkMockHostNetworkConnector;

// Interfaces
export MockHostMem(..);
export MockHostBarAccess(..);
export MockHostNetworkConnector(..);



// imported C function to handle shared memory
import "BDPI" function ActionValue#(Bit#(64)) c_createMockHostRpcChannel;
import "BDPI" function ActionValue#(t_word) c_readBRAM(Bit#(64) clientId, Bit#(64) wordAddr, Bit#(32) wordWidth) provisos (
	Bits#(t_word, sz_word)
);
import "BDPI" function Action c_writeBRAM(Bit#(64) clientId, Bit#(64) wordAddr, t_word d, Bit#(sz_byteen) byteEn, Bit#(32) wordWidth) provisos (
	Bits#(t_word, sz_word)
);

import "BDPI" function ActionValue#(PcieBarAccessAction) c_getPcieBarReadReq(Bit#(64) clientId);
import "BDPI" function Action c_putPcieBarReadResp(Bit#(64) clientId, PcieBarAccessAction resp);
import "BDPI" function ActionValue#(PcieBarAccessAction) c_getPcieBarWriteReq(Bit#(64) clientId);
import "BDPI" function Action c_putPcieBarWriteResp(Bit#(64) clientId, PcieBarAccessAction resp);

import "BDPI" function ActionValue#(NetIfcAccessAction) c_netIfcGetRxData(Bit#(64) clientId);
import "BDPI" function Action c_netIfcPutTxData(Bit#(64) clientId, NetIfcAccessAction resp);

function ActionValue#(t_word) readBRAM(Bit#(64) clientId, t_addr wordAddr) provisos (
	Bits#(t_addr, sz_addr),
	Bits#(t_word, sz_word),
	Add#(a__, sz_addr, 64)
);
    return c_readBRAM(clientId, zeroExtend(pack(wordAddr)), fromInteger(valueOf(sz_word)));
endfunction

function Action writeBRAM(Bit#(64) clientId, t_addr wordAddr, t_word d, Bit#(sz_byteen) byteEn) provisos (
	Bits#(t_addr, sz_addr),
	Bits#(t_word, sz_word),
	Add#(a__, sz_addr, 64)
);
    return c_writeBRAM(clientId, zeroExtend(pack(wordAddr)), d, byteEn, fromInteger(valueOf(sz_word)));
endfunction


interface MockHostMem#(type addr, type data, numeric type n);
	interface BRAM2PortBE #(addr, data, n) hostMem;
	method Bool ready;
endinterface

interface MockHostBarAccess;
	interface Client#(PcieBarAddr, PcieBarData) barReadClt;
	interface Client#(Tuple2#(PcieBarAddr, PcieBarData), Bool) barWriteClt; 
	method Bool ready;
endinterface

interface MockHostNetworkConnector;
	interface Put#(NetIfcAccessAction)   txPut;
	interface Get#(NetIfcAccessAction)   rxGet;
	method Bool ready;
endinterface

typedef struct {
	Bit#(64) pci_tag;
	Bit#(64) valid;
	Bit#(64) addr;
	Bit#(64) value;
} PcieBarAccessAction deriving(Bits, FShow);


typedef struct {
	Bit#(8) isValid;
	Bit#(8) isLast;
	Bit#(8) isFirst;
	Bit#(8) mod;
	DATA data;
} NetIfcAccessAction deriving(Bits, FShow); 


module mkMockHostNetworkConnector (MockHostNetworkConnector);

	Clock srcClock <- exposeCurrentClock;
    Reset srcReset <- exposeCurrentReset;

    // mem
	Reg#(Bit#(64))  clientIdReg   <- mkReg(0);
	Reg#(Bool)      initDoneReg    <- mkReg(False);
	Reg#(Bit#(64))  memHandleForCmacReg   <- mkReg(0);
	Reg#(Bool)      initDoneForCamcReg    <- mkReg(False);

	FIFOF#(NetIfcAccessAction) txQ <- mkFIFOF;
	FIFOF#(NetIfcAccessAction) rxQ <- mkFIFOF;

    rule doInit(!initDoneReg);
		let ptr <- c_createMockHostRpcChannel;
		if(ptr == 0) begin
			$fwrite(stderr, "%0t: mkMockHostNetworkConnector: ERROR: fail to create createNewMockHostRpcChannel\n", $time);
			$finish;
		end
		$display("%0t: mkMockHostNetworkConnector: createNewMockHostRpcChannel, client_id = %h", $time, ptr);
		clientIdReg <= ptr;
		initDoneReg <= True;
		memHandleForCmacReg <= ptr;
		initDoneForCamcReg <= True;
	endrule

	rule forwardNetIfcTx if (initDoneForCamcReg);

		if (txQ.notEmpty) begin
			let beat = txQ.first;
			txQ.deq;

			// $display("time=%0t: ", $time, "net ifc send beat=", fshow(beat));
			
			c_netIfcPutTxData(memHandleForCmacReg, beat);
		end
		else begin
			// $display("time=%0t: ", $time, "net ifc send data=NO_DATA_TO_SEND");
		end

	endrule

	rule forwardNetIfcRx if (initDoneForCamcReg);
		let beat <- c_netIfcGetRxData(memHandleForCmacReg);
		if (beat.isValid != 0) begin
			// rxQ.enq(beat);
			// $display("time=%0t: ", $time, "net ifc recv beat=", fshow(beat));

			if (rxQ.notFull) begin
				rxQ.enq(beat);
				// $display("time=%0t: ", $time, "net ifc recv beat=", fshow(beat));
			end 
			else begin
				$display("time=%0t: ", $time, "net ifc recv data BUT DISCARD SINCE QUEUE FULL");
				$finish(1);
			end
		end
	endrule

	method Bool ready = initDoneReg;

	interface rxGet 	= toGet(rxQ);
	interface txPut 	= toPut(txQ);
endmodule

// Exported module
module mkMockHostMem #(BRAM_Configure cfg)(MockHostMem#(addr, data, n)) provisos(
	Bits#(addr, addr_sz),
	Bits#(data, data_sz),
	Div#(data_sz, n, chunk_sz),
	Mul#(chunk_sz, n, data_sz),
	Add#(a__, addr_sz, 64),
	FShow#(addr),
	FShow#(data)
);


    // mem
	Reg#(Bit#(64))  clientIdReg   <- mkReg(0);
	Reg#(Bool)      initDoneReg    <- mkReg(False);


	FIFOF#(data) portRespQueueA <- mkFIFOF;
	FIFOF#(data) portRespQueueB <- mkFIFOF;

    rule doInit(!initDoneReg);
		let ptr <- c_createMockHostRpcChannel;
		if(ptr == 0) begin
			$fwrite(stderr, "%0t: mkMockHostMem: ERROR: fail to create createNewMockHostRpcChannel\n", $time);
			$finish;
		end
		$display("%0t: mkMockHostMem: createNewMockHostRpcChannel, client_id = %h", $time, ptr);
		clientIdReg <= ptr;
		initDoneReg <= True;
	endrule

	method Bool ready = initDoneReg;

	interface BRAM2PortBE hostMem;
		interface BRAMServer portA;
			interface Put request;
				method Action put(BRAMRequestBE#(addr, data, n) req);
					// $display(
					// 	"time=%0t::", $time, "mock Host Mem Port A req.writeen=", fshow(req.writeen),
					// 	" req.addr=", fshow(req.address)
					// );
					if (req.writeen == 0) begin
						let resp <- readBRAM(clientIdReg, req.address);
						portRespQueueA.enq(resp);
					end 
					else begin
						writeBRAM(clientIdReg, req.address, req.datain, req.writeen);
						if (req.responseOnWrite) begin
							portRespQueueA.enq(unpack(0));
						end
					end
				endmethod
			endinterface

			interface Get response;
				method ActionValue#(data) get;
					// $display(
					// 	"time=%0t::", $time, "mock Host Mem Port A output read result=", fshow(portRespQueueA.first)
					// );

					portRespQueueA.deq;
					return portRespQueueA.first;
				endmethod
			endinterface
		endinterface

		method Action portAClear;
		endmethod


		interface BRAMServer portB;
			interface Put request;
				method Action put(BRAMRequestBE#(addr, data, n) req);
					// $display(
					// 	"time=%0t::", $time, "mock Host Mem Port B req.writeen=", fshow(req.writeen),
					// 	" req.addr=", fshow(req.address)
					// );
					if (req.writeen == 0) begin
						let resp <- readBRAM(clientIdReg, req.address);
						portRespQueueB.enq(resp);
					end 
					else begin
						writeBRAM(clientIdReg, req.address, req.datain, req.writeen);
						if (req.responseOnWrite) begin
							portRespQueueB.enq(unpack(0));
						end
					end
				endmethod
			endinterface

			interface Get response;
				method ActionValue#(data) get;
					portRespQueueB.deq;
					return portRespQueueB.first;
				endmethod
			endinterface
		endinterface

		method Action portBClear;
		endmethod
	endinterface
endmodule



module mkMockHostBarAccess(MockHostBarAccess);


	Reg#(Bit#(64))  clientIdReg   <- mkReg(0);
	Reg#(Bool)      initDoneReg    <- mkReg(False);

	FIFOF#(Tuple2#(PcieBarAddr, PcieBarData)) barWriteReqQ <- mkFIFOF;
	FIFOF#(Bool) barWriteRespQ <- mkFIFOF;
	FIFOF#(PcieBarAddr) barReadReqQ <- mkFIFOF;
	FIFOF#(PcieBarData) barReadRespQ <- mkFIFOF;


	// Note, it assumes that the resp will keep order as the request.
	// We do not support out of order now, to support OOO, the CSR
	// handling logic must also pass the tag field all the way around.
	// since the current CSR/BAR read logic is simple and will finish
	// in one cycle, it can't be out of order, so we simply keep tag 
	// in order in this queue.
	FIFOF#(Bit#(64)) readTagKeepOrderQ <- mkFIFOF;
	FIFOF#(Bit#(64)) writeTagKeepOrderQ <- mkFIFOF;

    rule doInit(!initDoneReg);
		let ptr <- c_createMockHostRpcChannel;
		if(ptr == 0) begin
			$fwrite(stderr, "%0t: mkMockHostBarAccess: ERROR: fail to create createNewMockHostRpcChannel\n", $time);
			$finish;
		end
		$display("%0t: mkMockHostBarAccess: createNewMockHostRpcChannel, client_id = %h", $time, ptr);
		clientIdReg <= ptr;
		initDoneReg <= True;
	endrule

	rule forwardBarReadReq if (initDoneReg);
		let rawReq <- c_getPcieBarReadReq(clientIdReg);
		if (rawReq.valid != 0) begin
			barReadReqQ.enq(unpack(truncate(pack(rawReq.addr))));
			readTagKeepOrderQ.enq(rawReq.pci_tag);
		end
	endrule

	rule forwardBarReadResp if (initDoneReg);
		barReadRespQ.deq;
		readTagKeepOrderQ.deq;
		let resp = PcieBarAccessAction {
			pci_tag: readTagKeepOrderQ.first,
			valid: 1,
			addr: 0,
			value: unpack(zeroExtend(pack(barReadRespQ.first)))
		};
		c_putPcieBarReadResp(clientIdReg, resp);
	endrule

	rule forwardBarWriteReq if (initDoneReg);
		let rawReq <- c_getPcieBarWriteReq(clientIdReg);
		if (rawReq.valid != 0) begin
			barWriteReqQ.enq(
				tuple2(
					unpack(truncate(pack(rawReq.addr))),
					unpack(truncate(pack(rawReq.value)))
				)
			);
			writeTagKeepOrderQ.enq(rawReq.pci_tag);
		end
	endrule

	rule forwardBarWriteResp if (initDoneReg);
		barWriteRespQ.deq;
		writeTagKeepOrderQ.deq;
		let resp = PcieBarAccessAction {
			pci_tag: writeTagKeepOrderQ.first,
			valid: barWriteRespQ.first ? 1 : 0,
			addr: 0,
			value: 0
		};
		c_putPcieBarWriteResp(clientIdReg, resp);
		// $display("time=%0t,  mkMockHostBarAccess, forwardBarWriteResp", $time);
	endrule

	method Bool ready = initDoneReg;

	interface barWriteClt = toGPClient(barWriteReqQ, barWriteRespQ);
    interface barReadClt = toGPClient(barReadReqQ, barReadRespQ);

endmodule






endpackage