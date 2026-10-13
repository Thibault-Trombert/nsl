library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_amba;
use nsl_bnoc.axi_adapter.all;
use nsl_amba.axi4_stream.all;

-- Vivado IP packaging boundary for nsl_bnoc.axi_adapter.committed_to_axi4_stream:
-- the real entity's ports use NSL record types (committed_req_t/committed_ack_t,
-- nsl_amba.axi4_stream.master_t/slave_t), which Vivado's IP packager rejects at
-- the top level. This wrapper flattens both sides to primitive types. Both
-- resulting port groups use the standard _t{data,valid,last,ready} naming
-- convention, so Vivado auto-detects them as axis_rtl interfaces (named
-- "committed" and "axi") without needing custom X_INTERFACE_INFO.
entity committed_to_axi4_stream_ip_top is
  generic(
    max_length_l2_c       : integer := 11;
    max_packet_count_l2_c : integer := 4
    );
  port(
    clock : in std_logic;
    resetn : in std_logic;

    committed_tdata  : in  std_logic_vector(7 downto 0) := x"00";
    committed_tlast  : in  std_logic := '0';
    committed_tvalid : in  std_logic := '0';
    committed_tready : out std_logic;

    axi_tdata  : out std_logic_vector(7 downto 0);
    axi_tlast  : out std_logic;
    axi_tvalid : out std_logic;
    axi_tready : in  std_logic := '1'
    );
end entity;

architecture beh of committed_to_axi4_stream_ip_top is

  constant config_c : nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(1, last => true);

  signal committed_i_s : nsl_bnoc.committed.committed_req_t;
  signal committed_o_s : nsl_bnoc.committed.committed_ack_t;

  signal axi_o_s : nsl_amba.axi4_stream.master_t;
  signal axi_i_s : nsl_amba.axi4_stream.slave_t;

begin

  committed_i_s.data  <= std_ulogic_vector(committed_tdata);
  committed_i_s.last  <= std_ulogic(committed_tlast);
  committed_i_s.valid <= std_ulogic(committed_tvalid);
  committed_tready <= std_logic(committed_o_s.ready);

  axi_pack: nsl_amba.packer.axi4_stream_master_packer
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

  adapter: entity nsl_bnoc.committed_to_axi4_stream
    generic map(
      max_length_l2_c => max_length_l2_c,
      max_packet_count_l2_c => max_packet_count_l2_c
      )
    port map(
      clock_i => std_ulogic(clock),
      reset_n_i => std_ulogic(resetn),

      committed_i => committed_i_s,
      committed_o => committed_o_s,

      axi_o => axi_o_s,
      axi_i => axi_i_s
      );

end architecture;
