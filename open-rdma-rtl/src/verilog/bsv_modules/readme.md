This dir contains some verilog files copied from bluespec's source code, and someone may be modified.

The reasons that some files goes into this dir is:

1. some verilog files need special attribute to make backend tools work as expected, so we need to modify the original file.
    * `SyncFIFO.v`  add the `/*synthesis syn_ramstyle = "registers"*/` attribute
2. some verilog files can't be copied by `listVlogFiles.tcl`
    * `SyncHandshake.v`