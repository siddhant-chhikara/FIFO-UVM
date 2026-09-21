import uvm_pkg::*;
`include "uvm_macros.svh"

class fifo_driver extends uvm_driver #(fifo_transaction);
  `uvm_component_utils(fifo_driver)

  virtual fifo_if vif;

  function new(string name = "fifo_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found")
  endfunction

  task run_phase(uvm_phase phase);
    fifo_transaction tr;

    // drive through the clocking block (vif.cb.*), never the raw signals --
    // raw drives at @(posedge clk) race with the DUT's always_ff sampling on
    // the same edge and shift everything by one cycle
    vif.cb.wr_en <= 0;
    vif.cb.rd_en <= 0;
    vif.cb.wr_ip <= 0;

    // hold off until reset deasserts -- reset runs concurrently in the top module
    wait (vif.rst == 0);

    forever begin
      seq_item_port.get_next_item(tr);
      @(vif.cb);
      vif.cb.wr_en <= tr.wr_en;
      vif.cb.rd_en <= tr.rd_en;
      vif.cb.wr_ip <= tr.wr_ip;
      seq_item_port.item_done();
    end
  endtask

endclass
