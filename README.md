# FIFO — UVM Verification with Functional Coverage Closure

A UVM verification environment for an 8×8 synchronous FIFO, built in SystemVerilog and run in Vivado 2026.1 (xsim). Constrained-random stimulus, queue-based reference model, SVA, and a functional coverage model closed to 100%.

The repository also contains the original class-based (non-UVM) testbench the environment was converted from, kept for comparison.

---

## Results

| Metric | Result |
|---|---|
| Transactions driven | 100,001 |
| Simulated time | 1,000,025 ns |
| Scoreboard data comparisons | 46,833 |
| Mismatches | **0** |
| Underflows | **0** |
| Functional coverage | **100% — closed** |
| `UVM_ERROR` / `UVM_FATAL` | 0 / 0 |
| Wall-clock runtime | ~16 s |

```
writes observed : 46840
reads checked   : 46833
matches         : 46833
mismatches      : 0
underflows      : 0
left in queue   : 7
RESULT: PASS -- all data checks matched

FUNCTIONAL COVERAGE
overall        : 100.00%
COVERAGE CLOSED -- all reachable bins hit
```

Writes minus reads equals the residue left in the FIFO (46,840 − 46,833 = 7), so every byte written was either read back and verified or still resident. Nothing was silently dropped.

---

## DUT

An 8-bit wide, 8-deep synchronous FIFO.

- Registered read output (1-cycle read latency)
- `full` / `empty` flag generation
- Concurrent read and write support
- Three inline SVA properties: no write when full, no read when empty, occupancy stays within `[0:8]`

---

## Verification architecture

```
          ┌──────────────────────── fifo_env ────────────────────────┐
          │                                                           │
          │   ┌────────────── fifo_agent ──────────────┐              │
          │   │                                         │             │
 sequence─┼──▶│ sequencer ──▶ driver ──┐       monitor ─┼──analysis──▶│ scoreboard
          │   │                         │          ▲    │    port     │  (reference
          │   └─────────────────────────┼──────────┼────┘             │    model)
          │                             │          │                  │
          └─────────────────────────────┼──────────┼──────────────────┘
                                        ▼          │
                                   ┌── fifo_if (clocking block) ──┐
                                   │                              │
                                   └──────────▶ DUT (main.sv) ────┘
```

| File | Role |
|---|---|
| `main.sv` | DUT — the FIFO itself, with inline SVA |
| `fifo_if.sv` | Interface with clocking block |
| `fifo_transaction.sv` | Sequence item; constrained so illegal stimulus is never generated |
| `fifo_sequence.sv` | Constrained-random stimulus generator |
| `fifo_sequencer.sv` | Sequencer |
| `fifo_driver.sv` | Drives the DUT through the clocking block |
| `fifo_monitor.sv` | Observes the interface, broadcasts transactions, owns the covergroup |
| `fifo_scoreboard.sv` | Queue-based reference model and checker |
| `fifo_agent.sv` | Bundles sequencer + driver + monitor |
| `fifo_env.sv` | Bundles agent + scoreboard |
| `fifo_test.sv` | Top-level test; starts the sequence |
| `fifo_pkg.sv` | Package that includes all classes in dependency order |
| `fifo_uvm_top.sv` | Simulation top: clock, reset, DUT instantiation, `run_test()` |
| `driver.sv` `monitor.sv` `scoreboard.sv` `tb.sv` | Original non-UVM testbench, kept for comparison |

---

## Running it

**Vivado setup**

1. Add to Simulation Sources: `fifo_if.sv`, `main.sv`, `fifo_pkg.sv`, `fifo_uvm_top.sv`, and the nine `fifo_*.sv` class files
2. Set the nine class files to file type **Verilog Header** — they are compiled via `fifo_pkg.sv`, never standalone
3. Simulation top: `fifo_uvm_top`
4. Settings → Simulation → **Elaboration** → `xelab.more_options`: add `-L uvm`
5. Run Behavioral Simulation, then **Run All** (the default 1000 ns runtime truncates the test)

**Compile order:** `fifo_if.sv` → `main.sv` → `fifo_pkg.sv` → `fifo_uvm_top.sv`

**Runtime options** (`xsim.simulate.more_options`)

| Option | Effect |
|---|---|
| `+RUNCYCLES=<n>` | Set transaction count without recompiling (default 100,001) |
| `+UVM_VERBOSITY=UVM_HIGH` | Print every individual data check |

---

## Functional coverage

The covergroup lives in the monitor and samples once per clock.

| Coverpoint | What it proves |
|---|---|
| `cp_op` | All four operations issued: IDLE / READ / WRITE / BOTH |
| `cp_full` | Full was reached **and** transitioned into and out of (`0=>1`, `1=>0`) |
| `cp_empty` | Empty was reached and transitioned into and out of |
| `cp_occ` | Every occupancy level 0–8 was visited |
| `cx_op_full` | Which operations occurred while full |
| `cx_op_empty` | Which operations occurred while empty |

### Unreachable is not uncovered

An earlier covergroup used four 1-bit coverpoints (`wr_en`, `rd_en`, `full`, `empty`) and a single cross. It reported 100% within a few hundred cycles while proving almost nothing — every bin is trivially hit by random traffic. It was replaced with the model above, which measures FIFO *behaviour*: transitions, occupancy levels, and operation-vs-state corners.

That model first reported **83.33%**, with both crosses at 50%. The four unhit bins were:

- WRITE while full
- BOTH while full
- READ while empty
- BOTH while empty

None of these are stimulus gaps. They are forbidden by the transaction constraints (`c_no_write_when_full`, `c_no_read_when_empty`) and by the DUT's own SVA. Reaching them would have meant loosening constraints to generate illegal stimulus purely to inflate a metric.

They are instead declared `illegal_bins`, which removes them from the coverage denominator *and* raises a runtime error if they are ever hit — turning a documented assumption into an active check. Across 100,001 cycles none fired, so the constraint contract is confirmed three independent ways: the solver refuses to generate the combinations, the DUT's SVA never asserts, and the coverage model never flags them.

`ignore_bins` is used separately to narrow each cross to the question being asked; a cross diluted with uninteresting combinations yields a percentage nobody can interpret.

The monitor's `report_phase` prints the per-coverpoint breakdown and emits `COVERAGE CLOSED` at 100%, or a `uvm_warning` below it — so closure is machine-checkable rather than eyeballed.

---

## Notable debug: a one-cycle data shift

After the environment was running, the scoreboard reported 38 mismatches with a distinctive signature:

```
@85000  MISMATCH Expected=92  Got=0
@115000 MISMATCH Expected=123 Got=92
@195000 MISMATCH Expected=199 Got=123
```

`Got` was always the *previous* `Expected` — every read was returning the prior read's data, with the first returning the reset value.

**Cause.** The driver was assigning the raw interface signals at a clock edge:

```systemverilog
@(posedge vif.clk);
vif.wr_en <= tr.wr_en;      // races the DUT's always_ff on the same edge
```

Testbench assignment and DUT sampling landed on the same edge, shifting all data by one cycle.

**Fix.** Drive through the clocking block, which applies values at its defined output skew:

```systemverilog
@(vif.cb);
vif.cb.wr_en <= tr.wr_en;
```

Zero mismatches on the next run. The same transaction that previously failed at 85,000 ns passed with the identical expected value.

---

## Other issues resolved during bring-up

| Symptom | Cause | Fix |
|---|---|---|
| `fifo_transaction not declared` | Class files compiled as separate compilation units couldn't see each other | Wrap all classes in a package |
| `UVM_FATAL: Requested test not found` | Top named the test only as a string, so classes were never elaborated and the factory never registered them | `import fifo_pkg::*;` in the top module |
| `UVM_FATAL [RUNPHSTIME]` | Reset consumed 15 ns before `run_test()` | Reset moved to a concurrent `initial` block; driver and monitor wait on `rst` |
| `embedded coverage group cannot be instantiated outside new()` | Covergroup constructed in `build_phase` | Construct in `new()` — coverpoint expressions evaluate at `sample()` time, so a not-yet-resolved `vif` is fine |

---

## Design notes

- **Declarative constraints over procedural patching.** Illegal stimulus is prevented by the solver rather than generated and then corrected.
- **Stimulus independent of the DUT.** The sequence tracks its own `expected_count` instead of reading `full`/`empty`, so generation never races the design.
- **Analysis ports over direct calls.** The monitor broadcasts; it has no knowledge of the scoreboard. Consumers can be added without touching monitor code.
- **Factory construction throughout.** Every component is built with `type_id::create`, so any of them can be substituted from the test level via a factory override without editing structural code.
- **Reporting over printing.** Per-check messages are emitted at `UVM_HIGH` and filtered by default; the scoreboard and monitor each print one consolidated summary in `report_phase`. This dropped the log from 600 KB to a handful of lines.
- **A test that checks nothing must not pass.** The scoreboard raises an error if zero comparisons were performed, so a broken environment cannot report "0 mismatches" and look healthy.

---

## Scope

**Not parameterized.** `DATA_WIDTH` and `FIFO_DEPTH` are fixed at 8.

**No formal verification.** The SVA properties are checked in simulation only. Proving them requires an external tool — Vivado ships no formal property checker.

Both are stated here rather than left implied.

---

## Next

- **AXI4-Lite UVM VIP** — master/slave agents, protocol checker, coverage model. Introduces independent channel handshakes, `VALID`/`READY` dependency rules, write-response ordering and outstanding transactions.
- **Asynchronous FIFO with CDC** — two-clock design, gray-code pointers, synchronizer chains.
