import uvm_pkg::*;
`include "uvm_macros.svh"

class fifo_agent extends uvm_agent;
  `uvm_component_utils(fifo_agent)

  fifo_sequencer sqr;
  fifo_driver    drv;
  fifo_monitor   mon;

  function new(string name = "fifo_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = fifo_sequencer::type_id::create("sqr", this);
    drv = fifo_driver::type_id::create("drv", this);
    mon = fifo_monitor::type_id::create("mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass
