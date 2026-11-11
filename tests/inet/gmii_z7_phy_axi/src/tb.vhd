library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_mii, nsl_simulation;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_mii.flit.all;
use nsl_mii.gmii.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- gmii_z7_phy_axi looped back on itself through the filter, i.e. the
-- AXI4-Stream version of feeding from_mac back into to_mac.
--
-- Same shape as the committed-side scenarios: a clean frame has to
-- come back untouched, a frame the phy marks bad has to disappear, and
-- a probe frame behind it proves nothing leaked and the path
-- recovered. The phy marks a frame by asserting ER during it, which is
-- exactly what sets in_error_seen in mii_flit_to_axi4_stream and thus
-- the TUSER bit the filter drops on.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  signal gmii_tx_s, gmii_rx_s : gmii_io_group_t;
  signal from_mac_s, to_mac_s : bus_t;

  constant frame_a_c : byte_string := from_hex("000102030405060708090a0b0c0d0e0f");
  constant frame_b_c : byte_string := from_hex("101112131415161718191a1b1c1d1e1f");
  constant frame_c_c : byte_string := from_hex("202122232425262728292a2b2c2d2e2f");

  -- Drives one GMII frame: preamble, SFD, payload, then back to idle.
  -- When error_at is a payload index, ER is asserted on that byte.
  procedure gmii_frame_put(signal clock : in std_ulogic;
                           signal gmii : out gmii_io_group_t;
                           constant data : in byte_string;
                           constant error_at : in integer := -1) is
  begin
    for i in 0 to 6
    loop
      wait until falling_edge(clock);
      gmii.data <= x"55";
      gmii.en <= '1';
      gmii.er <= '0';
    end loop;

    wait until falling_edge(clock);
    gmii.data <= x"d5";
    gmii.en <= '1';
    gmii.er <= '0';

    for i in data'range
    loop
      wait until falling_edge(clock);
      gmii.data <= data(i);
      gmii.en <= '1';
      if i = error_at then
        gmii.er <= '1';
      else
        gmii.er <= '0';
      end if;
    end loop;

    wait until falling_edge(clock);
    gmii.data <= x"00";
    gmii.en <= '0';
    gmii.er <= '0';
  end procedure;

  procedure gmii_idle_put(signal clock : in std_ulogic;
                          signal gmii : out gmii_io_group_t;
                          constant count : in natural) is
  begin
    for i in 0 to count-1
    loop
      wait until falling_edge(clock);
      gmii.data <= x"00";
      gmii.en <= '0';
      gmii.er <= '0';
    end loop;
  end procedure;

  -- Collects the next frame off the GMII RX side, preamble and SFD
  -- stripped, so what comes out is comparable to what was put in.
  procedure gmii_frame_get(signal clock : in std_ulogic;
                           signal gmii : in gmii_io_group_t;
                           variable data : out byte_stream) is
    variable r : byte_stream;
    variable seen_sfd : boolean := false;
  begin
    clear(r);

    while true
    loop
      wait until falling_edge(clock);
      exit when gmii.en = '1';
    end loop;

    while gmii.en = '1'
    loop
      if seen_sfd then
        write(r, gmii.data);
      elsif gmii.data = x"d5" then
        seen_sfd := true;
      end if;
      wait until falling_edge(clock);
    end loop;

    data := r;
  end procedure;

begin

  gmii_gen: process
  begin
    done_s(0) <= '0';

    gmii_tx_s.data <= x"00";
    gmii_tx_s.en <= '0';
    gmii_tx_s.er <= '0';

    wait until reset_n_s = '1';
    gmii_idle_put(clock_s, gmii_tx_s, 32);

    log(LOG_LEVEL_INFO, "Sending clean frame A", LOG_COLOR_CYAN);
    gmii_frame_put(clock_s, gmii_tx_s, frame_a_c);
    gmii_idle_put(clock_s, gmii_tx_s, 64);

    log(LOG_LEVEL_INFO, "Sending frame B, with ER asserted mid-frame", LOG_COLOR_YELLOW);
    gmii_frame_put(clock_s, gmii_tx_s, frame_b_c, error_at => 4);
    gmii_idle_put(clock_s, gmii_tx_s, 64);

    log(LOG_LEVEL_INFO, "Sending clean probe frame C", LOG_COLOR_CYAN);
    gmii_frame_put(clock_s, gmii_tx_s, frame_c_c);
    gmii_idle_put(clock_s, gmii_tx_s, 256);

    done_s(0) <= '1';
    wait;
  end process;

  gmii_chk: process
    variable blob : byte_stream;
  begin
    done_s(1) <= '0';

    gmii_frame_get(clock_s, gmii_rx_s, blob);
    assert_equal("frame A looped back", blob.all, frame_a_c, warning);
    deallocate(blob);

    -- Frame B was marked by the phy and dropped by the filter, so the
    -- next frame on the wire must be C. Had B leaked, it would show up
    -- here instead and fail the comparison.
    gmii_frame_get(clock_s, gmii_rx_s, blob);
    assert_equal("frame C looped back, B dropped", blob.all, frame_c_c, warning);
    deallocate(blob);

    done_s(1) <= '1';
    wait;
  end process;

  dut: nsl_mii.gmii_axi.gmii_z7_phy_axi
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      gmii_tx_i => gmii_tx_s,
      gmii_tx_clk_o => open,
      gmii_col_o => open,

      gmii_crs_o => open,
      gmii_rx_clk_o => open,
      gmii_rx_o => gmii_rx_s,

      from_mac_o => from_mac_s.m,
      from_mac_i => from_mac_s.s,

      to_mac_i => to_mac_s.m,
      to_mac_o => to_mac_s.s
      );

  filter: nsl_amba.stream_packetizer.axi4_stream_unpacketizer_filter
    generic map(
      config_c => axi4_flit_cfg,
      error_index_c => 0,
      max_length_l2_c => 11,
      max_packet_count_l2_c => 4
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i(0) => clock_s,

      in_i => from_mac_s.m,
      in_o => from_mac_s.s,

      out_o => to_mac_s.m,
      out_i => to_mac_s.s
      );

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count  => done_s'length
      )
    port map(
      clock_period(0) => 8 ns,
      reset_duration  => (others => 14 ns),
      clock_o(0)      => clock_s,
      reset_n_o(0)    => reset_n_s,
      done_i          => done_s
      );

end architecture;
