library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_simulation;
use nsl_data.bytestream.all;

-- Minimal simulator exposing two memory-mapped buses on UDP:
--
-- * port 4250: a full AXI4 RAM behind axi4_mm_on_stream. Datagrams are
--   the axi4_mm_on_stream frames prefixed with one channel byte (the
--   stream TID, serialized by the meta packer/unpacker).
-- * port 4251: an APB RAM behind apb_stream_bridge.
--
-- The simulation never ends; kill the simulator when done.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0) := (others => '0');

  constant udp_config_c : nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(1, last => true);

begin

  axi: block is
    constant mm_config_c : nsl_amba.axi4_mm.config_t
      := nsl_amba.axi4_mm.config(address_width => 32,
                                 data_bus_width => 32,
                                 id_width => 2,
                                 max_length => 16,
                                 burst => true);
    constant stream_config_c : nsl_amba.axi4_stream.config_t
      := nsl_amba.axi4_stream.config(1, id => 3, last => true);

    signal udp_rx_s, udp_tx_s, rx_s, tx_s : nsl_amba.axi4_stream.bus_t;
    signal local_s, ram_s : nsl_amba.axi4_mm.bus_t;
  begin

    net: nsl_amba.stream_to_udp.axi4_stream_udp_gateway
      generic map(
        config_c => udp_config_c,
        bind_port_c => 4250
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        tx_i => udp_tx_s.m,
        tx_o => udp_tx_s.s,

        rx_o => udp_rx_s.m,
        rx_i => udp_rx_s.s
        );

    unpacker: nsl_amba.stream_meta.axi4_stream_meta_unpacker
      generic map(
        in_config_c => udp_config_c,
        out_config_c => stream_config_c,
        meta_elements_c => "i"
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => udp_rx_s.m,
        in_o => udp_rx_s.s,

        out_o => rx_s.m,
        out_i => rx_s.s
        );

    packer: nsl_amba.stream_meta.axi4_stream_meta_packer
      generic map(
        in_config_c => stream_config_c,
        out_config_c => udp_config_c,
        meta_elements_c => "i"
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => tx_s.m,
        in_o => tx_s.s,

        out_o => udp_tx_s.m,
        out_i => udp_tx_s.s
        );

    local_s.m.aw <= nsl_amba.axi4_mm.address_defaults(mm_config_c);
    local_s.m.w <= nsl_amba.axi4_mm.write_data_defaults(mm_config_c);
    local_s.m.b <= nsl_amba.axi4_mm.accept(mm_config_c, true);
    local_s.m.ar <= nsl_amba.axi4_mm.address_defaults(mm_config_c);
    local_s.m.r <= nsl_amba.axi4_mm.accept(mm_config_c, true);

    bridge: nsl_amba.mm_stream_adapter.axi4_mm_on_stream
      generic map(
        mm_config_c => mm_config_c,
        stream_config_c => stream_config_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        slave_i => local_s.m,
        slave_o => local_s.s,

        master_o => ram_s.m,
        master_i => ram_s.s,

        rx_i => rx_s.m,
        rx_o => rx_s.s,

        tx_o => tx_s.m,
        tx_i => tx_s.s
        );

    ram: nsl_amba.ram.axi4_mm_full_ram
      generic map(
        config_c => mm_config_c,
        byte_size_l2_c => 16
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        axi_i => ram_s.m,
        axi_o => ram_s.s
        );

  end block;

  apb: block is
    constant apb_config_c : nsl_amba.apb.config_t
      := nsl_amba.apb.config(address_width => 16,
                             data_bus_width => 32);

    signal udp_rx_s, udp_tx_s : nsl_amba.axi4_stream.bus_t;
    signal apb_s : nsl_amba.apb.bus_t;
  begin

    net: nsl_amba.stream_to_udp.axi4_stream_udp_gateway
      generic map(
        config_c => udp_config_c,
        bind_port_c => 4251
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        tx_i => udp_tx_s.m,
        tx_o => udp_tx_s.s,

        rx_o => udp_rx_s.m,
        rx_i => udp_rx_s.s
        );

    bridge: nsl_amba.stream_apb.apb_stream_bridge
      generic map(
        apb_config_c => apb_config_c,
        stream_config_c => udp_config_c,
        burst_length_l2_c => 4,
        identify_c => to_byte_string("apb_ram")
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        rx_i => udp_rx_s.m,
        rx_o => udp_rx_s.s,

        tx_o => udp_tx_s.m,
        tx_i => udp_tx_s.s,

        apb_o => apb_s.m,
        apb_i => apb_s.s
        );

    ram: nsl_amba.ram.apb_ram
      generic map(
        config_c => apb_config_c,
        byte_size_l2_c => 12
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        apb_i => apb_s.m,
        apb_o => apb_s.s
        );

  end block;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 42 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
