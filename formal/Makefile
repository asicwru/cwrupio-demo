# Formal verification with SymbiYosys.
#   make            run every module check (should all pass)
#   make <module>   run one module, e.g. make sequencer
#   make spec       check docs/isa.md rules the RTL doesn't implement yet (fails until it does)
#   make clean      delete run output
# Needs OSS CAD Suite on PATH: export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"

MODULES := loop_counter program_counter tx_shift_reg rx_shift_reg timing_unit \
           instruction_decoder instruction_memory pin_control sequencer host_interface
TOP     := cwrupio_top

all: $(MODULES) $(TOP)

$(MODULES):
	sby -f $@.sby prove cover

$(TOP):
	sby -f $@.sby bmc cover

spec:
	sby -f $(TOP).sby spec

clean:
	rm -rf $(MODULES) $(TOP) $(foreach m,$(MODULES) $(TOP),$(m)_prove $(m)_cover $(m)_bmc $(m)_spec)

.PHONY: all spec clean $(MODULES) $(TOP)
