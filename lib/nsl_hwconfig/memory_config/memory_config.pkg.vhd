-- Memory resources of the target device, as far as generic code needs
-- to know about them to pick an implementation.
--
-- The package declaration is common to every target, the build selects
-- one package body per device family. Code reading these facts only
-- trades cost: behavior of anything built upon them must stay the
-- same whatever the answer.
package memory_config is

  -- LUT RAM, also called distributed RAM: logic cells used as small
  -- memories.
  type lutram_t is
  record
    -- Target has LUT RAM that the synthesizer infers from generic RTL.
    present: boolean;
    -- Its read port is asynchronous: read data follows the read
    -- address within the cycle, without a clock edge.
    async_read: boolean;
    -- Word count and word width of one primitive in simple dual-port
    -- mode (one write port, one read port), for its shallowest
    -- configuration. A memory of D words of W bits takes at least
    -- ceil(D / depth) * ceil(W / width) primitives. Zero when absent.
    depth: natural;
    width: natural;
    -- Deepest FIFO that is cheaper in LUT RAM than in block RAM along
    -- with the control logic a block RAM FIFO takes. Zero when absent.
    fifo_depth_max: natural;
  end record;

  function lutram return lutram_t;

end package;
