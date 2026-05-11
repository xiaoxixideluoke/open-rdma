import GetPut :: *;
import ConnectableF :: *;
import PrimUtils :: *;
import DtldStream :: *;
import BasicDataTypes :: *;


typedef DtldStreamData#(DATA) DataStream;
typedef PipeOut#(DataStream) DataStreamPipeOut;
typedef Put#(DataStream) DataStreamPipeIn;


typedef DtldStreamData#(DESC_DATA) DescDataStream;
typedef PipeOut#(DescDataStream) DescDataStreamPipeOut;
typedef Put#(DescDataStream) DewsDataStreamPipeIn;