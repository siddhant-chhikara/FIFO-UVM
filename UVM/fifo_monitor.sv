import uvm_pkg::*;
`include "uvm_macros.svh"

class fifo_monitor extends uvm_monitor;
  `uvm_component_utils(fifo_monitor)

  virtual fifo_if vif;
  uvm_analysis_port #(fifo_transaction) ap;

  bit rd_en_d1 = 0;

  // sampled operation type, mirrors the IDLE/READ/WRITE/BOTH idea from the
  // original testbench -- sampled as a 2-bit code {wr_en, rd_en}
  bit [1:0]     op;
  int unsigned  occ = 0;   // monitor's own model of FIFO occupancy (0..8)

  covergroup cg;
    // what operation was issued this cycle
    cp_op : coverpoint op {
      bins IDLE  = {2'b00};
      bins READ  = {2'b01};
      bins WRITE = {2'b10};
      bins BOTH  = {2'b11};
    }

    // flag states, plus the transitions into and out of them --
    // "did we actually reach full and come back" is the interesting part
    cp_full : coverpoint vif.full {
      bins not_full   = {0};
      bins is_full    = {1};
      bins fill_up    = (0 => 1);
      bins drain_off  = (1 => 0);
    }

    cp_empty : coverpoint vif.empty {
      bins not_empty   = {0};
      bins is_empty    = {1};
      bins go_empty    = (0 => 1);
      bins leave_empty = (1 => 0);
    }

    // every occupancy level the FIFO can sit at
    cp_occ : coverpoint occ {
      bins lvl[] = {[0:8]};
    }

    // Corner cases that matter: which operations occur while full / empty.
    //
    // ignore_bins  -> narrows the cross to the question being asked
    // illegal_bins -> combinations the stimulus constraints make impossible
    //                 (c_no_write_when_full / c_no_read_when_empty) and that
    //                 the DUT's own SVA also forbids. Declaring them illegal
    //                 removes them from the coverage denominator AND errors at
    //                 runtime if they are ever hit -- an assumption turned into
    //                 an active check.
    cx_op_full  : cross cp_op, cp_full {
      ignore_bins  nf             = binsof(cp_full.not_full);
      ignore_bins  tr             = binsof(cp_full.fill_up) || binsof(cp_full.drain_off);
      illegal_bins wr_when_full   = binsof(cp_op.WRITE) && binsof(cp_full.is_full);
      illegal_bins both_when_full = binsof(cp_op.BOTH)  && binsof(cp_full.is_full);
    }

    cx_op_empty : cross cp_op, cp_empty {
      ignore_bins  ne              = binsof(cp_empty.not_empty);
      ignore_bins  tr              = binsof(cp_empty.go_empty) || binsof(cp_empty.leave_empty);
      illegal_bins rd_when_empty   = binsof(cp_op.READ) && binsof(cp_empty.is_empty);
      illegal_bins both_when_empty = binsof(cp_op.BOTH) && binsof(cp_empty.is_empty);
    }
  endgroup

  function new(string name = "fifo_monitor", uvm_component parent = null);
    super.new(name, parent);
    cg = new();   // embedded covergroups MUST be constructed in new()
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found")
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    fifo_transaction tr;

    wait (vif.rst == 0);

    forever begin
      @(vif.cb);

      // update the sampled variables BEFORE sampling the covergroup
      op = {vif.wr_en, vif.rd_en};
      cg.sample();

      // WRITE
      if (vif.wr_en && !vif.full) begin
        tr = fifo_transaction::type_id::create("tr");
        tr.wr_en = 1;
        tr.rd_en = 0;
        tr.wr_ip = vif.wr_ip;
        ap.write(tr);
        if (occ < 8) occ++;
      end

      // READ (1-cycle delay, same as original testbench)
      rd_en_d1 <= vif.rd_en;
      if (rd_en_d1) begin
        tr = fifo_transaction::type_id::create("tr");
        tr.wr_en = 0;
        tr.rd_en = 1;
        tr.wr_ip = vif.rd_op;   // reusing wr_ip to carry observed read data
        ap.write(tr);
        if (occ > 0) occ--;
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    real cov;
    super.report_phase(phase);
    cov = cg.get_coverage();

    `uvm_info("COV", $sformatf(
      "\n  FUNCTIONAL COVERAGE\n  overall        : %0.2f%%\n  cp_op          : %0.2f%%\n  cp_full        : %0.2f%%\n  cp_empty       : %0.2f%%\n  cp_occ         : %0.2f%%\n  cx_op_full     : %0.2f%%\n  cx_op_empty    : %0.2f%%",
      cov,
      cg.cp_op.get_coverage(),
      cg.cp_full.get_coverage(),
      cg.cp_empty.get_coverage(),
      cg.cp_occ.get_coverage(),
      cg.cx_op_full.get_coverage(),
      cg.cx_op_empty.get_coverage()), UVM_LOW)

    if (cov >= 100.0)
      `uvm_info("COV", "COVERAGE CLOSED -- all reachable bins hit", UVM_LOW)
    else
      `uvm_warning("COV", $sformatf("Coverage NOT closed: %0.2f%%", cov))
  endfunction

endclass
