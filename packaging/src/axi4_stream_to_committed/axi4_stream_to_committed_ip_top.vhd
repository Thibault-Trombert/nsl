library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_amba;
use nsl_bnoc.axi_adapter.all;
use nsl_amba.axi4_stream.all;

-- Vivado IP packaging boundary for nsl_bnoc.axi_adapter.axi4_stream_to_committed
-- (the mirror of committed_to_axi4_stream_ip_top.vhd: AXI4-Stream in,
-- committed out). Flattens nsl_amba.axi4_stream.master_t/slave_t via
-- axi4_stream_slave_packer (this side is fed FROM outside, i.e. an AXI4-
-- Stream slave), and committed_req_t/committed_ack_t by plain aggregate
-- assignment (committed_req_t/committed_ack_t are literal subtypes of
-- framed_req_t/framed_ack_t, so this is wire-identical to the framed case).
-- Both flat port groups use the standard _t{data,valid,last,ready} naming
-- convention, so Vivado auto-detects them as axis_rtl interfaces ("axi" and
-- "committed") without needing custom X_INTERFACE_INFO.
entity axi4_stream_to_committed_ip_top is
  port(
    clock : in std_logic;
    resetn : in std_logic;

    axi_tdata  : in  std_logic_vector(7 downto 0) := x"00";
    axi_tlast  : in  std_logic := '0';
    axi_tvalid : in  std_logic := '0';
    axi_tready : out std_logic;

    committed_tdata  : out std_logic_vector(7 downto 0);
    committed_tlast  : out std_logic;
    committed_tvalid : out std_logic;
    committed_tready : in  std_logic := '1'
    );
end entity;

architecture beh of axi4_stream_to_committed_ip_top is

  constant config_c : nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(1, last => true);

  signal axi_i_s : nsl_amba.axi4_stream.master_t;
  signal axi_o_s : nsl_amba.axi4_stream.slave_t;

  signal committed_o_s : nsl_bnoc.committed.committed_req_t;
  signal committed_i_s : nsl_bnoc.committed.committed_ack_t;

begin

  committed_tdata  <= std_logic_vector(committed_o_s.data);
  committed_tlast  <= std_logic(committed_o_s.last);
  committed_tvalid <= std_logic(committed_o_s.valid);
  committed_i_s.ready <= std_ulogic(committed_tready);

  axi_pack: nsl_amba.packer.axi4_stream_slave_packer
    generic map(
      config_c => config_c
      )
    port map(
      tvalid => axi_tvalid,
      tready => axi_tready,
      tdata => axi_tdata,
      tlast => axi_tlast,

      stream_i => axi_o_s,
      stream_o => axi_i_s
      );

  adapter: entity nsl_bnoc.axi4_stream_to_committed
    port map(
      clock_i => std_ulogic(clock),
      reset_n_i => std_ulogic(resetn),

      axi_i => axi_i_s,
      axi_o => axi_o_s,

      committed_o => committed_o_s,
      committed_i => committed_i_s
      );

end architecture;
