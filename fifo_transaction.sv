import uvm_pkg::*;
`include "uvm_macros.svh"

class fifo_transaction extends uvm_sequence_item;
  `uvm_object_utils(fifo_transaction)

  rand bit [7:0] wr_ip;
  rand bit       wr_en;
  rand bit       rd_en;

  int unsigned expected_count;

  constraint c_no_write_when_full { (expected_count == 8) -> wr_en == 0; }
  constraint c_no_read_when_empty { (expected_count == 0) -> rd_en == 0; }

  function new(string name = "fifo_transaction");
    super.new(name);
  endfunction

endclass