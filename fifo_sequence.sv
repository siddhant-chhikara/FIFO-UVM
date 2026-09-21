class fifo_sequence extends uvm_sequence #(fifo_transaction);
  `uvm_object_utils(fifo_sequence)

  // Default run length. Override at runtime WITHOUT recompiling:
  //   +RUNCYCLES=1000000
  // (Settings > Simulation > Simulation tab > xsim.simulate.more_options)
  int unsigned run_cycles = 100001;

  int unsigned expected_count = 0;

  function new(string name = "fifo_sequence");
    super.new(name);
  endfunction

  task body();
    fifo_transaction tr;

    void'($value$plusargs("RUNCYCLES=%d", run_cycles));
    `uvm_info("SEQ", $sformatf("Driving %0d transactions", run_cycles), UVM_LOW)

    repeat (run_cycles) begin
      tr = fifo_transaction::type_id::create("tr");

      start_item(tr);
      tr.expected_count = expected_count;
      tr.randomize();
      finish_item(tr);

      if (tr.wr_en && !tr.rd_en)
        expected_count = expected_count + 1;
      else if (tr.rd_en && !tr.wr_en)
        expected_count = expected_count - 1;
    end
  endtask

endclass
