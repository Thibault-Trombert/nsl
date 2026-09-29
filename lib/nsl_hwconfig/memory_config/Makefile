vhdl-sources += memory_config.pkg.vhd

# Exactly one package body per target. Each branch nests its own
# fallback so that no two bodies are ever selected together.
ifneq ($(filter gowin,$(hwdep)),)
vhdl-sources += memory_config_gowin.vhd
else
ifneq ($(filter xc6s%,$(target_part))$(filter xc7%,$(target_part)),)
vhdl-sources += memory_config_xilinx_lut6.vhd
else
ifneq ($(filter lattice-ecp5,$(hwdep))$(filter lattice-machxo2,$(hwdep))$(filter lattice-nexus,$(hwdep)),)
vhdl-sources += memory_config_lattice_dpr16x4.vhd
else
ifneq ($(filter A5E%,$(target_part)),)
vhdl-sources += memory_config_agilex5.vhd
else
ifeq ($(hwdep),simulation)
vhdl-sources += memory_config_simulation.vhd
else
vhdl-sources += memory_config_none.vhd
endif
endif
endif
endif
endif
