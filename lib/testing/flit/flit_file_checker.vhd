library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library testing;
use testing.fifo.all;
use testing.flit.all;

library nsl;
use nsl.flit.all;

entity flit_file_checker is
  generic(
    filename: string
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in flit_cmd;
    p_in_ack   : out flit_ack;

    p_done     : out std_ulogic
    );
end entity;

architecture rtl of flit_file_checker is
begin

  check: testing.fifo.fifo_file_checker
    generic map(
      width => 8,
      filename => filename
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_full_n => p_in_ack.ack,
      p_write => p_in_val.val,
      p_data => p_in_val.data,
      p_done => p_done
      );

end architecture;
