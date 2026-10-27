FST ?= -fst # write real FST waveforms

SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../../src

PROJECT_SOURCES = cwrupio_pkg.sv instruction_memory.sv program_counter.sv \
                  instruction_decoder.sv sequencer.sv timing_unit.sv \
                  loop_counter.sv tx_shift_reg.sv rx_shift_reg.sv \
                  host_interface.sv pin_control.sv cwrupio_top.sv

VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
VERILOG_SOURCES += $(PWD)/tb_spi_mode0.sv
COMPILE_ARGS += -g2012
TOPLEVEL = tb_spi_mode0
COCOTB_TEST_MODULES = test_spi_mode0

include $(shell cocotb-config --makefiles)/Makefile.sim