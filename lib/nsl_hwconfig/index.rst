=========================
 Target hardware facts
=========================

`nsl_hwconfig` holds facts about the target device that library code
needs at elaboration time: PLL and IO delay limits, oscillators, memory
resources.  Packages are selected by the build from the target filter
variables (`hwdep`, `target_part`, `target_part_name`), so a design
never names its vendor to use them.

Vendor packages
===============

``gowin_config``, ``xc6_config``, ``xc7_config``,
``cyclone10lp_config`` and ``agilex5_config`` only exist in builds for
their vendor, and are only used by vendor-specific implementation
variants.

Memory resources
================

``memory_config`` exists in every build.  Its declaration is common,
its body is picked per target family.  ``lutram`` returns a
``lutram_t`` record:

``present``
  the target has LUT RAM the synthesizer infers from generic RTL;

``async_read``
  its read port is asynchronous;

``depth``, ``width``
  words and bits of one primitive in simple dual-port mode, in its
  shallowest configuration;

``fifo_depth_max``
  deepest fifo that is cheaper in LUT RAM than in block RAM with the
  control logic of a block RAM fifo.

.. list-table::
   :header-rows: 1

   * - Target
     - Primitive
     - ``depth`` x ``width``
     - ``fifo_depth_max``
   * - Gowin (GW1N, GW2A, GW5A)
     - RAM16SDP4 (SSRAM)
     - 16 x 4
     - 64
   * - Xilinx Spartan-6, 7-series
     - RAM32M / RAM64M
     - 32 x 6
     - 128
   * - Lattice ECP5, MachXO2, Nexus
     - DPR16X4
     - 16 x 4
     - 64
   * - Intel Agilex 5
     - MLAB
     - 32 x 20
     - 64
   * - Simulation, no vendor
     - (as a typical 16 x 4 target)
     - 16 x 4
     - 64
   * - iCE40, Cyclone 10 LP, any other target
     - none
     - 0 x 0
     - 0

A target this partition does not know of is described as having no LUT
RAM: code relying on these facts then uses block RAM, which works
everywhere, at a possibly higher cost.  Facts only steer cost, never
function: anything selected upon them has to fulfill the same contract
whatever the answer, simulation included.
