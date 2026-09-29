-- Xilinx 6-input LUT families (Spartan-6, 7-series): SLICEM LUTs make
-- distributed RAM with asynchronous read. For a simple dual-port
-- memory, RAM32M holds 32 words of 6 bits in four LUTs, RAM64M 64
-- words of 3 bits.
--
-- Up to 64 words, a stored bit costs a third of a LUT with no read
-- mux; at 128 words, a F7 mux joins two such memories. Either is far
-- below the control and prefetch logic of a block RAM FIFO, which is
-- worth its block RAM beyond that.
package body memory_config is

  function lutram return lutram_t
  is
  begin
    return lutram_t'(
      present => true,
      async_read => true,
      depth => 32,
      width => 6,
      fifo_depth_max => 128);
  end function;

end package body;
