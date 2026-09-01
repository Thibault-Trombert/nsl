library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_bnoc, nsl_inet, nsl_mii;
use nsl_amba.axi4_stream.all;
use nsl_inet.vlan.all;
use nsl_mii.gmii.all;

-- Elaboration-only harness: instantiates vlan_path_router in both
-- generic configurations so every generate branch is compiled.
entity tb is
end entity;

architecture beh of tb is

  constant vids_c : vlan_id_vector(0 to 2) := (10, 20, 30);

  signal clock_s   : std_ulogic := '0';
  signal reset_n_s : std_ulogic := '0';

  signal gmii_tx_s : gmii_io_group_t := (data => (others => '0'), en => '0', er => '0');
  signal gmii_rx_a_s, gmii_rx_b_s : gmii_io_group_t;
  signal txclk_a_s, col_a_s, crs_a_s : std_ulogic;
  signal txclk_b_s, col_b_s, crs_b_s : std_ulogic;
  signal rxclk_a_s, rxclk_b_s : std_logic;

  signal tx_m_a_s, tx_m_b_s : master_vector(0 to 2);
  signal tx_s_a_s, tx_s_b_s : slave_vector(0 to 2) := (others => (ready => '0'));
  signal rx_m_a_s, rx_m_b_s : master_vector(0 to 2) := (others => null_master_c);
  signal rx_s_a_s, rx_s_b_s : slave_vector(0 to 2);

  signal from_mac_ack_s, to_mac_ack_s : nsl_bnoc.committed.committed_ack;
  signal from_mac_req_s, to_mac_req_s : nsl_bnoc.committed.committed_req;

begin

  clock_s <= not clock_s after 4 ns;
  reset_n_s <= '1' after 100 ns;

  -- With the GMII adapter and the per-VID fifos.
  dut_a: entity work.vlan_path_router
    generic map(
      vlan_id_c             => vids_c,
      native_vlan_id_c      => 10,
      word_count_l2_c       => 9,
      gen_backpressure_fifo => true,
      gen_gmii_adpater      => true
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i   => clock_s,

      gmii_tx_i     => gmii_tx_s,
      gmii_tx_clk_o => txclk_a_s,
      gmii_col_o    => col_a_s,
      gmii_crs_o    => crs_a_s,
      gmii_rx_clk_o => rxclk_a_s,
      gmii_rx_o     => gmii_rx_a_s,

      routed_tx_o => tx_m_a_s,
      routed_tx_i => tx_s_a_s,
      routed_rx_i => rx_m_a_s,
      routed_rx_o => rx_s_a_s
      );

  -- Bypassing both.
  dut_b: entity work.vlan_path_router
    generic map(
      vlan_id_c             => vids_c,
      native_vlan_id_c      => 20,
      word_count_l2_c       => 6,
      gen_backpressure_fifo => false,
      gen_gmii_adpater      => false
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i   => clock_s,

      gmii_tx_clk_o => txclk_b_s,
      gmii_col_o    => col_b_s,
      gmii_crs_o    => crs_b_s,
      gmii_rx_clk_o => rxclk_b_s,
      gmii_rx_o     => gmii_rx_b_s,

      from_mac_o => from_mac_ack_s,
      to_mac_o   => to_mac_req_s,

      routed_tx_o => tx_m_b_s,
      routed_tx_i => tx_s_b_s,
      routed_rx_i => rx_m_b_s,
      routed_rx_o => rx_s_b_s
      );

end architecture;
