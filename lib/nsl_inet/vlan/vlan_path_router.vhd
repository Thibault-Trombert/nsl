library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_inet, nsl_mii;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.committed.all;
use nsl_inet.vlan.all;
use nsl_mii.gmii.all;

-- One GMII port fanned out to one AXI4-Stream pipe per VLAN.
--
-- TX (the MAC transmits, frames leave through routed_tx_o):
--
--   gmii_tx_i -> gmii_z7_phy -> mac_receiver -> vlan_demux -+-> committed_to_axi4_stream -> [fifo] -> routed_tx_o(0)
--                                                           +-> ...                                            (N-1)
--
-- RX (frames enter through routed_rx_i, the MAC receives):
--
--   routed_rx_i(i) -> [fifo] -> axi4_stream_to_committed -+-> vlan_mux -> mac_transmitter -> gmii_z7_phy -> gmii_rx_o
--
-- N is vlan_id_c'length; pipe i carries VID vlan_id_c(i).
--
-- gmii_z7_phy speaks the layer-1 frame format (FCS present), while
-- vlan_demux and vlan_mux speak the nsl_inet.mac boundary (no FCS).
-- Tag insertion and removal change the frame length, so the FCS is
-- checked and stripped on the way in and recomputed on the way out.
-- Both stages live inside the gen_gmii_adpater generate: when the
-- adapter is bypassed, from_mac_i / to_mac_o are expected to already
-- carry mac-boundary frames.

entity vlan_path_router is
  generic(
    -- One AXI4-Stream pipe per entry, in this order.
    vlan_id_c : vlan_id_vector;
    -- Untagged frames belong to this VID.  Default 0 is reserved by
    -- 802.1Q, so untagged frames are dropped unless overridden.
    native_vlan_id_c : vlan_id_t := 0;
    -- Depth of each per-VID packet-drop fifo, in log2 words.
    word_count_l2_c : integer := 9;
    -- Instantiate the per-VID packet-drop fifos.
    gen_backpressure_fifo : boolean := true;
    -- Instantiate the Zynq-7 GMII phy and the mac framing around it.
    gen_gmii_adpater : boolean := true
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;

    -- Zynq-7 PS GMII.  Meaningful only when gen_gmii_adpater is true;
    -- outputs are held idle otherwise.
    gmii_tx_i     : in  gmii_io_group_t := (data => (others => '0'), en => '0', er => '0');
    gmii_tx_clk_o : out std_ulogic;
    gmii_col_o    : out std_ulogic;
    gmii_crs_o    : out std_ulogic;
    gmii_rx_clk_o : out std_logic;
    gmii_rx_o     : out gmii_io_group_t;

    -- mac-boundary committed frames.  Meaningful only when
    -- gen_gmii_adpater is false; outputs are held idle otherwise.
    -- Directions are relative to this entity: from_mac_* carries what
    -- the MAC transmitted, to_mac_* what the MAC is to receive.
    from_mac_i : in  committed_req := committed_req_idle_c;
    from_mac_o : out committed_ack;
    to_mac_o   : out committed_req;
    to_mac_i   : in  committed_ack := committed_ack_idle_c;

    -- Per-VID AXI4-Stream, byte wide with tlast.
    routed_tx_o : out master_vector(0 to vlan_id_c'length-1);
    routed_tx_i : in  slave_vector(0 to vlan_id_c'length-1);

    routed_rx_i : in  master_vector(0 to vlan_id_c'length-1);
    routed_rx_o : out slave_vector(0 to vlan_id_c'length-1)
    );
end entity;

architecture beh of vlan_path_router is

  constant vlan_count_c : natural := vlan_id_c'length;

  -- Byte wide with tlast: what committed_to_axi4_stream emits and
  -- axi4_stream_to_committed expects.
  constant stream_config_c : nsl_amba.axi4_stream.config_t
    := nsl_bnoc.axi_adapter.axi4_stream_committed_config_c;

  -- mac boundary, between the phy (or the ports) and the vlan blocks.
  signal l2_from_mac_s : committed_bus_t;
  signal l2_to_mac_s   : committed_bus_t;

  -- Per-VID committed pipes, vlan blocks to adapters.
  signal demux_req_s : committed_req_array(0 to vlan_count_c-1);
  signal demux_ack_s : committed_ack_array(0 to vlan_count_c-1);
  signal mux_req_s   : committed_req_array(0 to vlan_count_c-1);
  signal mux_ack_s   : committed_ack_array(0 to vlan_count_c-1);

  -- Per-VID AXI4-Stream, adapters to fifos.
  signal tx_adapted_m_s : master_vector(0 to vlan_count_c-1);
  signal tx_adapted_s_s : slave_vector(0 to vlan_count_c-1);
  signal rx_drained_m_s : master_vector(0 to vlan_count_c-1);
  signal rx_drained_s_s : slave_vector(0 to vlan_count_c-1);

begin

  -- ------------------------------------------------------------------
  -- MAC boundary
  -- ------------------------------------------------------------------

  with_gmii: if gen_gmii_adpater
  generate
    signal l1_from_mac_s, l1_to_mac_s : committed_bus_t;
  begin

    phy: nsl_mii.gmii.gmii_z7_phy
      port map(
        reset_n_i => reset_n_i,
        clock_i   => clock_i,

        gmii_tx_i     => gmii_tx_i,
        gmii_tx_clk_o => gmii_tx_clk_o,
        gmii_col_o    => gmii_col_o,
        gmii_crs_o    => gmii_crs_o,
        gmii_rx_clk_o => gmii_rx_clk_o,
        gmii_rx_o     => gmii_rx_o,

        from_mac_o => l1_from_mac_s.req,
        from_mac_i => l1_from_mac_s.ack,

        to_mac_i => l1_to_mac_s.req,
        to_mac_o => l1_to_mac_s.ack
        );

    -- Checks and strips the FCS before the tag is removed.
    fcs_check: nsl_inet.mac.mac_receiver
      generic map(
        l1_has_fcs_c       => true,
        l1_header_length_c => 0
        )
      port map(
        clock_i   => clock_i,
        reset_n_i => reset_n_i,

        l1_i => l1_from_mac_s.req,
        l1_o => l1_from_mac_s.ack,

        l2_o => l2_from_mac_s.req,
        l2_i => l2_from_mac_s.ack
        );

    -- Pads and recomputes the FCS after the tag has been inserted.
    fcs_append: nsl_inet.mac.mac_transmitter
      generic map(
        l1_has_fcs_c       => true,
        l1_header_length_c => 0,
        min_frame_size_c   => 64
        )
      port map(
        clock_i   => clock_i,
        reset_n_i => reset_n_i,

        l2_i => l2_to_mac_s.req,
        l2_o => l2_to_mac_s.ack,

        l1_o => l1_to_mac_s.req,
        l1_i => l1_to_mac_s.ack
        );

    from_mac_o <= committed_ack_idle_c;
    to_mac_o   <= committed_req_idle_c;

  end generate;

  without_gmii: if not gen_gmii_adpater
  generate

    l2_from_mac_s.req <= from_mac_i;
    from_mac_o        <= l2_from_mac_s.ack;

    to_mac_o        <= l2_to_mac_s.req;
    l2_to_mac_s.ack <= to_mac_i;

    gmii_tx_clk_o <= '0';
    gmii_col_o    <= '0';
    gmii_crs_o    <= '0';
    gmii_rx_clk_o <= '0';
    gmii_rx_o     <= (data => (others => '0'), en => '0', er => '0');

  end generate;

  -- ------------------------------------------------------------------
  -- VLAN routing
  -- ------------------------------------------------------------------

  demux: nsl_inet.vlan.vlan_demux
    generic map(
      header_length_c  => 0,
      vlan_id_c        => vlan_id_c,
      native_vlan_id_c => native_vlan_id_c
      )
    port map(
      clock_i   => clock_i,
      reset_n_i => reset_n_i,

      in_i => l2_from_mac_s.req,
      in_o => l2_from_mac_s.ack,

      vlan_o => demux_req_s,
      vlan_i => demux_ack_s
      );

  mux: nsl_inet.vlan.vlan_mux
    generic map(
      header_length_c  => 0,
      vlan_id_c        => vlan_id_c,
      native_vlan_id_c => native_vlan_id_c
      )
    port map(
      clock_i   => clock_i,
      reset_n_i => reset_n_i,

      vlan_i => mux_req_s,
      vlan_o => mux_ack_s,

      out_o => l2_to_mac_s.req,
      out_i => l2_to_mac_s.ack
      );

  -- ------------------------------------------------------------------
  -- Per-VID stream adaptation and buffering
  -- ------------------------------------------------------------------

  per_vlan: for i in 0 to vlan_count_c-1
  generate

    -- TX: committed out of the demux, AXI4-Stream out of the entity.
    tx_adapter: nsl_bnoc.axi_adapter.committed_to_axi4_stream
      port map(
        clock_i   => clock_i,
        reset_n_i => reset_n_i,

        committed_i => demux_req_s(i),
        committed_o => demux_ack_s(i),

        axi_o => tx_adapted_m_s(i),
        axi_i => tx_adapted_s_s(i)
        );

    tx_buffered: if gen_backpressure_fifo
    generate
      fifo: nsl_amba.stream_fifo.axi4_stream_async_packet_drop_fifo
        generic map(
          config_c        => stream_config_c,
          word_count_l2_c => word_count_l2_c,
          -- The component indexes clock_i(1) unconditionally, so it is
          -- always a two-clock instance.  Both domains are driven by
          -- clock_i here; see routed_clock_i in the design notes if the
          -- routed side ever needs its own domain.
          clock_count_c   => 2
          )
        port map(
          reset_n_i  => reset_n_i,
          clock_i(0) => clock_i,
          clock_i(1) => clock_i,

          in_i => tx_adapted_m_s(i),
          in_o => tx_adapted_s_s(i),

          out_i => routed_tx_i(i),
          out_o => routed_tx_o(i),

          overrun_o => open
          );
    end generate;

    tx_unbuffered: if not gen_backpressure_fifo
    generate
      routed_tx_o(i)    <= tx_adapted_m_s(i);
      tx_adapted_s_s(i) <= routed_tx_i(i);
    end generate;

    -- RX: AXI4-Stream into the entity, committed into the mux.
    rx_buffered: if gen_backpressure_fifo
    generate
      fifo: nsl_amba.stream_fifo.axi4_stream_async_packet_drop_fifo
        generic map(
          config_c        => stream_config_c,
          word_count_l2_c => word_count_l2_c,
          -- The component indexes clock_i(1) unconditionally, so it is
          -- always a two-clock instance.  Both domains are driven by
          -- clock_i here; see routed_clock_i in the design notes if the
          -- routed side ever needs its own domain.
          clock_count_c   => 2
          )
        port map(
          reset_n_i  => reset_n_i,
          clock_i(0) => clock_i,
          clock_i(1) => clock_i,

          in_i => routed_rx_i(i),
          in_o => routed_rx_o(i),

          out_i => rx_drained_s_s(i),
          out_o => rx_drained_m_s(i),

          overrun_o => open
          );
    end generate;

    rx_unbuffered: if not gen_backpressure_fifo
    generate
      rx_drained_m_s(i) <= routed_rx_i(i);
      routed_rx_o(i)    <= rx_drained_s_s(i);
    end generate;

    rx_adapter: nsl_bnoc.axi_adapter.axi4_stream_to_committed
      port map(
        clock_i   => clock_i,
        reset_n_i => reset_n_i,

        axi_i => rx_drained_m_s(i),
        axi_o => rx_drained_s_s(i),

        committed_o => mux_req_s(i),
        committed_i => mux_ack_s(i)
        );

  end generate;

end architecture;
