library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library testing;
use testing.fifo.all;
use testing.flit.all;

library nsl;
use nsl.flit.all;

entity flit_file_reader is
  generic(
    filename: string
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_out_val   : out flit_cmd;
    p_out_ack   : in flit_ack;

    p_done : out std_ulogic
    );
end entity;

architecture rtl of flit_file_reader is
begin

  gen: testing.fifo.fifo_file_reader
    generic map(
      width => 8,
      filename => filename
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_empty_n => p_out_val.val,
      p_read => p_out_ack.ack,
      p_data => p_out_val.data,
      p_done => p_done
      );

end architecture;
