// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class ibex_icache_mem_monitor
  extends dv_base_monitor #(.ITEM_T (ibex_icache_mem_resp_item),
                            .CFG_T  (ibex_icache_mem_agent_cfg),
                            .COV_T  (ibex_icache_mem_agent_cov));

  `uvm_component_utils(ibex_icache_mem_monitor)
  `uvm_component_new

  // the base class provides the following handles for use:
  // ibex_icache_mem_agent_cfg: cfg
  // ibex_icache_mem_agent_cov: cov
  // uvm_analysis_port #(ibex_icache_resp_item): analysis_port

  // Incoming requests. This gets hooked up to the sequencer to service requests
  uvm_analysis_port #(ibex_icache_mem_req_item) request_port;

  function automatic void build_phase(uvm_phase phase);
    super.build_phase(phase);
    request_port = new("request_port", this);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
  endtask

  // Collect transactions forever. Forked in dv_base_moditor::run_phase
  protected task automatic collect_trans(uvm_phase phase);
    fork
      collect_requests();
      collect_grants();
    join
  endtask

  // The collect_requests monitor is in charge of spotting changes to instr_addr_o when the req
  // line is high
  //
  // This must collect the "I have a new address request" immediately, rather than at the next clock
  // edge, to make sure that a PMP error can be signalled in the same cycle.
  //
  // Note that it's possible the underlying memory seed will change after the request has been seen.
  // We don't try to spot this, and instead report the error state based on the seed when the
  // request appeared.
  task automatic collect_requests();
    forever begin
      // Wait for either a posedge on req or any change to the address
      @(posedge cfg.vif.req or cfg.vif.addr);

      // If the req line is high, pass the "new address" request to the driver
      if (cfg.vif.req)
        new_request(cfg.vif.addr);
    end
  endtask

  // The collect_grants monitor is in charge of spotting granted requests which haven't been
  // squashed by a PMP error, passing them back to the driver ("Hey, you granted this. Time to
  // service it!")
  task automatic collect_grants();
    logic pending_req = 1'b0;

    forever begin
      if (cfg.vif.monitor_cb.req & cfg.vif.monitor_cb.gnt & !cfg.vif.monitor_cb.pmp_err)
        new_grant(cfg.vif.monitor_cb.addr);

      @(cfg.vif.monitor_cb);
    end
  endtask

  // This is called immediately when an address is requested and is used to drive the PMP response
  function automatic void new_request(logic [31:0] addr);
    ibex_icache_mem_req_item item = new("item");

    item.is_grant = 1'b0;
    item.address = addr;
    item.seed = '0;
    request_port.write(item);
  endfunction

  // This is called on a clock edge when an request is granted
  function automatic void new_grant(logic [31:0] addr);
    ibex_icache_mem_req_item item = new("item");

    item.is_grant = 1'b1;
    item.address = addr;
    `DV_CHECK_RANDOMIZE_FATAL(item)
    request_port.write(item);
  endfunction

endclass
