library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.flit.all;

package swd is

  function swd_cmd_read_build(
    ad : boolean;
    a : natural range 0 to 3
    ) return std_ulogic_vector;

  function swd_cmd_write_build(
    ad : boolean;
    a : natural range 0 to 3
    ) return std_ulogic_vector;

  constant SWD_CMD_RESET : std_ulogic_vector(7 downto 0):= x"20";
  constant SWD_CMD_READ  : std_ulogic_vector(7 downto 0):= x"08";
  constant SWD_CMD_WRITE : std_ulogic_vector(7 downto 0):= x"00";

  constant SWD_RSP_READ_OK      : std_ulogic_vector(3 downto 0):= x"8";
  constant SWD_RSP_WRITE_OK     : std_ulogic_vector(3 downto 0):= x"0";
  constant SWD_RSP_FAULT        : std_ulogic_vector(3 downto 0):= x"1";
  constant SWD_RSP_OTHER        : std_ulogic_vector(3 downto 0):= x"2";
  constant SWD_RSP_PARITY_ERROR : std_ulogic_vector(3 downto 0):= x"3";
  constant SWD_RSP_RESET_DONE   : std_ulogic_vector(3 downto 0):= x"5";

  component swd_master is
    port(
      p_resetn    : in std_ulogic;
      p_clk       : in std_ulogic;

      p_in_val    : in fifo_framed_cmd;
      p_in_ack    : out fifo_framed_rsp;
      p_out_val   : out fifo_framed_cmd;
      p_out_ack   : in fifo_framed_rsp;

      p_swclk     : out std_ulogic;
      p_swdio_o   : out std_ulogic;
      p_swdio_i   : in std_ulogic;
      p_swdio_oe  : out std_ulogic
      );
  end component;

  component swd_flit_master is
    port(
      p_resetn    : in std_ulogic;
      p_clk       : in std_ulogic;

      p_in_val    : in flit_cmd;
      p_in_ack    : out flit_ack;
      p_out_val   : out flit_cmd;
      p_out_ack   : in flit_ack;

      p_swclk     : out std_ulogic;
      p_swdio_o   : out std_ulogic;
      p_swdio_i   : in std_ulogic;
      p_swdio_oe  : out std_ulogic
      );
  end component;

end package swd;

package body swd is

  function swd_cmd_read_build(
    ad : boolean;
    a : natural range 0 to 3
    ) return std_ulogic_vector is
    variable au : natural;
  begin
    if ad then
      au := 4;
    else
      au := 0;
    end if;
    return std_ulogic_vector(to_unsigned(8 + a + au, 8));
  end swd_cmd_read_build;
  
  function swd_cmd_write_build(
    ad : boolean;
    a : natural range 0 to 3
    ) return std_ulogic_vector is
    variable au : natural;
  begin
    if ad then
      au := 4;
    else
      au := 0;
    end if;
    return std_ulogic_vector(to_unsigned(a + au, 8));
  end swd_cmd_write_build;

end swd;
