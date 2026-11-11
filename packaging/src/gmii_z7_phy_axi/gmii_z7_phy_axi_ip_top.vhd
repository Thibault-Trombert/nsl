library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_mii;
use nsl_mii.gmii.all;

-- Vivado IP wrapper for nsl_mii.gmii_axi.gmii_z7_phy_axi.
--
-- IP-XACT cannot express record ports, so the two gmii_io_group_t
-- groups become the ten signals of xilinx.com:interface:gmii:1.0, and
-- the two AXI4-Stream links are flattened by the nsl_amba packers.
--
-- The block presents itself as a PHY to the MAC: it consumes TXD/TX_EN
-- and drives RXD/RX_DV, plus TX_CLK and RX_CLK.  Wire the gmii
-- interface straight to a Zynq-7 GMII_ETHERNET port.
--
-- Unlike gmii_z7_phy, whose committed links carry the frame status in
-- an extra beat after the payload, this one carries it in TUSER(0) of
-- the beat holding TLAST, and the payload ends where TLAST says it
-- does. TUSER(0) is an *error* flag: set means the phy saw an error
-- during the frame (or its receiver overflowed) and the frame must be
-- discarded. Anything downstream that has to act on it, in either
-- direction, must propagate TUSER -- a plain AXI4-Stream FIFO drops
-- the bit unless it is configured with TUSER enabled.
entity gmii_z7_phy_axi_ip_top is
  generic(
    -- Inter-packet gap, in bit times.
    ipg_c : natural range 0 to 1023 := 96
    );
  port(
    reset_n_i : in std_logic;
    clock_i   : in std_logic;

    gmii_txd    : in  std_logic_vector(7 downto 0);
    gmii_tx_en  : in  std_logic;
    gmii_tx_er  : in  std_logic;
    gmii_tx_clk : out std_logic;
    gmii_rxd    : out std_logic_vector(7 downto 0);
    gmii_rx_dv  : out std_logic;
    gmii_rx_er  : out std_logic;
    gmii_rx_clk : out std_logic;
    gmii_crs    : out std_logic;
    gmii_col    : out std_logic;

    -- Frames the MAC transmitted, layer-1 format with FCS.
    -- TUSER(0) on the TLAST beat tells whether the frame was bad.
    from_mac_tdata  : out std_logic_vector(7 downto 0);
    from_mac_tuser  : out std_logic_vector(0 downto 0);
    from_mac_tvalid : out std_logic;
    from_mac_tlast  : out std_logic;
    from_mac_tready : in  std_logic;

    -- Frames to hand to the MAC, same format. A frame whose TUSER(0)
    -- is set on its TLAST beat is aborted on the wire rather than sent
    -- cleanly.
    to_mac_tdata  : in  std_logic_vector(7 downto 0);
    to_mac_tuser  : in  std_logic_vector(0 downto 0);
    to_mac_tvalid : in  std_logic;
    to_mac_tlast  : in  std_logic;
    to_mac_tready : out std_logic
    );
end entity;

architecture beh of gmii_z7_phy_axi_ip_top is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of clock_i : signal is "xilinx.com:signal:clock:1.0 clock_i CLK";
  attribute X_INTERFACE_INFO of reset_n_i : signal is "xilinx.com:signal:reset:1.0 reset_n_i RST";
  attribute X_INTERFACE_PARAMETER of reset_n_i : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_PARAMETER of clock_i : signal is "ASSOCIATED_BUSIF gmii:from_mac:to_mac, ASSOCIATED_RESET reset_n_i";

  attribute X_INTERFACE_INFO of gmii_txd : signal is "xilinx.com:interface:gmii:1.0 gmii TXD";
  attribute X_INTERFACE_INFO of gmii_tx_en : signal is "xilinx.com:interface:gmii:1.0 gmii TX_EN";
  attribute X_INTERFACE_INFO of gmii_tx_er : signal is "xilinx.com:interface:gmii:1.0 gmii TX_ER";
  attribute X_INTERFACE_INFO of gmii_tx_clk : signal is "xilinx.com:interface:gmii:1.0 gmii TX_CLK";
  attribute X_INTERFACE_INFO of gmii_rxd : signal is "xilinx.com:interface:gmii:1.0 gmii RXD";
  attribute X_INTERFACE_INFO of gmii_rx_dv : signal is "xilinx.com:interface:gmii:1.0 gmii RX_DV";
  attribute X_INTERFACE_INFO of gmii_rx_er : signal is "xilinx.com:interface:gmii:1.0 gmii RX_ER";
  attribute X_INTERFACE_INFO of gmii_rx_clk : signal is "xilinx.com:interface:gmii:1.0 gmii RX_CLK";
  attribute X_INTERFACE_INFO of gmii_crs : signal is "xilinx.com:interface:gmii:1.0 gmii CRS";
  attribute X_INTERFACE_INFO of gmii_col : signal is "xilinx.com:interface:gmii:1.0 gmii COL";

  attribute X_INTERFACE_INFO of from_mac_tdata : signal is "xilinx.com:interface:axis:1.0 from_mac TDATA";
  attribute X_INTERFACE_INFO of from_mac_tuser : signal is "xilinx.com:interface:axis:1.0 from_mac TUSER";
  attribute X_INTERFACE_INFO of from_mac_tvalid : signal is "xilinx.com:interface:axis:1.0 from_mac TVALID";
  attribute X_INTERFACE_INFO of from_mac_tlast : signal is "xilinx.com:interface:axis:1.0 from_mac TLAST";
  attribute X_INTERFACE_INFO of from_mac_tready : signal is "xilinx.com:interface:axis:1.0 from_mac TREADY";

  attribute X_INTERFACE_INFO of to_mac_tdata : signal is "xilinx.com:interface:axis:1.0 to_mac TDATA";
  attribute X_INTERFACE_INFO of to_mac_tuser : signal is "xilinx.com:interface:axis:1.0 to_mac TUSER";
  attribute X_INTERFACE_INFO of to_mac_tvalid : signal is "xilinx.com:interface:axis:1.0 to_mac TVALID";
  attribute X_INTERFACE_INFO of to_mac_tlast : signal is "xilinx.com:interface:axis:1.0 to_mac TLAST";
  attribute X_INTERFACE_INFO of to_mac_tready : signal is "xilinx.com:interface:axis:1.0 to_mac TREADY";

  constant config_c : nsl_amba.axi4_stream.config_t := nsl_mii.flit.axi4_flit_cfg;

  signal tx_s, rx_s : gmii_io_group_t;

  signal from_mac_m_s : nsl_amba.axi4_stream.master_t;
  signal from_mac_s_s : nsl_amba.axi4_stream.slave_t;
  signal to_mac_m_s : nsl_amba.axi4_stream.master_t;
  signal to_mac_s_s : nsl_amba.axi4_stream.slave_t;

begin

  tx_s.data <= std_ulogic_vector(gmii_txd);
  tx_s.en   <= gmii_tx_en;
  tx_s.er   <= gmii_tx_er;

  gmii_rxd   <= std_logic_vector(rx_s.data);
  gmii_rx_dv <= rx_s.en;
  gmii_rx_er <= rx_s.er;

  from_mac_pack: nsl_amba.packer.axi4_stream_master_packer
    generic map(
      config_c => config_c
      )
    port map(
      tvalid => from_mac_tvalid,
      tready => from_mac_tready,
      tdata => from_mac_tdata,
      tstrb => open,
      tkeep => open,
      tlast => from_mac_tlast,
      tid => open,
      tdest => open,
      tuser => from_mac_tuser,

      stream_i => from_mac_m_s,
      stream_o => from_mac_s_s
      );

  to_mac_pack: nsl_amba.packer.axi4_stream_slave_packer
    generic map(
      config_c => config_c
      )
    port map(
      tvalid => to_mac_tvalid,
      tready => to_mac_tready,
      tdata => to_mac_tdata,
      tlast => to_mac_tlast,
      tuser => to_mac_tuser,

      stream_i => to_mac_s_s,
      stream_o => to_mac_m_s
      );

  phy: nsl_mii.gmii_axi.gmii_z7_phy_axi
    generic map(
      ipg_c => ipg_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i   => clock_i,

      gmii_tx_i     => tx_s,
      gmii_tx_clk_o => gmii_tx_clk,
      gmii_col_o    => gmii_col,
      gmii_crs_o    => gmii_crs,
      gmii_rx_clk_o => gmii_rx_clk,
      gmii_rx_o     => rx_s,

      from_mac_o => from_mac_m_s,
      from_mac_i => from_mac_s_s,

      to_mac_i => to_mac_m_s,
      to_mac_o => to_mac_s_s
      );

end architecture;
