import GetPut :: *;
import ClientServer :: *;
import Connectable :: *;
import RegFile :: *;
import FIFOF :: *;
import Vector :: *;

import PrimUtils :: *;


typedef 14 ACX_BRAM72K_SDP_ADDR_WIDTH;
typedef Bit#(ACX_BRAM72K_SDP_ADDR_WIDTH) AcxBram72kAddr;
typedef TMul#(72,1024) BITS_COUNT_72K;

typedef Bit#(144) Bram72kEntry144;
typedef Bit#(128) Bram72kEntry128;

interface BRAM72K_SDP#(type tData);
    method Action putReadReq(AcxBram72kAddr addr);
    method tData read;
    method Action putWriteReq(AcxBram72kAddr addr, tData data);    
endinterface


import "BVI" ACX_BRAM72K_SDP =
module mkBram72kSdpVerilogInner(BRAM72K_SDP#(tData))
    provisos(
            Bits#(tData, szData)
           );

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    parameter read_width  = valueOf(szData);
    parameter write_width = valueOf(szData);
    parameter byte_width = 8;
    parameter outreg_enable = 0;
    
    input_clock wrClk (wrclk) = clk;
    input_clock rdClk (rdclk) = clk;
    input_reset outLatchRst(outlatch_rstn) = rst;
    input_reset outRegRst(outreg_rstn) = rst;
    
    default_clock no_clock;
    no_reset;

    port we = 18'h3FFFF;
    port wrmsel = 1'b0;
    port rdmsel = 1'b0;
    port outreg_ce = 1'b0;


    method putReadReq((*reg*)rdaddr) enable(rden) clocked_by(rdClk) reset_by(no_reset);
    method dout read clocked_by(rdClk) reset_by(no_reset);
    method putWriteReq((*reg*)wraddr, (*reg*)din) enable(wren) clocked_by(wrClk) reset_by(no_reset);    

    schedule putReadReq C putReadReq;
    schedule read CF read;
    schedule putWriteReq C putWriteReq;
    schedule (putReadReq) CF (read);
    // schedule (putReadReq) CF (putWriteReq);
    // schedule (putReadReq, putWriteReq) SB read;

endmodule



module mkBram72kSdpVerilog(BRAM72K_SDP#(tData))
    provisos(
            Bits#(tData, szData)
           );

    function ActionValue#(Integer) getAddrShift;
        return actionvalue
            Integer ret = 0;
            case (valueOf(szData))
                144, 128 : ret = 5;
                72 , 64  : ret = 4;
                36 , 32  : ret = 3;
                18 , 16  : ret = 2;
                9  ,  8  : ret = 1;
                4        : ret = 0;
                default  :
                    immFail("mkBram72kSdpVerilog", $format("BRAM72k data width not supported: %d", valueOf(szData)));
            endcase
            return ret;
        endactionvalue;
    endfunction

    BRAM72K_SDP#(tData) inner <- mkBram72kSdpVerilogInner;
    
    method Action putReadReq(AcxBram72kAddr addr);
        let shiftCnt <- getAddrShift;
        inner.putReadReq(addr << shiftCnt);
    endmethod
    
    method read = inner.read;

    method Action putWriteReq(AcxBram72kAddr addr, tData data);
        let shiftCnt <- getAddrShift;
        inner.putWriteReq(addr << shiftCnt, data);
    endmethod

endmodule




// bluesim module for the BVI imported ACX_BRAM72K_SDP
module mkBram72kSdpBluesim(BRAM72K_SDP#(tData))
    provisos(
            Bits#(tData, szData),
            Add#(a__, szData, BITS_COUNT_72K),
            FShow#(tData)
    );

    RegFile#(AcxBram72kAddr, tData) storage <- mkRegFileFull;
    
    Reg#(AcxBram72kAddr) addrReg <- mkRegU;
    Reg#(tData) outDataDelayReg <- mkRegU;

    RWire#(Tuple2#(AcxBram72kAddr, tData)) writeReqWire <- mkRWire;
    RWire#(AcxBram72kAddr) readReqWire <- mkRWire;


    rule handle;
        if (writeReqWire.wget matches tagged Valid .req) begin
            let {addr, data} = req;
            storage.upd(addr, data);
        end
        let outData = storage.sub(addrReg);
        outDataDelayReg <= outData;
    endrule

    method Action putReadReq(AcxBram72kAddr addr);
        addrReg <= addr;
    endmethod
    
    method read = outDataDelayReg;

    method Action putWriteReq(AcxBram72kAddr addr, tData data);
        writeReqWire.wset(tuple2(addr, data));
    endmethod    

endmodule

module mkBRAM72K_SDP(BRAM72K_SDP#(tData))
    provisos(
            Bits#(tData, szData),
            Add#(a__, szData, BITS_COUNT_72K),
            FShow#(tData)
    );

    BRAM72K_SDP#(tData) _i;
    if (genVerilog) begin
        _i <- mkBram72kSdpVerilog;
    end
    else begin
        _i <- mkBram72kSdpBluesim;
    end
    return _i;
endmodule

interface SdpBram#(type tData);
    interface Put#(Tuple2#(AcxBram72kAddr, tData)) write;
    interface Server#(AcxBram72kAddr, tData) readSrv;
endinterface

module mkSdpBram#(Integer nameId)(SdpBram#(tData)) provisos (
        Bits#(AcxBram72kAddr, szAddr),
        Bits#(tData, szData),
        Bounded#(AcxBram72kAddr),
        Eq#(AcxBram72kAddr),
        Add#(a__, szData, BITS_COUNT_72K),
        FShow#(tData)
    );

    BRAM72K_SDP#(tData) ram <- mkBRAM72K_SDP;


    FIFOF#(Tuple2#(AcxBram72kAddr, tData)) writeReqQ1 <- mkUGLFIFOF;

    FIFOF#(AcxBram72kAddr) readAddrQ1  <- mkUGLFIFOF;

    Wire#(tData) outWire <- mkWire;

    PulseWire hasReadRespWire <- mkPulseWire;
    PulseWire getRespCalledWire <- mkPulseWire;



    (* no_implicit_conditions *)
    rule checkConflict;
        Maybe#(AcxBram72kAddr) writeReqMaybe = tagged Invalid;
        Maybe#(AcxBram72kAddr) readReqMaybe = tagged Invalid;
        let {addr, data} = ?;
        if (writeReqQ1.notEmpty) begin
            writeReqQ1.deq;
            {addr, data} = writeReqQ1.first;
            writeReqMaybe = tagged Valid addr;

            // $display("time=%0t", $time, "nameId=%d", nameId, " BRAM checkConflict, data=", fshow(data));
        end

        if (readAddrQ1.notEmpty) begin
            readAddrQ1.deq;
            readReqMaybe = tagged Valid readAddrQ1.first;
        end
    
        Bool isAddrConflict = (
            isValid(writeReqMaybe) && 
            isValid(readReqMaybe)  &&
            fromMaybe(?, writeReqMaybe) == fromMaybe(?, readReqMaybe)
        );

        Bool hasReadReqInThisBeat = readAddrQ1.notEmpty;

        if (hasReadReqInThisBeat) begin
            // $display("time=%0t", $time, "nameId=%d", nameId, ", isAddrConflict=", fshow(isAddrConflict), ", writeReqMaybe=", fshow(writeReqMaybe), ", readReqMaybe=", fshow(readReqMaybe));
            if (isAddrConflict) begin
                outWire <= data;
            end
            else begin
                outWire <= ram.read;
            end
            hasReadRespWire.send;
        end
    endrule

    rule respGetDelayMonitor;
        if (hasReadRespWire && !getRespCalledWire) begin
            immFail("Has pending bram read result but not read", $format(""));
        end
    endrule

    interface Put write;
        method Action put(Tuple2#(AcxBram72kAddr, tData) req);
            let {addr, data} = req;
            immAssert(writeReqQ1.notFull, "UG FIFO writeReqQ1 is Full when trying to enq", $format(""));
            ram.putWriteReq(addr, data);
            writeReqQ1.enq(tuple2(addr, data));
            // $display("time=%0t", $time, "nameId=%d", nameId, "BRAM write, addr=", fshow(addr), ", data=", fshow(data));
        endmethod
    endinterface

    interface Server readSrv;
        interface Put request;
            method Action put(AcxBram72kAddr addr);
                ram.putReadReq(addr);
                // immAssert(readAddrQ1.notFull, "UG FIFO readAddrQ1 is Full when trying to enq", $format(""));
                readAddrQ1.enq(addr);
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(tData) get;
                getRespCalledWire.send;
                return outWire;
            endmethod
        endinterface
    endinterface
endmodule    