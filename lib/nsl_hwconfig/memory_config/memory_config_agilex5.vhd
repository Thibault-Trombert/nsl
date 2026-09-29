-- Agilex 5 MLABs are 640-bit LUT RAMs, 32 words of 20 bits, with an
-- unregistered read output available.
package body memory_config is

  function lutram return lutram_t
  is
  begin
    return lutram_t'(
      present => true,
      async_read => true,
      depth => 32,
      width => 20,
      fifo_depth_max => 64);
  end function;

end package body;
