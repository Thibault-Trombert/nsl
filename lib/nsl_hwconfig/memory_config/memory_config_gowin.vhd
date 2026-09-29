-- Gowin devices (GW1N, GW2A, GW5A) implement LUT RAM as Shadow SRAM,
-- one CFU making a RAM16SDP4: 16 words of 4 bits, asynchronous read.
--
-- A CFU in SSRAM mode is the area of 8 LUT4. Past 16 words, every
-- further 16 words take another set of primitives plus a read mux
-- stage. At 64 words, a 32-bit FIFO takes 32 SSRAM, about 256 LUT4
-- worth of fabric, where a block RAM FIFO takes one BSRAM along with
-- about 170 LUT and 230 registers of control and prefetch logic: this
-- is about where both costs meet.
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
