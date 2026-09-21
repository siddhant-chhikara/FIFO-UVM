// Bundles every UVM class into one package (one shared scope, compiled in dependency order).
// Only THIS file gets compiled for the classes -- the individual fifo_*.sv class files are pulled in via `include.
package fifo_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "fifo_transaction.sv"
  `include "fifo_sequence.sv"
  `include "fifo_sequencer.sv"
  `include "fifo_driver.sv"
  `include "fifo_monitor.sv"
  `include "fifo_scoreboard.sv"
  `include "fifo_agent.sv"
  `include "fifo_env.sv"
  `include "fifo_test.sv"

endpackage
