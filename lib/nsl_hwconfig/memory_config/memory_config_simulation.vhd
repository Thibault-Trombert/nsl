-- Simulation without a target vendor. Costs mean nothing here, answer
-- as a typical device with 16x4 LUT RAM would so that simulation
-- selects the same implementations most targets do.
package body memory_config is

  function lutram return lutram_t
  is
  begin
    return lutram_t'(
      present => true,
      async_read => true,
      depth => 16,
      width => 4,
      fifo_depth_max => 64);
  end function;

end package body;
