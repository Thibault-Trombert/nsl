library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package ti is

  component ti_easyscale is
    generic(
      p_clk_hz   : natural range 1000000 to 100000000
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_easyscale: inout std_logic;

      p_dev_addr : in std_ulogic_vector(7 downto 0);
      p_ack_req  : in std_ulogic;
      p_reg_addr : in std_ulogic_vector(1 downto 0);
      p_data     : in std_ulogic_vector(4 downto 0);
      p_start    : in std_ulogic;

      p_busy     : out std_ulogic;
      p_dev_ack  : out std_ulogic
      );
  end component;

end package ti;
