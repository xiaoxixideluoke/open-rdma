module bram_single_clock_wr_with_read_bypass#(
        parameter ADDR_WIDTH = 8,
        parameter DATA_WIDTH = 8,
        parameter FILE = "",
        parameter BYPASS_WRITE_DATA = 0
    )(
        output reg [(DATA_WIDTH-1):0] q,
        input [(DATA_WIDTH-1):0] d,
        input [(ADDR_WIDTH-1):0] write_address, read_address,
        input we, clk
    );

    reg [(DATA_WIDTH-1):0] mem [(2**ADDR_WIDTH-1):0];

    initial begin : init_rom_block
        if (FILE != "") begin
            $readmemb(FILE, mem);
        end
        else begin
            // synopsys translate_off
            for (integer row_id = 0; row_id < 2**ADDR_WIDTH; row_id = row_id + 1) begin
                mem[row_id] = 'h0;
            end
            // synopsys translate_on
        end
    end // initial begin


    always @ (posedge clk) begin
        
        
        if (BYPASS_WRITE_DATA) begin
            if (we)
                mem[write_address] = d;
            q = mem[read_address];
        end
        else begin
            if (we)
                mem[write_address] <= d;
            q <= mem[read_address];
        end
    end
endmodule