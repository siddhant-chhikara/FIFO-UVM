import uvm_pkg::*;
`include "uvm_macros.svh"

class fifo_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(fifo_scoreboard)

  uvm_analysis_imp #(fifo_transaction, fifo_scoreboard) imp;

  int q[$];

  // running tallies -- printed once in report_phase instead of one line per check
  int unsigned num_writes     = 0;
  int unsigned num_matches    = 0;
  int unsigned num_mismatches = 0;
  int unsigned num_underflows = 0;

  function new(string name = "fifo_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    imp = new("imp", this);
  endfunction

  // Mandatory callback -- UVM calls this whenever the monitor does ap.write(tr)
  function void write(fifo_transaction tr);
    if (tr.wr_en) begin
      q.push_back(tr.wr_ip);
      num_writes++;
    end
    else if (tr.rd_en) begin
      if (q.size() == 0) begin
        num_underflows++;
        `uvm_error("UNDERFLOW", "Read observed with empty reference queue")
      end
      else begin
        int exp;
        exp = q.pop_front();
        if (exp == tr.wr_ip) begin
          num_matches++;
          // UVM_HIGH so this is filtered out at default verbosity -- keeps the
          // log usable on long runs. Raise verbosity to see every check.
          `uvm_info("PASS", $sformatf("Data match: %0d", tr.wr_ip), UVM_HIGH)
        end
        else begin
          num_mismatches++;
          `uvm_error("MISMATCH", $sformatf("Expected=%0d Got=%0d", exp, tr.wr_ip))
        end
      end
    end
  endfunction

  // runs after run_phase completes -- one consolidated result instead of N lines
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SB_SUMMARY", $sformatf(
      "\n  writes observed : %0d\n  reads checked   : %0d\n  matches         : %0d\n  mismatches      : %0d\n  underflows      : %0d\n  left in queue   : %0d",
      num_writes, num_matches + num_mismatches, num_matches,
      num_mismatches, num_underflows, q.size()), UVM_LOW)

    if (num_mismatches == 0 && num_underflows == 0 && (num_matches + num_mismatches) > 0)
      `uvm_info("SB_SUMMARY", "RESULT: PASS -- all data checks matched", UVM_LOW)
    else if ((num_matches + num_mismatches) == 0)
      `uvm_error("SB_SUMMARY", "RESULT: NO CHECKS PERFORMED -- scoreboard saw no reads")
  endfunction

endclass
