-- Lattice families with distributed RAM in their PFUs (ECP5, MachXO2,
-- Nexus): DPR16X4, 16 words of 4 bits, asynchronous read. Same
-- granularity as Gowin SSRAM, hence the same break-even depth against
-- a block RAM FIFO.
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
