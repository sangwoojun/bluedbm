#set_false_path -from [get_keepers {*|SyncFIFO:*|dGDeqPtr*}] -to [get_keepers {*|SyncFIFO:*|sSyncReg*}]
#set_false_path -from [get_keepers {*|SyncFIFO:*|sGEnqPtr*}] -to [get_keepers {*|SyncFIFO:*|dSyncReg*}]
#set_false_path -from [get_keepers {*|SyncFIFO:*|fifoMem*}] -to [get_keepers {*|SyncFIFO:*|dDoutReg*}]
set_false_path -from [get_ports -hierarchical -filter {NAME=~*SyncFIFO*dGDeqPtr*}] -to [get_ports -hierarchical -filter {NAME=~ *SyncFIFO*sSyncReg*}]
set_false_path -from [get_ports -hierarchical -filter {NAME=~*SyncFIFO*sGEnqPtr*}] -to [get_ports -hierarchical -filter {NAME=~ *SyncFIFO*dSyncReg*}]
set_false_path -from [get_ports -hierarchical -filter {NAME=~*SyncFIFO*fifoMem*}] -to [get_ports -hierarchical -filter {NAME=~ *SyncFIFO*dDoutReg*}]


#set_max_delay -from [get_clocks clk125] -to [get_clocks clk_250mhz] 4.000 -datapath_only
#set_max_delay -from [get_clocks clk_250mhz] -to [get_clocks clk_125mhz] 4.000 -datapath_only

set_false_path -from [get_cells -hierarchical -filter {NAME=~*hwmain_dma_*dGDeqPtr*}] -to [get_cells -hierarchical -filter {NAME=~ *hwmain_dma_*sSyncReg*}]
set_false_path -from [get_cells -hierarchical -filter {NAME=~*hwmain_dma_*sGEnqPtr*}] -to [get_cells -hierarchical -filter {NAME=~ *hwmain_dma_*dSyncReg*}]
set_false_path -from [get_cells -hierarchical -filter {NAME=~*hwmain_dma_*fifoMem*}] -to [get_cells -hierarchical -filter {NAME=~ *hwmain_dma_*dDoutReg*}]

set_false_path -from [get_cells -hierarchical -filter {NAME=~*auroraGearbox_sendQ*dGDeqPtr*}] -to [get_cells -hierarchical -filter {NAME=~ *auroraGearbox_sendQ*sSyncReg*}]
set_false_path -from [get_cells -hierarchical -filter {NAME=~*auroraGearbox_sendQ*sGEnqPtr*}] -to [get_cells -hierarchical -filter {NAME=~ *auroraGearbox_sendQ*dSyncReg*}]
set_false_path -from [get_cells -hierarchical -filter {NAME=~*auroraGearbox_sendQ*fifoMem*}] -to [get_cells -hierarchical -filter {NAME=~ *auroraGearbox_sendQ*dDoutReg*}]

#set_false_path -from [get_cells -hierarchical -filter {NAME=~rst125*}]
