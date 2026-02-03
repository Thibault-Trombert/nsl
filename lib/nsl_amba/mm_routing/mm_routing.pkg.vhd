library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

-- AXI4-MM routing components for building interconnect fabrics.
package mm_routing is

  -- Error slave that responds with DECERR to all transactions.
  -- Useful for handling unmapped address ranges.
  component axi4_mm_error_slave is
    generic(
      config_c : work.axi4_mm.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      axi_i : in work.axi4_mm.master_t;
      axi_o : out work.axi4_mm.slave_t
      );
  end component;

  -- Full N-to-M AXI4-MM crossbar interconnect.
  -- Connects N masters to M slaves with address-based routing.
  -- ID field is widened to encode master index for response routing.
  --
  -- slave_config_c.id_width must be >= master_config_c.id_width +
  -- ceil_log2(master_count_c) to accommodate master index in ID field.
  -- Other config fields (address_width, data_bus_width_l2, len_width)
  -- must match between master and slave configs.
  --
  -- default_slave_c controls handling of unmapped addresses:
  -- - If < 0: an internal error slave is instantiated, unmapped accesses return DECERR
  -- - If >= 0: unmapped addresses route to the external slave at that index
  --
  -- aw_tracking_depth_c sets the depth of the per-master FIFO that
  -- correlates AW and W channels. This limits how many write
  -- transactions each master can have outstanding before AW blocks.
  -- Increase if masters issue many back-to-back write addresses
  -- before sending data.
  component axi4_mm_crossbar is
    generic(
      master_config_c : work.axi4_mm.config_t;
      slave_config_c : work.axi4_mm.config_t;
      master_count_c : positive;
      routing_table_c : work.address.address_vector;
      default_slave_c : integer := -1;
      aw_tracking_depth_c : positive := 4
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- From masters, use master_config_c
      slave_i : in work.axi4_mm.master_vector(0 to master_count_c-1);
      slave_o : out work.axi4_mm.slave_vector(0 to master_count_c-1);

      -- To slaves, use slave_config_c
      master_o : out work.axi4_mm.master_vector(0 to routing_table_c'length-1);
      master_i : in work.axi4_mm.slave_vector(0 to routing_table_c'length-1)
      );
  end component;

  -- Shared bus N-to-M AXI4-MM interconnect.
  -- Low-cost alternative to crossbar: only one transaction at a time globally.
  -- Trades throughput for minimal logic and wire count.
  --
  -- Features:
  -- - Single outstanding transaction globally
  -- - No pipelining
  -- - Fixed priority arbitration: lower master index first
  -- - IDs pass through
  -- - Writes take priority over reads from same master
  --
  -- default_slave_c controls handling of unmapped addresses:
  -- - If < 0: an internal error slave is instantiated, unmapped accesses return DECERR
  -- - If >= 0: unmapped addresses route to the external slave at that index
  component axi4_mm_shared_bus is
    generic(
      config_c : work.axi4_mm.config_t;
      master_count_c : positive;
      routing_table_c : work.address.address_vector;
      default_slave_c : integer := -1
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- From masters
      slave_i : in work.axi4_mm.master_vector(0 to master_count_c-1);
      slave_o : out work.axi4_mm.slave_vector(0 to master_count_c-1);

      -- To slaves
      master_o : out work.axi4_mm.master_vector(0 to routing_table_c'length-1);
      master_i : in work.axi4_mm.slave_vector(0 to routing_table_c'length-1)
      );
  end component;

end package mm_routing;
