library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, work;
use work.flit.all;
use work.gmii.all;
use nsl_amba.axi4_stream.all;

entity gmii_z7_phy_axi is
  generic(
    ipg_c : natural := 96
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    gmii_tx_i : in gmii_io_group_t;
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
end entity;

architecture beh of gmii_z7_phy_axi is

  signal s_flit_to_mac : mii_flit_t;

begin

  tx_path: work.flit.mii_flit_from_axi4_stream
    generic map(
      ipg_c => ipg_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => to_mac_i,
      in_o => to_mac_o,

      underrun_o => open,
      packet_o => gmii_crs_o,
      flit_o => s_flit_to_mac,
      ready_i => '1'
      );

  gmii_rx_o.data <= s_flit_to_mac.data;
  gmii_rx_o.en <= s_flit_to_mac.valid;
  gmii_rx_o.er <= s_flit_to_mac.error;
  gmii_rx_clk_o <= clock_i;

  rx_path: work.flit.mii_flit_to_axi4_stream
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      valid_i => '1',
      flit_i.data => gmii_tx_i.data,
      flit_i.valid => gmii_tx_i.en,
      flit_i.error => gmii_tx_i.er,

      out_o => from_mac_o,
      out_i => from_mac_i
      );

  gmii_col_o <= '0';
  gmii_tx_clk_o <= clock_i;

end architecture;
