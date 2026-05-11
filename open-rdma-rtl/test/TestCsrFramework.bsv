import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;

import PrimUtils :: *;

import Utils4Test :: *;

import AddressChunker :: *;
import BasicDataTypes :: *;
import RdmaHeaders :: *;
import ClientServer :: *;
import ConnectableF::*;
import CsrFramework :: *;



interface TestCsrNodeTiming;
    method Byte getOutput;
endinterface


(* synthesize *)
(* doc = "testcase" *)
module mkTestCsrNodeTiming(CsrNode#(ADDR, Dword, NUMERIC_TYPE_FOUR));

endmodule