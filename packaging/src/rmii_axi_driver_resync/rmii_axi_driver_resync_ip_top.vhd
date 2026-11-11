library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_mii, nsl_amba;
use nsl_mii.rmii.all;
use nsl_mii.link.all;
use nsl_amba.axi4_stream.all;

-- Vivado IP packaging boundary for nsl_mii.rmii.rmii_axi_driver_resync: the
-- real entity's ports use NSL record types (rmii_m2p/rmii_p2m, link_speed_t,
-- nsl_amba.axi4_stream.master_t/slave_t), which Vivado's IP packager
-- (ipx::package_project) rejects at the top level - only std_logic/
-- std_logic_vector is allowed there. This wrapper flattens everything to
-- primitive types, using nsl_amba.packer's axi4_stream_slave_packer/
-- master_packer for the two AXI4-Stream ports (same helper
-- management_controller_ip_top.vhd uses for its own command/response),
-- and instantiates the real driver underneath. rx/tx use the same 1-byte
-- + 1-bit-user + tlast config as nsl_mii.flit.axi4_flit_cfg, which is what
-- rmii_axi_driver_resync actually packs/unpacks internally via
-- mii_flit_to/from_axi4_stream. RMII pins are left as plain ports.
entity rmii_axi_driver_resync_ip_top is
  generic(
    ipg_c : integer := 96
    );
  port(
    clock : in std_logic;
    resetn : in std_logic;

    rmii_ref_clock : in std_logic;

    rmii_o_tx_d   : out std_logic_vector(1 downto 0);
    rmii_o_tx_en  : out std_logic;
    rmii_i_rx_d   : in  std_logic_vector(1 downto 0);
    rmii_i_rx_er  : in  std_logic;
    rmii_i_crs_dv : in  std_logic;

    -- nsl_mii.link.to_speed: 00=10M 01=100M others=1000M
    link_speed : in std_logic_vector(1 downto 0) := "01";

    tx_sfd : out std_logic;
    rx_sfd : out std_logic;

    rx_tdata  : out std_logic_vector(7 downto 0);
    rx_tuser  : out std_logic_vector(0 downto 0);
    rx_tlast  : out std_logic;
    rx_tvalid : out std_logic;
    rx_tready : in  std_logic := '1';

    tx_tdata  : in  std_logic_vector(7 downto 0) := x"00";
    tx_tuser  : in  std_logic_vector(0 downto 0) := "0";
    tx_tlast  : in  std_logic := '0';
    tx_tvalid : in  std_logic := '0';
    tx_tready : out std_logic
    );
end entity;

architecture beh of rmii_axi_driver_resync_ip_top is

  constant config_c : nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(1, user => 1, last => true);

  signal rmii_o_s : rmii_m2p;
  signal rmii_i_s : rmii_p2m;

  signal rx_o_s : nsl_amba.axi4_stream.master_t;
  signal rx_i_s : nsl_amba.axi4_stream.slave_t;
  signal tx_i_s : nsl_amba.axi4_stream.master_t;
  signal tx_o_s : nsl_amba.axi4_stream.slave_t;

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of clock : signal is "xilinx.com:signal:clock:1.0 clock CLK";
  attribute X_INTERFACE_PARAMETER of clock : signal is "ASSOCIATED_BUSIF rx:tx, ASSOCIATED_RESET resetn";
  attribute X_INTERFACE_INFO of resetn : signal is "xilinx.com:signal:reset:1.0 resetn RST";
  attribute X_INTERFACE_PARAMETER of resetn : signal is "POLARITY ACTIVE_LOW";


begin

  rmii_o_tx_d  <= std_logic_vector(rmii_o_s.tx_d);
  rmii_o_tx_en <= std_logic(rmii_o_s.tx_en);
  rmii_i_s.rx_d   <= std_ulogic_vector(rmii_i_rx_d);
  rmii_i_s.rx_er  <= std_ulogic(rmii_i_rx_er);
  rmii_i_s.crs_dv <= std_ulogic(rmii_i_crs_dv);

  rx_pack: nsl_amba.packer.axi4_stream_master_packer
    generic map(
      config_c => config_c
      )
    port map(
      tvalid => rx_tvalid,
      tready => rx_tready,
      tdata => rx_tdata,
      tlast => rx_tlast,
      tuser => rx_tuser,

      stream_i => rx_o_s,
      stream_o => rx_i_s
      );

  tx_pack: nsl_amba.packer.axi4_stream_slave_packer
    generic map(
      config_c => config_c
      )
    port map(
      tvalid => tx_tvalid,
      tready => tx_tready,
      tdata => tx_tdata,
      tlast => tx_tlast,
      tuser => tx_tuser,

      stream_i => tx_o_s,
      stream_o => tx_i_s
      );

  driver: entity nsl_mii.rmii_axi_driver_resync
    generic map(
      ipg_c => ipg_c
      )
    port map(
      reset_n_i => std_ulogic(resetn),
      clock_i => std_ulogic(clock),

      rmii_ref_clock_i => std_ulogic(rmii_ref_clock),
      rmii_o => rmii_o_s,
      rmii_i => rmii_i_s,

      link_speed_i => to_speed(std_ulogic_vector(link_speed)),

      tx_sfd_o => tx_sfd,
      rx_sfd_o => rx_sfd,

      rx_o => rx_o_s,
      rx_i => rx_i_s,

      tx_i => tx_i_s,
      tx_o => tx_o_s
      );

end architecture;
