library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;

package tpiu is

  component tpiu_unformatter is
    generic(
      test        : boolean := false;
      trace_width : positive range 1 to 32;
      target_id : natural range 0 to 15;
      source_id : natural range 0 to 15
      );
    port(
      p_resetn    : in  std_ulogic;
      p_traceclk  : in  std_ulogic;
      p_clk       : in  std_ulogic;
      p_overflow  : out std_ulogic;
      p_sync      : out std_ulogic;
      p_tracedata : in  std_ulogic_vector(2 * trace_width - 1 downto 0);
      p_out_val   : out fifo_framed_cmd;
      p_out_ack   : in  fifo_framed_rsp
      );
  end component;

end package tpiu;
