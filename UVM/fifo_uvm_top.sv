`timescale 1ns / 1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import fifo_pkg::*;   // makes every UVM class (incl. fifo_test) visible and registered with the factory

module fifo_uvm_top;

  logic clk;
  fifo_if intf(clk);

  main dut (
    .clk(clk),
    .rst(intf.rst),
    .wr_en(intf.wr_en),
    .rd_en(intf.rd_en),
    .wr_ip(intf.wr_ip),
    .rd_op(intf.rd_op),
    .full(intf.full),
    .empty(intf.empty)
  );

  // clock generation
  initial clk = 0;
  always #5 clk = ~clk;

  // reset generation -- runs CONCURRENTLY with UVM, not before it.
  // driver/monitor each wait for rst to deassert before acting.
  initial begin
    intf.rst = 1;
    repeat (2) @(posedge clk);
    intf.rst = 0;
  end

  // UVM entry point -- must be called at time 0, no delays before it
  initial begin
    uvm_config_db#(virtual fifo_if)::set(null, "*", "vif", intf);
    run_test("fifo_test");
  end

endmodule
