set vivado_backend_dir		$::env(VIVADO_BACKEND_DIR)
set vivado_work_dir 		$::env(VIVADO_WORKDIR)
set project_name  			$::env(PROJ_NAME)
set top_module 				$::env(TOP)

set rtl_dirs 				$::env(RTL_DIRS)
set sdc_dirs 				$::env(VIVADO_SDC_DIRS)

set eth_ip_type             $::env(BLUE_RDMA_ETH_IP_TYPE)
set dma_ip_type             $::env(BLUE_RDMA_DMA_IP_TYPE)

set part $::env(VIVADO_PART)
set device [get_parts $part]; # xcvu13p-fhgb2104-2-i; #

set current_time [clock format [clock seconds] -format "%Y-%m-%d-%H-%M-%S"]

proc runGenerateIP {vivado_work_dir rtl_dir_list sdc_dir_list vivado_backend_dir} {
    global device

    set_part $device

    set sdc_snapshot_dir "$vivado_work_dir/sdc_snapshot_dir"
    set dir_ips "$vivado_backend_dir/ips"

    set dir_ip_gen "$vivado_backend_dir/ip_generated"
    file mkdir $dir_ip_gen


    read_xdc [ glob $sdc_snapshot_dir/*.sdc ]

    foreach file [ glob $dir_ips/**/*.tcl ] {
        source $file
    }

    report_property $device -file $vivado_work_dir/pre_synth_dev_prop.rpt
    reset_target all [ get_ips * ]
    generate_target all [ get_ips * ]

}

proc runSynthIP {vivado_work_dir rtl_dir_list sdc_dir_list vivado_backend_dir} {
    global device

    set_part $device

    set sdc_snapshot_dir "$vivado_work_dir/sdc_snapshot_dir"
    set dir_ip_gen "$vivado_backend_dir/ip_generated"

    read_xdc [ glob $sdc_snapshot_dir/*.sdc ]
    
    read_ip [glob $dir_ip_gen/**/*.xci]
    # The following line will generate a .dcp checkpoint file, so no need to create by ourselves
    synth_ip [ get_ips * ] -quiet
}

proc build_snapshot_dir_and_file_list {snapshot_dir snapshot_file_list filetype dir_list } {
	
	foreach dir $dir_list {
		foreach filename [ glob -- $dir] {
			set filename_without_path [file tail $filename]
			set snapshot_file_name "$snapshot_dir/$filename_without_path"

			# create snapshot of RTL files, so different compile version won't affact each other
			file copy -force $filename $snapshot_file_name

			puts "add file to RTL snapshot: $filename"
			lappend snapshot_file_list [list $filetype $snapshot_file_name]
		}
	}
	return $snapshot_file_list
}


proc createSourceSnapshot {vivado_work_dir rtl_dir_list sdc_dir_list vivado_backend_dir} {
    global dir_ip_gen part device


    set verilog_snapshot_dir "$vivado_work_dir/verilog_snapshot_dir"
	set sdc_snapshot_dir "$vivado_work_dir/sdc_snapshot_dir"

	file mkdir $verilog_snapshot_dir
	file mkdir $sdc_snapshot_dir

	set snapshot_file_list {}

	# add our own files (especially sdc files) last, so all the signals provided by other IP will be available.
	set snapshot_file_list [build_snapshot_dir_and_file_list $verilog_snapshot_dir $snapshot_file_list "VERILOG_FILE" $rtl_dir_list]
	set snapshot_file_list [build_snapshot_dir_and_file_list $sdc_snapshot_dir $snapshot_file_list "SDC_FILE" $sdc_dir_list]
}

proc createProject {vivado_work_dir rtl_dir_list sdc_dir_list vivado_backend_dir} {
    global part device 
    set_part $device
    set_param general.maxthreads 24

    set dir_ip_gen "$vivado_backend_dir/ip_generated"

    set verilog_snapshot_dir "$vivado_work_dir/verilog_snapshot_dir"
	set sdc_snapshot_dir "$vivado_work_dir/sdc_snapshot_dir"

    read_ip [glob $dir_ip_gen/**/*.xci]

    read_verilog [ glob $verilog_snapshot_dir/*.v ]

    read_xdc [ glob $sdc_snapshot_dir/*.sdc ]

}


proc runSynthDesign {args} {
	global vivado_work_dir top_module eth_ip_type dma_ip_type
	synth_design -top $top_module -flatten_hierarchy rebuilt -verilog_define "BLUE_RDMA_ETH_IP_TYPE_${eth_ip_type} BLUE_RDMA_DMA_IP_TYPE_${dma_ip_type}"

    source batch_insert_ila.tcl
    batch_insert_ila 256

    file copy -force "debug_nets.ltx" $vivado_work_dir/debug_nets.ltx

	write_checkpoint -force $vivado_work_dir/post_synth_design.dcp
    write_xdc -force -exclude_physical $vivado_work_dir/post_synth.xdc
}

proc runPlacement {args} {
    global vivado_work_dir top_module current_time

    if {[dict get $args -open_checkpoint] == true} {
        open_checkpoint $vivado_work_dir/post_synth_design.dcp
    }

    opt_design -remap -verbose

    if {[dict exist $args -directive]} {
        set directive [dict get $args -directive]
        place_design -verbose  -directive ${directive}
    } else {
        set directive ""
        place_design -verbose 
    }

    file mkdir $vivado_work_dir/${current_time}_${directive}
    write_checkpoint -force $vivado_work_dir/${current_time}_${directive}/post_place.dcp
    write_xdc -force -exclude_physical $vivado_work_dir/${current_time}_${directive}/post_place.xdc
}

proc runRoute {args} {
    global vivado_work_dir

    if {[dict get $args -open_checkpoint] == true} {
        open_checkpoint $vivado_work_dir/post_place.dcp
    }

    route_design

    proc runPPO { {num_iters 1} {enable_phys_opt 1} } {
        global vivado_work_dir
        for {set idx 0} {$idx < $num_iters} {incr idx} {
            place_design -post_place_opt; # Better to run after route
            if {$enable_phys_opt != 0} {
                phys_opt_design
            }
            route_design
            if {[get_property SLACK [get_timing_paths ]] >= -0.05} {
                break; # Stop if timing closure
            }

            write_checkpoint -force $vivado_work_dir/post_route_$idx.dcp
        }
    }

    write_checkpoint -force $vivado_work_dir/post_route.dcp
    runPPO 10 1; # num_iters=4, enable_phys_opt=1

    write_checkpoint -force $vivado_work_dir/post_route.dcp
    write_xdc -force -exclude_physical $vivado_work_dir/post_route.xdc

    write_verilog -force $vivado_work_dir/post_impl_netlist.v -mode timesim -sdf_anno true

}

proc runWriteBitStream {args} {
    global vivado_work_dir

    if {[dict get $args -open_checkpoint] == true} {
        open_checkpoint $vivado_work_dir/post_route.dcp
    }

    set_property CONFIG_MODE SPIx4 [current_design]
    set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

    write_bitstream -force $vivado_work_dir/top.bit
}

createSourceSnapshot $vivado_work_dir $rtl_dirs $sdc_dirs $vivado_backend_dir
# runGenerateIP $vivado_work_dir $rtl_dirs $sdc_dirs $vivado_backend_dir
# runSynthIP $vivado_work_dir $rtl_dirs $sdc_dirs $vivado_backend_dir

createProject $vivado_work_dir $rtl_dirs $sdc_dirs $vivado_backend_dir

runSynthDesign


runPlacement -open_checkpoint -false -directive ExtraNetDelay_high
runRoute -open_checkpoint -false

runWriteBitStream -open_checkpoint -false

#place_design -directive ExtraNetDelay_high; phys_opt_design -placement_opt; route_design -directive AggressiveExplore; phys_opt_design -placement_opt;