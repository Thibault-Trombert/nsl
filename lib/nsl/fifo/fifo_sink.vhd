library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity fifo_sink is
  generic (
    width: integer
    );
  port (
    p_resetn  : in  std_ulogic;
    p_clk     : in  std_ulogic;

    p_in_ready : out std_ulogic;
    p_in_valid  : in std_ulogic;
    p_in_data   : in std_ulogic_vector(width-1 downto 0)
    );
end fifo_sink;

architecture rtl of fifo_sink is

begin

  p_in_ready <= '1';
  
end rtl;
