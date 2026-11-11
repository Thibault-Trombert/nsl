library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, work;
use nsl_amba.axi4_stream.all;
use work.gmii.all;

-- AXI4-Stream flavour of work.gmii.
--
-- Same Layer-1 transport as work.gmii, with the frame status carried
-- in a TUSER bit of the beat holding TLAST instead of an extra flit
-- appended to the payload. Streams use work.flit.axi4_flit_cfg, i.e.
-- config(1, user => 1, last => true), and bit 0 of TUSER is an error
-- flag: set means the frame was not received cleanly and must be
-- discarded. Note this is inverted with respect to the committed
-- status byte's LSB, which is a validity flag.
--
-- Layer 1 <-> layer 2 frame components:
-- * Destination MAC [6]
-- * Source MAC [6]
-- * Ethertype [2]
-- * Payload [*]
-- * FCS [*]
-- and, alongside the last beat:
-- * TUSER[0] Frame error (an error was signaled by Phy, or the
--            receiver overflowed)
package gmii_axi is

  -- Pseudo GMII adapter, fixed at Gb traffic, dedicated to connection
  -- to Zynq-7 hard-IP. Behaves as a Phy to the GbE controller. Always
  -- feed a 125 MHz clock.
  --
  -- This is work.gmii.gmii_z7_phy with AXI4-Stream ports.
  component gmii_z7_phy_axi is
    generic(
      -- In bit time
      ipg_c : natural := 96
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      gmii_tx_i : in gmii_io_group_t;
      -- Zynq-7 GbE receives TX Clock from PL.
      gmii_tx_clk_o : out std_ulogic;
      gmii_col_o : out std_ulogic;

      gmii_crs_o : out std_ulogic;
      gmii_rx_clk_o : out std_logic;
      gmii_rx_o : out gmii_io_group_t;

      from_mac_o : out master_t;
      from_mac_i : in slave_t;

      to_mac_i : in master_t;
      to_mac_o : out slave_t
      );
  end component;

end package gmii_axi;
