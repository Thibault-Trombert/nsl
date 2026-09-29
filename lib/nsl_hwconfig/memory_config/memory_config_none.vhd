-- Targets without LUT RAM (iCE40, Cyclone 10 LP) and any target this
-- partition has no specific knowledge of. An array read asynchronously
-- becomes registers there, so generic code should rather use block
-- RAM for anything but a few words.
package body memory_config is

  function lutram return lutram_t
  is
  begin
    return lutram_t'(
      present => false,
      async_read => false,
      depth => 0,
      width => 0,
      fifo_depth_max => 0);
  end function;

end package body;
