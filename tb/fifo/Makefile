SIM ?= icarus
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES += $(PWD)/../../src/fifo.sv
VERILOG_SOURCES += $(PWD)/../../src/fifo_system.sv

COMPILE_ARGS += -g2012

TOPLEVEL = fifo_system
COCOTB_TEST_MODULES = test_fifo

include $(shell cocotb-config --makefiles)/Makefile.sim